import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:uuid/uuid.dart';

import 'core/config/app_config.dart';
import 'core/permissions/permission_service.dart';
import 'models/haptic_command_model.dart';
import 'models/studio_session_model.dart';
import 'services/auth/auth_service.dart';
import 'services/auth/iot_credentials_repository.dart';
import 'services/auth/token_storage_service.dart';
import 'services/ble/ble_connection_manager.dart';
import 'services/ble/ble_footwear_client.dart';
import 'services/gateway_coordinator.dart';
import 'services/mqtt/mqtt_gateway_service.dart';
import 'services/studio/studio_api_service.dart';
import 'ui/screens/login_screen.dart';

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

/// Garde de routage : vérifie la présence d'une session JWT valide au démarrage.
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
            // Le changement d'état via notifyListeners() bascule automatiquement l'écran
          },
        );
      },
    );
  }
}


class LogEntry {
  final DateTime timestamp;
  final String tag;
  final String message;
  final Color color;

  const LogEntry({
    required this.timestamp,
    required this.tag,
    required this.message,
    required this.color,
  });
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

class _GatewayDashboardScreenState extends State<GatewayDashboardScreen> {
  final String _deviceId = 'HK-2';
  final String _targetDeviceId = 'HealthKicks-HK-2';
  IotCredentialsRepository? _credentialsRepo;

  final PermissionService _permissionService = PermissionService();
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

  final List<LogEntry> _logs = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _ensureBleManager();
    _initGateway();
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

      _addLog('BLE', 'Statut connexion : ${status.name}');
      if (status == BleConnectionStatus.disconnected) {
        _studioSavedSub?.cancel();
        if (_coordinator != null) {
          _coordinator?.stopRouting();
          _coordinator = null;
        } else {
          _mqttService?.publishGatewayStatus(online: false);
        }
        _bleClient?.dispose();
        _bleClient = null;
      } else if (status == BleConnectionStatus.ready && _bleManager?.connectedDevice != null) {
        _onBleDeviceReady(_bleManager!.connectedDevice!);
      }
    });
  }

  @override
  void dispose() {
    _studioSavedSub?.cancel();
    _coordinator?.stopRouting();
    _bleClient?.dispose();
    _bleManager?.dispose();
    _mqttService?.disconnect();
    _scrollController.dispose();
    super.dispose();
  }

  void _addLog(String tag, String message, {Color? color}) {
    if (!mounted) return;
    setState(() {
      _logs.add(LogEntry(
        timestamp: DateTime.now(),
        tag: tag,
        message: message,
        color: color ?? _colorForTag(tag),
      ));
    });

    // Auto-scroll to latest log entry
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
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
      _coordinator?.stopRouting();
      _coordinator = null;
      _mqttService?.disconnect();

      _credentialsRepo ??= IotCredentialsRepository(
        backendBaseUrl: AppConfig.backendBaseUrl,
        tokenStorage: TokenStorageService(),
        authService: widget.authService,
        onLog: (msg, {bool isError = false}) {
          _addLog('AUTH', msg, color: isError ? Colors.red : Colors.cyan);
        },
      );

      final currentUserId = widget.authService?.currentUser?.id.toString();

      _mqttService = MqttGatewayService(
        deviceId: _deviceId,
        userId: currentUserId,
        credentialsRepository: _credentialsRepo!,
        onLog: (msg, {bool isError = false}) {
          _addLog('MQTT', msg, color: isError ? Colors.red : Colors.teal);
        },
      );

      final connected = await _mqttService!.connect();
      if (mounted) {
        setState(() => _mqttConnected = connected);
      }

      if (connected && _bleClient != null) {
        _setupCoordinator();
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

    _coordinator?.stopRouting();
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

    // 1. Initialiser le broker MQTT en arrière-plan sans bloquer l'initialisation BLE
    unawaited(_connectMqtt());

    // 2. Solliciter les permissions requises et démarrer le scan BLE immédiatement dès accord
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

    // Annuler tout scan en cours avant de relancer
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    _addLog('BLE', 'Démarrage du scan large pour "$_targetDeviceId" ou Service GATT...');
    try {
      await _bleManager!.startAutoConnect(
        targetDeviceId: _targetDeviceId,
        timeout: const Duration(seconds: 10),
        onLog: (msg) {
          final isError = msg.contains('Erreur') || msg.contains('refusé') || msg.contains('Échec');
          _addLog(
            msg.startsWith('[PERM]') ? 'PERM' : 'BLE',
            msg.replaceFirst(RegExp(r'^\[(BLE|PERM)\]\s*'), ''),
            color: isError ? Colors.red : null,
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
          _addLog('BLE', msg, color: isError ? Colors.red : Colors.blue);
        },
      );
      _addLog('BLE', 'Découverte des services GATT en cours...');
      await _bleClient!.initializeServices();
      _addLog(
        'BLE',
        'Souscription active : Activity (0002), Studio Control (0004), Burst (0005) | Haptique (0003) ${_bleClient!.hasHaptic ? "prêt" : "non trouvé"}',
      );

      // Écoute des flux BLE pour le journal en direct
      _bleClient!.activityStream.listen((detection) {
        _addLog(
          'ACTIVITY',
          '${detection.eventType.toUpperCase()} (${detection.confidencePercent}%) | Chute=${detection.isFall} | Haptique=${detection.isHapticTriggered}',
        );
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

      // Brancher le coordinateur de routage bidirectionnel
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
      _addLog('HAPTIC', '[HAPTIC] Écriture sur 0003 (Intensité: ${command.intensity}, Durée: ${command.durationMs} ms)...');
      await _bleClient!.sendHapticCommand(command);
      _addLog('HAPTIC', '[HAPTIC] Écriture sur 0003 validée avec succès (GATT write OK).', color: Colors.green);
    } catch (e) {
      _addLog('HAPTIC', '[HAPTIC] Échec écriture sur 0003 : $e', color: Colors.red);
    }
  }

  Future<void> _triggerTestStudioSession() async {
    final isConnected = _bleClient != null &&
        (_bleStatus == BleConnectionStatus.ready || _bleStatus == BleConnectionStatus.connected) &&
        _bleClient!.hasStudioControl;

    if (!isConnected) {
      _addLog('STUDIO', 'Chaussure non connectée ou service Studio indisponible.', color: Colors.red);
      return;
    }

    _addLog('STUDIO', 'Démarrage session Studio (5.0s, label: test_gait)...');

    try {
      // 1. S'assurer que le service MQTT est initialisé et connecté
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
          label: 'test_gait',
          durationSec: 5.0,
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
            label: 'test_gait',
            durationSec: 5.0,
          );
          sessionId = resp.sessionId;
          _addLog('STUDIO', 'Session réservée : $sessionId', color: Colors.green);
        } catch (e) {
          sessionId = const Uuid().v4();
          _addLog('STUDIO', 'Erreur réservation REST ($e), fallback local : $sessionId', color: Colors.orange);
        }

        await _bleClient!.startStudioSession(
          label: 'test_gait',
          durationSec: 5.0,
          sessionId: sessionId,
        );
      }
      _addLog('STUDIO', 'Ordre START envoyé à la chaussure. En attente du flux burst...', color: Colors.indigo);
    } catch (e) {
      _addLog('STUDIO', 'Échec lancement session Studio : $e', color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HealthKicks BLE-to-MQTT Gateway'),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
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
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Status Cards
              Row(
                children: [
                  Expanded(child: _buildBleCard()),
                  const SizedBox(width: 8),
                  Expanded(child: _buildMqttCard()),
                ],
              ),
              const SizedBox(height: 10),

              // 2. Action Test Controls
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.vibration),
                      label: const Text('Test Haptique'),
                      onPressed: _sendTestHapticCommand,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Studio 5s'),
                      onPressed: _triggerTestStudioSession,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 3. Event Logs Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Journal d\'événements en direct (${_logs.length})',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.clear_all, size: 18),
                    label: const Text('Effacer'),
                    onPressed: () => setState(() => _logs.clear()),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // 4. Console Logs Container
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF1E1E1E)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: _logs.isEmpty
                      ? const Center(
                          child: Text(
                            'Aucun événement enregistré pour le moment.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          itemCount: _logs.length,
                          itemBuilder: (context, index) {
                            final entry = _logs[index];
                            final timeStr =
                                '${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}:${entry.timestamp.second.toString().padLeft(2, '0')}.${entry.timestamp.millisecond.toString().padLeft(3, '0')}';
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    timeStr,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: entry.color.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      entry.tag,
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: entry.color,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      entry.message,
                                      style: const TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBleCard() {
    final isReady = (_bleStatus == BleConnectionStatus.ready || _bleStatus == BleConnectionStatus.connected) &&
        _bleClient != null;
    final isScanning = _bleStatus == BleConnectionStatus.scanning;
    final isConnecting = _bleStatus == BleConnectionStatus.connecting;

    final Color statusColor = isReady
        ? Colors.green
        : (isScanning || isConnecting ? Colors.orange : Colors.grey);

    final String statusText = isReady
        ? 'Connecté (MTU: $_mtu)'
        : (isScanning
            ? 'Scan...'
            : (isConnecting ? 'Connexion...' : 'Déconnecté'));

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bluetooth, color: statusColor, size: 20),
                const SizedBox(width: 4),
                const Text('Bluetooth BLE', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _connectedDevice?.platformName ?? _targetDeviceId,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor),
                ),
                const SizedBox(width: 4),
                Text(statusText, style: TextStyle(fontSize: 11, color: statusColor)),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              height: 28,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => _startBleScan(fromButton: true),
                child: const Text('Re-scanner', style: TextStyle(fontSize: 11)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMqttCard() {
    final Color statusColor = _mqttConnected ? Colors.green : Colors.grey;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.cloud, color: statusColor, size: 20),
                    const SizedBox(width: 6),
                    const Text('AWS IoT Core', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Port 443 WSS (${AppConfig.awsRegion})',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor),
                ),
                const SizedBox(width: 4),
                Text(
                  _mqttConnected ? 'Connecté' : 'Déconnecté',
                  style: TextStyle(fontSize: 11, color: statusColor),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 28,
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: _connectMqtt,
                child: const Text('Re-connecter', style: TextStyle(fontSize: 11)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
