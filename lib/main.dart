import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'core/config/app_config.dart';
import 'core/permissions/permission_service.dart';
import 'models/haptic_command_model.dart';
import 'services/auth/auth_service.dart';
import 'services/auth/iot_credentials_repository.dart';
import 'services/auth/token_storage_service.dart';
import 'services/ble/ble_connection_manager.dart';
import 'services/ble/ble_footwear_client.dart';
import 'services/gateway_coordinator.dart';
import 'services/mqtt/mqtt_gateway_service.dart';
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
  String _deviceId = 'HK-2';
  String _targetDeviceId = 'HealthKicks-HK-2';
  String _brokerHost = AppConfig.awsIotEndpoint;
  int _brokerPort = 443;
  MqttConnectionMode _connectionMode = MqttConnectionMode.cloudAwsWebSockets;
  IotCredentialsRepository? _credentialsRepo;

  final PermissionService _permissionService = PermissionService();
  BleConnectionManager? _bleManager;
  BleFootwearClient? _bleClient;
  MqttGatewayService? _mqttService;
  GatewayCoordinator? _coordinator;

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
        _coordinator?.stopRouting();
        _coordinator = null;
        _bleClient?.dispose();
        _bleClient = null;
      } else if (status == BleConnectionStatus.ready && _bleManager?.connectedDevice != null) {
        _onBleDeviceReady(_bleManager!.connectedDevice!);
      }
    });
  }

  @override
  void dispose() {
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

      if (_connectionMode == MqttConnectionMode.cloudAwsWebSockets) {
        _credentialsRepo = IotCredentialsRepository(
          backendBaseUrl: AppConfig.backendBaseUrl,
          tokenStorage: TokenStorageService(),
          authService: widget.authService,
          onLog: (msg, {bool isError = false}) {
            _addLog('AUTH', msg, color: isError ? Colors.red : Colors.cyan);
          },
        );
      }

      _mqttService = MqttGatewayService(
        brokerHost: _brokerHost,
        brokerPort: _brokerPort,
        deviceId: _deviceId,
        connectionMode: _connectionMode,
        credentialsRepository: _credentialsRepo,
        onLog: (msg, {bool isError = false}) {
          _addLog('MQTT', msg, color: isError ? Colors.red : Colors.teal);
        },
      );

      final connected = await _mqttService!.connect();
      if (mounted) {
        setState(() => _mqttConnected = connected);
      }

      if (connected && _bleClient != null) {
        _coordinator = GatewayCoordinator(
          bleClient: _bleClient!,
          mqttService: _mqttService!,
          deviceId: _deviceId,
        );
        _coordinator!.startRouting();
        _addLog('GATEWAY', 'Routage bidirectionnel transparent BLE <-> MQTT réactivé.', color: Colors.green);
      }
    } catch (e) {
      _addLog('MQTT', 'Erreur MQTT inattendue : $e', color: Colors.red);
      if (mounted) {
        setState(() => _mqttConnected = false);
      }
    }
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
      _bleClient = BleFootwearClient(device: device);
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
        _coordinator = GatewayCoordinator(
          bleClient: _bleClient!,
          mqttService: _mqttService!,
          deviceId: _deviceId,
        );
        _coordinator!.startRouting();
        _addLog('GATEWAY', 'Routage bidirectionnel transparent BLE <-> MQTT activé.');
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

    final sessionId = 'sess-${DateTime.now().millisecondsSinceEpoch}';
    _addLog('STUDIO', 'Démarrage session Studio (5.0s, label: test_gait, id: $sessionId)...');

    try {
      if (_coordinator != null) {
        await _coordinator!.triggerStudioSession(
          label: 'test_gait',
          durationSec: 5.0,
          sessionId: sessionId,
        );
      } else {
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

  Future<void> _showMqttSettingsDialog() async {
    final hostController = TextEditingController(
      text: _connectionMode == MqttConnectionMode.localTcp ? _brokerHost : '192.168.1.127',
    );
    final portController = TextEditingController(
      text: (_connectionMode == MqttConnectionMode.localTcp ? _brokerPort : 1883).toString(),
    );
    final deviceIdController = TextEditingController(text: _deviceId);
    var selectedMode = _connectionMode;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isCloud = selectedMode == MqttConnectionMode.cloudAwsWebSockets;

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.settings_ethernet, size: 22),
                  SizedBox(width: 8),
                  Text('Configuration Broker MQTT'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<MqttConnectionMode>(
                      segments: const [
                        ButtonSegment(
                          value: MqttConnectionMode.cloudAwsWebSockets,
                          icon: Icon(Icons.cloud_outlined, size: 16),
                          label: Text('AWS Cloud (SigV4)', style: TextStyle(fontSize: 11)),
                        ),
                        ButtonSegment(
                          value: MqttConnectionMode.localTcp,
                          icon: Icon(Icons.laptop, size: 16),
                          label: Text('Local (Mosquitto)', style: TextStyle(fontSize: 11)),
                        ),
                      ],
                      selected: {selectedMode},
                      onSelectionChanged: (selected) {
                        setDialogState(() {
                          selectedMode = selected.first;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    if (isCloud) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.cloud_done, size: 20, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Connecté à AWS IoT Core (${AppConfig.awsRegion}) via STS',
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Endpoint ATS : ${AppConfig.awsIotEndpoint}',
                              style: TextStyle(fontSize: 11),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Backend STS : ${AppConfig.backendBaseUrl}',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ] else ...[
                      TextField(
                        controller: hostController,
                        decoration: const InputDecoration(
                          labelText: 'Hôte IP Locale (PC)',
                          hintText: 'ex: 192.168.1.127',
                          prefixIcon: Icon(Icons.computer, size: 20),
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: portController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Port Broker',
                          hintText: '1883',
                          helperText: 'Mode direct TCP sans TLS',
                          prefixIcon: Icon(Icons.numbers, size: 20),
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: deviceIdController,
                      decoration: const InputDecoration(
                        labelText: 'Device ID',
                        hintText: 'HK-2',
                        prefixIcon: Icon(Icons.fingerprint, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (!isCloud) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Préréglages locaux rapides :',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          ActionChip(
                            avatar: const Icon(Icons.wifi, size: 14),
                            label: const Text('Local (192.168.1.127)', style: TextStyle(fontSize: 11)),
                            onPressed: () {
                              setDialogState(() {
                                hostController.text = '192.168.1.127';
                                portController.text = '1883';
                              });
                            },
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.wifi, size: 14),
                            label: const Text('Local (192.168.1.105)', style: TextStyle(fontSize: 11)),
                            onPressed: () {
                              setDialogState(() {
                                hostController.text = '192.168.1.105';
                                portController.text = '1883';
                              });
                            },
                          ),
                          ActionChip(
                            avatar: const Icon(Icons.phone_android, size: 14),
                            label: const Text('Émulateur (10.0.2.2)', style: TextStyle(fontSize: 11)),
                            onPressed: () {
                              setDialogState(() {
                                hostController.text = '10.0.2.2';
                                portController.text = '1883';
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Annuler'),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Appliquer & Connecter'),
                  onPressed: () {
                    final newHost = selectedMode == MqttConnectionMode.cloudAwsWebSockets
                        ? AppConfig.awsIotEndpoint
                        : hostController.text.trim();
                    final newPort = selectedMode == MqttConnectionMode.cloudAwsWebSockets
                        ? 443
                        : (int.tryParse(portController.text.trim()) ?? 1883);
                    final newDeviceId = deviceIdController.text.trim();

                    if (newDeviceId.isNotEmpty) {
                      setState(() {
                        _connectionMode = selectedMode;
                        _brokerHost = newHost;
                        _brokerPort = newPort;
                        _deviceId = newDeviceId;
                        _targetDeviceId = 'HealthKicks-$newDeviceId';
                      });
                      Navigator.of(ctx).pop();
                      _addLog(
                        'CONFIG',
                        'Configuration mise à jour : Mode=${selectedMode.name}, Device=$_deviceId${selectedMode == MqttConnectionMode.cloudAwsWebSockets ? ", Backend=${AppConfig.backendBaseUrl}, Endpoint=${AppConfig.awsIotEndpoint}" : ", Broker=$_brokerHost:$_brokerPort"}',
                      );
                      _connectMqtt();
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('HealthKicks BLE-to-MQTT Gateway'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Configuration Broker MQTT',
            onPressed: _showMqttSettingsDialog,
          ),
          InkWell(
            onTap: _showMqttSettingsDialog,
            borderRadius: BorderRadius.circular(16),
            child: Container(
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
                    const SizedBox(width: 4),
                    const Text('AWS / MQTT', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                InkWell(
                  onTap: _showMqttSettingsDialog,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: Icon(
                      Icons.settings,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            InkWell(
              onTap: _showMqttSettingsDialog,
              child: Text(
                _connectionMode == MqttConnectionMode.cloudAwsWebSockets
                    ? 'AWS SigV4 (Port 443 WSS)'
                    : '$_brokerHost:$_brokerPort (TCP)',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
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
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 28,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                      onPressed: _connectMqtt,
                      child: const Text('Re-connecter', style: TextStyle(fontSize: 11)),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  height: 28,
                  width: 32,
                  child: IconButton.outlined(
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.edit, size: 14),
                    tooltip: 'Configurer broker',
                    onPressed: _showMqttSettingsDialog,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
