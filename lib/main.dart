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
  static const String _deviceId = 'HK-2';
  static const String _targetDeviceId = 'HealthKicks-HK-2';
  static const String _brokerHost = '10.0.2.2'; // Gateway broker default (local/emulator)
  static const int _brokerPort = 1883;

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
      case 'BLE':
        return Colors.blue;
      case 'MQTT':
        return Colors.teal;
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

  Future<void> _initGateway() async {
    _addLog('INIT', 'Démarrage de la passerelle HealthKicks...');

    // 1. Solliciter les permissions requises
    try {
      final hasPerms = await _permissionService.requestBlePermissions();
      _addLog('PERM', hasPerms ? 'Permissions BLE & Localisation accordées.' : 'Permissions BLE refusées.');
    } catch (e) {
      _addLog('PERM', 'Vérification des permissions ignorée ($e)');
    }

    // 2. Initialiser le service MQTT
    try {
      _mqttService = MqttGatewayService(
        brokerHost: _brokerHost,
        brokerPort: _brokerPort,
        deviceId: _deviceId,
      );
      final connected = await _mqttService!.connect();
      if (mounted) {
        setState(() => _mqttConnected = connected);
      }
      _addLog('MQTT', connected ? 'Connecté au broker $_brokerHost:$_brokerPort' : 'Broker MQTT non joignable ($_brokerHost:$_brokerPort)');
    } catch (e) {
      _addLog('MQTT', 'Erreur MQTT : $e', color: Colors.red);
    }

    // 3. Initialiser le gestionnaire BLE
    try {
      _bleManager = BleConnectionManager(permissionService: _permissionService);
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
      _addLog('BLE', 'Initialisation BLE : $e');
    }
  }

  Future<void> _startBleScan() async {
    if (_bleManager == null) return;
    _addLog('BLE', 'Scan en cours pour "$_targetDeviceId" ou Service GATT...');
    try {
      await _bleManager!.startAutoConnect(targetDeviceId: _targetDeviceId);
    } catch (e) {
      _addLog('BLE', 'Erreur de scan : $e', color: Colors.red);
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
              children: [
                Icon(Icons.cloud, color: statusColor, size: 20),
                const SizedBox(width: 4),
                const Text('AWS / MQTT', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const Text(
              '$_brokerHost:$_brokerPort',
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
              width: double.infinity,
              height: 28,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () async {
                  _addLog('MQTT', 'Reconnexion au broker...');
                  final ok = await _mqttService?.connect() ?? false;
                  if (mounted) {
                    setState(() => _mqttConnected = ok);
                  }
                },
                child: const Text('Re-connecter', style: TextStyle(fontSize: 11)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
