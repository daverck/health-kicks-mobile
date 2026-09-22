import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'core/config/app_config.dart';
import 'core/constants/ble_constants.dart';
import 'core/permissions/permission_service.dart';
import 'models/activity_detection_model.dart';
import 'models/haptic_command_model.dart';
import 'models/log_entry_model.dart';
import 'models/studio_session_model.dart';
import 'models/step_data_model.dart';
import 'services/auth/auth_service.dart';
import 'services/auth/iot_credentials_repository.dart';
import 'services/auth/token_storage_service.dart';
import 'services/background_surveillance_service.dart';
import 'services/ble/ble_connection_manager.dart';
import 'services/ble/ble_footwear_client.dart';
import 'services/gateway_coordinator.dart';
import 'services/mqtt/mqtt_gateway_service.dart';
import 'services/studio/studio_api_service.dart';
import 'services/event_history_service.dart';
import 'services/inactivity_settings_service.dart';
import 'services/local_storage/step_storage_service.dart';
import 'services/step_sync_service.dart';
import 'ui/screens/detection_events_history_screen.dart';
import 'ui/screens/event_logs_screen.dart';
import 'ui/screens/login_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/screens/steps_history_screen.dart';
import 'ui/widgets/recent_activities_card.dart';
import 'ui/widgets/step_counter_card.dart';
import 'ui/widgets/studio_session_dialog.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HealthKicksApp());
}

class HealthKicksApp extends StatelessWidget {
  final AuthService? authService;

  const HealthKicksApp({super.key, this.authService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HealthKicks Mobile',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: AuthGate(authService: authService),
    );
  }
}

/// Route guard: checks for presence of a valid JWT session at startup.
class AuthGate extends StatefulWidget {
  final AuthService? authService;

  const AuthGate({super.key, this.authService});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AuthService _authService;
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ??
        AuthService(
          tokenStorage: TokenStorageService(),
        );
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await _authService.initialize();
    if (mounted) {
      setState(() {
        _isChecking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF0F766E)),
              SizedBox(height: 16),
              Text(
                'Vérification de session...',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _authService,
      builder: (context, _) {
        if (_authService.state == AuthState.authenticated) {
          return GatewayDashboardScreen(
            authService: _authService,
            onLogout: () async {
              await _authService.logout();
            },
          );
        }

        return LoginScreen(
          authService: _authService,
          onLoginSuccess: () {
            // State change via notifyListeners() automatically switches screen
          },
        );
      },
    );
  }
}

class GatewayDashboardScreen extends StatefulWidget {
  final AuthService? authService;
  final VoidCallback? onLogout;

  const GatewayDashboardScreen({
    super.key,
    this.authService,
    this.onLogout,
  });

  @override
  State<GatewayDashboardScreen> createState() => _GatewayDashboardScreenState();
}

class _GatewayDashboardScreenState extends State<GatewayDashboardScreen> with WidgetsBindingObserver {
  final String _deviceId = 'HK-2';
  final String _targetDeviceId = 'HealthKicks-HK-2';
  IotCredentialsRepository? _credentialsRepo;

  final PermissionService _permissionService = PermissionService();
  late final BackgroundSurveillanceService _surveillanceService;
  BleConnectionManager? _bleManager;
  BleFootwearClient? _bleClient;
  MqttGatewayService? _mqttService;
  GatewayCoordinator? _coordinator;
  StudioApiService? _studioApiService;
  StreamSubscription<StudioSessionModel>? _studioSavedSub;

  BleConnectionStatus _bleStatus = BleConnectionStatus.disconnected;
  BluetoothDevice? _connectedDevice;
  int _mtu = 23;
  bool _mqttConnected = false;
  StepDataModel? _latestStepData;
  final List<ActivityDetectionModel> _recentActivities = [];
  DateTime? _lastInactivityToastTime;

  final StepStorageService _stepStorageService = StepStorageService();
  late final StepSyncService _stepSyncService;
  late final InactivitySettingsService _inactivitySettingsService;

  final List<LogEntry> _logs = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _inactivitySettingsService = InactivitySettingsService();
    unawaited(_inactivitySettingsService.loadSettings());
    _stepSyncService = StepSyncService(
      storageService: _stepStorageService,
      tokenStorage: TokenStorageService(),
      authService: widget.authService,
      backendBaseUrl: AppConfig.backendBaseUrl,
      onLog: (msg, {bool isError = false}) {
        _addLog('SYNC', msg, color: isError ? Colors.red : Colors.cyan);
      },
    );
    _stepSyncService.startPeriodicSync(deviceId: _deviceId);
    unawaited(_loadInitialDailySteps());
    _surveillanceService = BackgroundSurveillanceService(
      onLog: (tag, msg, {bool isError = false}) {
        _addLog(tag, msg, color: isError ? Colors.red : Colors.cyan);
      },
    );
    _surveillanceService.initialize();
    _ensureBleManager();
    _initGateway();
  }

  /// Loads today's step count initially from SQLite offline storage and updates from cloud history.
  Future<void> _loadInitialDailySteps() async {
    try {
      // 1. Query SQLite local storage for immediate offline display
      final now = DateTime.now();
      final localRecord = await _stepStorageService.getDailySteps(now);
      if (localRecord != null && mounted) {
        setState(() {
          _latestStepData = StepDataModel(
            totalSteps: localRecord.totalSteps,
            walkSteps: localRecord.walkSteps,
            runSteps: localRecord.runSteps,
            stairsSteps: localRecord.stairsSteps,
            unclassifiedSteps: localRecord.unclassifiedSteps,
            cadenceSpm: 0,
            timestamp: now,
          );
        });
      }

      // 2. Query cloud history for today's steps (recovers steps on fresh login / new device)
      final cloudSteps = await _stepSyncService.fetchTodaySteps(deviceId: _deviceId);
      if (cloudSteps != null && mounted) {
        final currentTotal = _latestStepData?.totalSteps ?? 0;
        if (cloudSteps.totalSteps >= currentTotal) {
          setState(() {
            _latestStepData = cloudSteps;
          });
          await _stepStorageService.recordStepSnapshot(DateTime.now(), cloudSteps);
          final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
          await _stepStorageService.markDaysSynced([todayStr]);
        }
      }
    } catch (e) {
      _addLog('SYNC', 'Erreur chargement initial des pas : $e', color: Colors.orange);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final isForeground = state == AppLifecycleState.resumed;
    _stepSyncService.setForegroundState(isForeground);

    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      unawaited(_stepSyncService.flushImmediateSync(deviceId: _deviceId));
    }
  }

  void _ensureBleManager() {
    if (_bleManager != null) return;

    _bleManager = BleConnectionManager(
      permissionService: _permissionService,
      onLog: (msg) {
        final isError = msg.contains('Erreur') || msg.contains('refusé') || msg.contains('Échec');
        _addLog(
          msg.startsWith('[PERM]') ? 'PERM' : 'BLE',
          msg.replaceFirst(RegExp(r'^\[(BLE|PERM)\]\s*'), ''),
          color: isError ? Colors.red : null,
        );
      },
    );

    _bleManager!.statusStream.listen((status) {
      if (!mounted) return;
      setState(() {
        _bleStatus = status;
        _connectedDevice = _bleManager?.connectedDevice;
        _mtu = _bleManager?.negotiatedMtu ?? 23;
      });

      _surveillanceService.onBleStatusChanged(
        status,
        deviceName: _bleManager?.connectedDevice?.platformName ?? _targetDeviceId,
      );

      _addLog('BLE', 'Statut connexion : ${status.name}');
      if (status == BleConnectionStatus.disconnected || status == BleConnectionStatus.scanning) {
        _studioSavedSub?.cancel();
        if (_coordinator != null) {
          _coordinator?.stopRouting();
          _coordinator = null;
        } else {
          _mqttService?.publishGatewayStatus(online: false);
        }
        _bleClient?.dispose();
        _bleClient = null;
        if (status == BleConnectionStatus.disconnected) {
          unawaited(_stepSyncService.flushImmediateSync(deviceId: _deviceId));
        }
      } else if (status == BleConnectionStatus.ready && _bleManager?.connectedDevice != null) {
        _onBleDeviceReady(_bleManager!.connectedDevice!);
      }
    });
  }

  bool _isDisposed = false;

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _inactivitySettingsService.dispose();
    _stepSyncService.dispose();
    _stepStorageService.close();
    _studioSavedSub?.cancel();
    _coordinator?.stopRouting();
    _bleClient?.dispose();
    _bleManager?.dispose();
    _surveillanceService.dispose();
    _mqttService?.disconnect();
    super.dispose();
  }

  void _addLog(String tag, String message, {Color? color}) {
    if (!mounted || _isDisposed) return;
    setState(() {
      _logs.add(LogEntry(
        timestamp: DateTime.now(),
        tag: tag,
        message: message,
        color: color ?? _colorForTag(tag),
      ));
    });
  }

  Color _colorForTag(String tag) {
    switch (tag) {
      case 'UI':
        return Colors.blueGrey;
      case 'BLE':
        return Colors.blue;
      case 'MQTT':
        return Colors.teal;
      case 'CONFIG':
        return Colors.cyan;
      case 'ACTIVITY':
        return Colors.orange;
      case 'BURST':
      case 'CRC32':
        return Colors.purple;
      case 'HAPTIC':
        return Colors.amber;
      case 'STUDIO':
        return Colors.indigo;
      case 'GATEWAY':
        return Colors.green;
      case 'ERROR':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Future<void> _connectMqtt() async {
    try {
      _credentialsRepo ??= IotCredentialsRepository(
        backendBaseUrl: AppConfig.backendBaseUrl,
        tokenStorage: TokenStorageService(),
        authService: widget.authService,
        onLog: (msg, {bool isError = false}) {
          _addLog('AUTH', msg, color: isError ? Colors.red : Colors.cyan);
        },
      );

      var currentUserId = widget.authService?.currentUserId;
      if (currentUserId == null || currentUserId.isEmpty) {
        currentUserId = await TokenStorageService().getUserIdFromToken();
      }

      // If userId is not yet resolved (e.g. async token initialization in progress),
      // defer connection by actively waiting up to 3 seconds.
      if (currentUserId == null || currentUserId.isEmpty) {
        for (int i = 0; i < 6 && (currentUserId == null || currentUserId.isEmpty); i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (!mounted || _isDisposed) return;
          currentUserId = widget.authService?.currentUserId;
          if (currentUserId == null || currentUserId.isEmpty) {
            currentUserId = await TokenStorageService().getUserIdFromToken();
          }
        }
      }

      if (currentUserId == null || currentUserId.isEmpty || currentUserId == 'unknown') {
        _addLog(
          'MQTT',
          'Connexion MQTT différée : utilisateur non authentifié ou userId introuvable.',
          color: Colors.amber,
        );
        if (mounted) {
          setState(() => _mqttConnected = false);
        }
        return;
      }

      // Recreate MQTT service if user has changed
      if (_mqttService != null && _mqttService!.userId != currentUserId) {
        _mqttService?.disconnect();
        _mqttService = null;
      }

      _mqttService ??= MqttGatewayService(
        deviceId: _deviceId,
        userId: currentUserId,
        credentialsRepository: _credentialsRepo!,
        onLog: (msg, {bool isError = false}) {
          _addLog('MQTT', msg, color: isError ? Colors.red : Colors.teal);
        },
        onConnectionRestored: () {
          if (_bleClient != null &&
              (_bleStatus == BleConnectionStatus.ready || _bleStatus == BleConnectionStatus.connected)) {
            _addLog('GATEWAY', 'Reconnexion MQTT : re-synchronisation du statut BLE online...', color: Colors.green);
            _coordinator?.publishBleStatus(online: true);
          }
        },
      );

      final connected = await _mqttService!.connect();
      if (mounted) {
        setState(() => _mqttConnected = connected);
      }

      if (connected) {
        final isBleReady = _bleClient != null &&
            (_bleStatus == BleConnectionStatus.ready || _bleStatus == BleConnectionStatus.connected);

        if (isBleReady) {
          if (_coordinator == null) {
            _setupCoordinator();
          } else {
            _addLog('GATEWAY', 'MQTT connecté : synchronisation immédiate de la présence BLE online...', color: Colors.green);
            await _coordinator!.publishBleStatus(online: true);
          }
        } else if (_bleStatus == BleConnectionStatus.scanning || _bleStatus == BleConnectionStatus.disconnected) {
          _addLog('GATEWAY', 'MQTT connecté et BLE en mode scan/déconnecté : notification statut offline...', color: Colors.grey);
          await _mqttService!.publishDeviceStatus(online: false);
        }
      }
    } catch (e) {
      _addLog('MQTT', 'Erreur MQTT inattendue : $e', color: Colors.red);
      if (mounted) {
        setState(() => _mqttConnected = false);
      }
    }
  }

  void _setupCoordinator() {
    if (_bleClient == null || _mqttService == null) return;

    _coordinator?.stopRouting(notifyOffline: false);
    _studioSavedSub?.cancel();

    _studioApiService ??= StudioApiService(
      backendBaseUrl: AppConfig.backendBaseUrl,
      tokenStorage: TokenStorageService(),
      authService: widget.authService,
      onLog: (msg, {bool isError = false}) {
        _addLog('STUDIO', msg, color: isError ? Colors.red : Colors.green);
      },
    );

    _coordinator = GatewayCoordinator(
      bleClient: _bleClient!,
      mqttService: _mqttService!,
      studioApiService: _studioApiService,
      deviceId: _deviceId,
      onLog: (msg, {bool isError = false}) {
        _addLog('GATEWAY', msg, color: isError ? Colors.red : Colors.green);
      },
    );

    _studioSavedSub = _coordinator!.studioSessionSavedStream.listen((savedSession) {
      if (mounted) {
        final shortId = savedSession.sessionId.length > 8
            ? savedSession.sessionId.substring(0, 8)
            : savedSession.sessionId;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Session Studio synchronisée ($shortId, ${savedSession.readings.length} trames)',
            ),
            backgroundColor: const Color(0xFF0F766E),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });

    _coordinator!.startRouting();
    _addLog('GATEWAY', 'Routage bidirectionnel BLE <-> MQTT + Sync REST activé.', color: Colors.green);
  }

  Future<void> _initGateway() async {
    _addLog('INIT', 'Démarrage de la passerelle HealthKicks...');
    _ensureBleManager();

    // 1. Initialize MQTT broker in background without blocking BLE initialization
    unawaited(_connectMqtt());

    // 2. Request required permissions and start BLE scan immediately upon grant
    try {
      final perms = await _permissionService.requestDetailedBlePermissions(
        onLog: (msg) => _addLog('PERM', msg),
      );
      _addLog(
        'PERM',
        perms.isGranted
            ? 'Permissions BLE accordées (${perms.details}).'
            : 'Permissions BLE incomplètes (${perms.details}).',
        color: perms.isGranted ? Colors.green : Colors.orange,
      );

      if (perms.isGranted) {
        await _startBleScan(fromButton: false);
      } else if (perms.isPermanentlyDenied && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Permissions Bluetooth nécessaires. Veuillez les activer dans les Paramètres.'),
            action: SnackBarAction(
              label: 'Paramètres',
              onPressed: () => _permissionService.openSettings(),
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      _addLog('PERM', 'Vérification des permissions : $e', color: Colors.orange);
      await _startBleScan(fromButton: false);
    }
  }

  Future<void> _startBleScan({bool fromButton = false}) async {
    if (fromButton) {
      _addLog('UI', 'Bouton Re-scanner pressé');
    }

    _ensureBleManager();

    // When starting scan, device is no longer active: publish offline
    if (_coordinator != null) {
      _coordinator?.stopRouting(notifyOffline: true);
      _coordinator = null;
    } else {
      _mqttService?.publishDeviceStatus(online: false);
    }
    _bleClient?.dispose();
    _bleClient = null;

    // Cancel any active scan before restarting
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    _addLog('BLE', 'Démarrage du scan large pour "$_targetDeviceId" ou Service GATT...');
    try {
      await _bleManager!.startAutoConnect(
        targetDeviceId: _targetDeviceId,
        timeout: BleConstants.defaultScanTimeout,
        onLog: (msg) {
          final isError = msg.contains('Erreur') || msg.contains('refusé') || msg.contains('Échec');
          _addLog(
            'BLE',
            msg,
            color: isError
                ? Colors.red
                : (msg.contains('Connecté') ? Colors.green : Colors.blueGrey),
          );
        },
      );
    } catch (e) {
      _addLog('BLE', 'Erreur de scan : $e', color: Colors.red);
      if (e.toString().contains('Paramètres') || e.toString().contains('refusé')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Permissions BLE requises : $e'),
              action: SnackBarAction(
                label: 'Paramètres',
                onPressed: () => _permissionService.openSettings(),
              ),
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }
    }
  }

  Future<void> _onBleDeviceReady(BluetoothDevice device) async {
    _addLog('BLE', 'Appareil connecté : ${device.platformName} (MTU: $_mtu octets)');

    try {
      _bleClient = BleFootwearClient(
        device: device,
        onLog: (msg, {bool isError = false}) {
          _addLog('BLE', msg, color: isError ? Colors.red : Colors.blueGrey);
        },
      );
      _addLog('BLE', 'Découverte des services GATT en cours...');
      await _bleClient!.initializeServices();
      _addLog(
        'BLE',
        'Souscription active : Activity (0002), Studio Control (0004), Burst (0005) | Haptique (0003) ${_bleClient!.hasHaptic ? "prêt" : "non trouvé"}',
      );

      // Listen to BLE streams for live event logging and recent activity history
      _bleClient!.activityStream.listen((detection) {
        if (mounted) {
          setState(() {
            _recentActivities.insert(0, detection);
            if (_recentActivities.length > 10) {
              _recentActivities.removeLast();
            }
          });
        }

        _addLog(
          'ACTIVITY',
          '${detection.eventType.toUpperCase()} (${detection.confidencePercent}%) | Chute=${detection.isFall} | Haptique=${detection.isHapticTriggered}',
        );

        if (detection.eventType == 'inactivity_alert' && mounted) {
          final now = DateTime.now();
          if (_lastInactivityToastTime == null || now.difference(_lastInactivityToastTime!).inSeconds >= 30) {
            _lastInactivityToastTime = now;
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.airline_seat_recline_normal, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Rappel d\'inactivité : Vous êtes immobile depuis ${_inactivitySettingsService.thresholdMinutes} minutes. Pensez à faire quelques pas !',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.deepOrange.shade700,
                duration: const Duration(seconds: 4),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      });

      _bleClient!.studioStatusStream.listen((statusMsg) {
        _addLog('STUDIO', 'Signal d\'état : $statusMsg');
      });

      _bleClient!.burstResultStream.listen((result) {
        _addLog(
          'BURST',
          'Réassemblage : ${result.framesRecovered}/${result.totalAnnounced} trames | CRC32 validé : ${result.isCrcValid}',
          color: result.isSuccess ? Colors.green : Colors.red,
        );
      });

      _bleClient!.stepDataStream.listen((stepData) async {
        if (mounted) {
          setState(() {
            _latestStepData = stepData;
          });
        }
        await _stepStorageService.recordStepSnapshot(DateTime.now(), stepData);
      });

      // Synchronize stored inactivity preferences to footwear
      unawaited(_inactivitySettingsService.syncToBle(_bleClient!));

      // Synchronize any stored offline steps upon successful BLE handshake
      unawaited(_stepSyncService.flushImmediateSync(deviceId: _deviceId));

      // Attach bidirectional routing coordinator
      if (_mqttService != null) {
        _setupCoordinator();
      }
    } catch (e) {
      _addLog('BLE', 'Erreur initialisation GATT : $e', color: Colors.red);
    }
  }

  Future<void> _sendTestHapticCommand() async {
    final isConnected = _bleClient != null &&
        (_bleStatus == BleConnectionStatus.ready || _bleStatus == BleConnectionStatus.connected) &&
        _bleClient!.hasHaptic;

    if (!isConnected) {
      _addLog('HAPTIC', 'Chaussure non connectée : impossible d\'émettre la commande.', color: Colors.red);
      return;
    }

    const command = HapticCommandModel(
      commandId: 'manual-test-vib',
      patternId: 0,
      intensity: 200,
      durationMs: 400,
    );

    try {
      _addLog('HAPTIC', 'Écriture sur 0003 (Intensité: ${command.intensity}, Durée: ${command.durationMs} ms)...');
      await _bleClient!.sendHapticCommand(command);
      _addLog('HAPTIC', 'Écriture sur 0003 validée avec succès (GATT write OK).', color: Colors.green);
    } catch (e) {
      _addLog('HAPTIC', 'Échec écriture sur 0003 : $e', color: Colors.red);
    }
  }

  void _showStudioSessionDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => StudioSessionDialog(
        onStartSession: ({required String label, required double durationSec}) async {
          await _triggerStudioSession(label: label, durationSec: durationSec);
        },
      ),
    );
  }

  Future<void> _triggerStudioSession({
    required String label,
    required double durationSec,
  }) async {
    final isConnected = _bleClient != null &&
        (_bleStatus == BleConnectionStatus.ready || _bleStatus == BleConnectionStatus.connected) &&
        _bleClient!.hasStudioControl;

    if (!isConnected) {
      _addLog('STUDIO', 'Chaussure non connectée ou service Studio indisponible.', color: Colors.red);
      return;
    }

    _addLog('STUDIO', 'Démarrage session Studio (${durationSec.toStringAsFixed(1)}s, label: $label)...');

    try {
      // 1. Ensure MQTT service is initialized and connected
      if (_mqttService == null) {
        _addLog('STUDIO', 'Initialisation et connexion au service MQTT AWS IoT...', color: Colors.indigo);
        await _connectMqtt();
      } else if (!_mqttService!.isConnected) {
        _addLog('STUDIO', 'Reconnexion au service MQTT AWS IoT...', color: Colors.indigo);
        await _mqttService!.connect();
      }

      _setupCoordinator();

      if (_coordinator != null) {
        _addLog('STUDIO', 'Réservation REST de la session auprès du backend FastAPI (/commands/studio/start)...');
        await _coordinator!.triggerStudioSession(
          label: label,
          durationSec: durationSec,
        );
      } else {
        _studioApiService ??= StudioApiService(
          backendBaseUrl: AppConfig.backendBaseUrl,
          tokenStorage: TokenStorageService(),
          authService: widget.authService,
          onLog: (msg, {bool isError = false}) {
            _addLog('STUDIO', msg, color: isError ? Colors.red : Colors.green);
          },
        );

        String sessionId;
        try {
          _addLog('STUDIO', 'Réservation REST directe auprès du backend FastAPI...');
          final resp = await _studioApiService!.startStudioSession(
            deviceId: _deviceId,
            label: label,
            durationSec: durationSec,
          );
          sessionId = resp.sessionId;
          _addLog('STUDIO', 'Session réservée : $sessionId', color: Colors.green);
        } catch (e) {
          sessionId = const Uuid().v4();
          _addLog('STUDIO', 'Erreur réservation REST ($e), fallback local : $sessionId', color: Colors.orange);
        }

        await _bleClient!.startStudioSession(
          label: label,
          durationSec: durationSec,
          sessionId: sessionId,
        );
      }
      _addLog('STUDIO', 'Ordre START envoyé à la chaussure. En attente du flux burst...', color: Colors.indigo);
    } catch (e) {
      _addLog('STUDIO', 'Échec lancement session Studio : $e', color: Colors.red);
    }
  }

  void _openEventLogsScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventLogsScreen(
          logs: _logs,
          onClearLogs: () => setState(() => _logs.clear()),
          deviceId: _deviceId,
          deviceName: _connectedDevice?.platformName.isNotEmpty == true
              ? _connectedDevice!.platformName
              : _targetDeviceId,
          bleStatus: _bleStatus.name,
          mtu: _mtu,
          mqttConnected: _mqttConnected,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isClinicianOrAdmin = widget.authService?.currentUser?.role == 'admin' ||
        widget.authService?.currentUser?.role == 'clinician';

    return Scaffold(
      appBar: AppBar(
        title: const Text('HealthKicks BLE-to-MQTT Gateway'),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.perm_identity, size: 16),
                const SizedBox(width: 4),
                Text(
                  _deviceId,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.show_chart_rounded),
            tooltip: 'Historique des Pas',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => StepsHistoryScreen(
                    storageService: _stepStorageService,
                    syncService: _stepSyncService,
                    deviceId: _deviceId,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Historique des Événements',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DetectionEventsHistoryScreen(
                    service: EventHistoryService(
                      backendBaseUrl: AppConfig.backendBaseUrl,
                      tokenStorage: TokenStorageService(),
                      authService: widget.authService,
                    ),
                    deviceId: _deviceId,
                    liveActivities: _recentActivities,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.article_outlined),
            tooltip: 'Journal d\'événements',
            onPressed: _openEventLogsScreen,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Paramètres',
            onPressed: _openSettingsScreen,
          ),
          if (widget.onLogout != null)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Se déconnecter',
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Déconnexion'),
                    content: const Text('Voulez-vous vraiment vous déconnecter de votre session HealthKicks ?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Annuler'),
                      ),
                      FilledButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          widget.onLogout!();
                        },
                        child: const Text('Déconnexion'),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Discreet Status Indicators (Tappable to Settings)
              _buildDiscreetStatusRow(),
              const SizedBox(height: 10),

              // 2. Step Counter Card
              StepCounterCard(
                stepData: _latestStepData,
                onOpenHistory: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StepsHistoryScreen(
                        storageService: _stepStorageService,
                        syncService: _stepSyncService,
                        deviceId: _deviceId,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),

              // 3. Recent Activities History Card
              RecentActivitiesCard(
                activities: _recentActivities,
                onViewAll: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DetectionEventsHistoryScreen(
                        service: EventHistoryService(
                          backendBaseUrl: AppConfig.backendBaseUrl,
                          tokenStorage: TokenStorageService(),
                          authService: widget.authService,
                        ),
                        deviceId: _deviceId,
                        liveActivities: _recentActivities,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),

              // 4. Action Test Controls
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.vibration),
                      label: const Text('Test Haptique'),
                      onPressed: _sendTestHapticCommand,
                    ),
                  ),
                  if (isClinicianOrAdmin) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Studio'),
                        onPressed: _showStudioSessionDialog,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSettingsScreen() {
    final isConnected = _bleClient != null &&
        (_bleStatus == BleConnectionStatus.ready || _bleStatus == BleConnectionStatus.connected);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          surveillanceService: _surveillanceService,
          inactivitySettingsService: _inactivitySettingsService,
          bleClient: _bleClient,
          isFootwearConnected: isConnected,
          studioStatusStream: _bleClient?.studioStatusStream,
          bleStatus: _bleStatus,
          isMqttConnected: _mqttConnected,
          deviceName: _connectedDevice?.platformName,
          targetDeviceId: _targetDeviceId,
          mtu: _mtu,
          onStartBleScan: () => _startBleScan(fromButton: true),
          onDisconnectBle: isConnected
              ? () async {
                  await _bleManager?.disconnect();
                }
              : null,
          onReconnectMqtt: _connectMqtt,
          onCalibrateSensor: isConnected
              ? () async {
                  _addLog('CONFIG', 'Envoi ordre de calibration d\'assiette (0x05)...');
                  await _bleClient?.sendCalibrateZeroCommand();
                }
              : null,
        ),
      ),
    );
  }

  Widget _buildDiscreetStatusRow() {
    final isBleReady = (_bleStatus == BleConnectionStatus.ready || _bleStatus == BleConnectionStatus.connected) &&
        _bleClient != null;
    final isBleScanning = _bleStatus == BleConnectionStatus.scanning;
    final isBleConnecting = _bleStatus == BleConnectionStatus.connecting;

    final Color bleColor = isBleReady
        ? Colors.green
        : (isBleScanning || isBleConnecting ? Colors.orange : Colors.grey);
    final IconData bleIcon = isBleReady
        ? Icons.bluetooth_connected
        : (isBleScanning || isBleConnecting ? Icons.bluetooth_searching : Icons.bluetooth_disabled);
    final String bleTooltip = isBleReady
        ? 'Bluetooth connecté (${_connectedDevice?.platformName.isNotEmpty == true ? _connectedDevice!.platformName : _targetDeviceId}, MTU: $_mtu)'
        : (isBleScanning ? 'Bluetooth : Recherche en cours...' : (isBleConnecting ? 'Bluetooth : Connexion...' : 'Bluetooth déconnecté'));

    final Color mqttColor = _mqttConnected ? Colors.green : Colors.grey;
    final IconData mqttIcon = _mqttConnected ? Icons.cloud_done : Icons.cloud_off;
    final String mqttTooltip = _mqttConnected
        ? 'AWS IoT Core : Connecté (Port 443 WSS, ${AppConfig.awsRegion})'
        : 'AWS IoT Core : Déconnecté';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.directions_walk_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'Chaussure $_deviceId',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: bleTooltip,
                child: Material(
                  color: bleColor.withValues(alpha: 0.12),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _openSettingsScreen,
                    child: Padding(
                      padding: const EdgeInsets.all(7.0),
                      child: Icon(bleIcon, color: bleColor, size: 18),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: mqttTooltip,
                child: Material(
                  color: mqttColor.withValues(alpha: 0.12),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _openSettingsScreen,
                    child: Padding(
                      padding: const EdgeInsets.all(7.0),
                      child: Icon(mqttIcon, color: mqttColor, size: 18),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
