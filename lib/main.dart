import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'core/permissions/permission_service.dart';
import 'models/haptic_command_model.dart';
import 'services/ble/ble_connection_manager.dart';
import 'services/ble/ble_footwear_client.dart';
import 'services/gateway_coordinator.dart';
import 'services/mqtt/mqtt_gateway_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HealthKicksApp());
}

class HealthKicksApp extends StatelessWidget {
  const HealthKicksApp({super.key});

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
      home: const GatewayDashboardScreen(),
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
  const GatewayDashboardScreen({super.key});

  @override
  State<GatewayDashboardScreen> createState() => _GatewayDashboardScreenState();
}

class _GatewayDashboardScreenState extends State<GatewayDashboardScreen> {
  String _deviceId = 'HK-2';
  String _targetDeviceId = 'HealthKicks-HK-2';
  String _brokerHost = '10.0.2.2'; // Gateway broker default (local/emulator)
  int _brokerPort = 1883;

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
    _initGateway();
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

      _mqttService = MqttGatewayService(
        brokerHost: _brokerHost,
        brokerPort: _brokerPort,
        deviceId: _deviceId,
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

    // 1. Solliciter les permissions requises
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
      if (!perms.isGranted && perms.isPermanentlyDenied && mounted) {
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
      _addLog('PERM', 'Vérification des permissions ignorée ($e)', color: Colors.orange);
    }

    // 2. Initialiser le service MQTT
    await _connectMqtt();

    // 3. Initialiser le gestionnaire BLE
    try {
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
        if (status == BleConnectionStatus.ready && _bleManager?.connectedDevice != null) {
          _onBleDeviceReady(_bleManager!.connectedDevice!);
        }
      });

      await _startBleScan();
    } catch (e) {
      _addLog('BLE', 'Initialisation BLE : $e', color: Colors.red);
    }
  }

  Future<void> _startBleScan() async {
    _addLog('UI', 'Bouton Re-scanner pressé');
    if (_bleManager == null) {
      _addLog('BLE', 'Gestionnaire BLE non initialisé.', color: Colors.red);
      return;
    }

    // Annuler tout scan en cours avant de relancer
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    _addLog('BLE', 'Scan en cours pour "$_targetDeviceId" ou Service GATT...');
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
      _addLog('BLE', 'Souscription active : Activity (0002), Studio Control (0004), Burst (0005)');

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
    if (_bleClient == null || _bleStatus != BleConnectionStatus.ready) {
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
      _addLog('HAPTIC', 'Envoi commande haptique (CMD:VIB 400ms, intensité: 200)...');
      await _bleClient!.sendHapticCommand(command);
      _addLog('HAPTIC', 'Commande haptique transmise avec succès au matériel.', color: Colors.green);
    } catch (e) {
      _addLog('HAPTIC', 'Échec transmission haptique : $e', color: Colors.red);
    }
  }

  Future<void> _triggerTestStudioSession() async {
    if (_coordinator == null) {
      _addLog('STUDIO', 'Passerelle non prête : impossible de démarrer la session Studio.', color: Colors.red);
      return;
    }

    final sessionId = 'sess-${DateTime.now().millisecondsSinceEpoch}';
    _addLog('STUDIO', 'Démarrage session Studio (5.0s, label: test_gait, id: $sessionId)...');

    try {
      await _coordinator!.triggerStudioSession(
        label: 'test_gait',
        durationSec: 5.0,
        sessionId: sessionId,
      );
      _addLog('STUDIO', 'Ordre START envoyé à la chaussure. En attente du flux burst...', color: Colors.indigo);
    } catch (e) {
      _addLog('STUDIO', 'Échec lancement session Studio : $e', color: Colors.red);
    }
  }

  Future<void> _showMqttSettingsDialog() async {
    final hostController = TextEditingController(text: _brokerHost);
    final portController = TextEditingController(text: _brokerPort.toString());
    final deviceIdController = TextEditingController(text: _deviceId);

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.settings_ethernet, size: 22),
                  SizedBox(width: 8),
                  Text('Paramètres MQTT'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: hostController,
                      decoration: const InputDecoration(
                        labelText: 'Hôte Broker (IP ou Nom)',
                        hintText: 'ex: 192.168.1.50 ou 10.0.2.2',
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
                        hintText: '1883 (TCP) ou 8883 (TLS)',
                        prefixIcon: Icon(Icons.numbers, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
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
                    const SizedBox(height: 16),
                    Text(
                      'Préréglages :',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ActionChip(
                          label: const Text('Émulateur (10.0.2.2)', style: TextStyle(fontSize: 11)),
                          onPressed: () {
                            setDialogState(() {
                              hostController.text = '10.0.2.2';
                              portController.text = '1883';
                            });
                          },
                        ),
                        ActionChip(
                          label: const Text('Localhost (127.0.0.1)', style: TextStyle(fontSize: 11)),
                          onPressed: () {
                            setDialogState(() {
                              hostController.text = '127.0.0.1';
                              portController.text = '1883';
                            });
                          },
                        ),
                        ActionChip(
                          label: const Text('Réseau Local (192.168.x.x)', style: TextStyle(fontSize: 11)),
                          onPressed: () {
                            setDialogState(() {
                              if (!hostController.text.startsWith('192.168.')) {
                                hostController.text = '192.168.1.';
                              }
                              portController.text = '1883';
                            });
                          },
                        ),
                      ],
                    ),
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
                  label: const Text('Appliquer'),
                  onPressed: () {
                    final newHost = hostController.text.trim();
                    final newPort = int.tryParse(portController.text.trim()) ?? 1883;
                    final newDeviceId = deviceIdController.text.trim();

                    if (newHost.isNotEmpty && newDeviceId.isNotEmpty) {
                      setState(() {
                        _brokerHost = newHost;
                        _brokerPort = newPort;
                        _deviceId = newDeviceId;
                        _targetDeviceId = 'HealthKicks-$newDeviceId';
                      });
                      Navigator.of(ctx).pop();
                      _addLog('CONFIG', 'Nouvelle configuration : $_brokerHost:$_brokerPort (Device: $_deviceId)');
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
    final isReady = _bleStatus == BleConnectionStatus.ready;
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
                onPressed: _startBleScan,
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
                '$_brokerHost:$_brokerPort',
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
