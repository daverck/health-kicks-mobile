import 'dart:async';
import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../core/constants/ble_constants.dart';
import '../../core/permissions/permission_service.dart';

enum BleConnectionStatus {
  disconnected,
  scanning,
  connecting,
  connected,
  ready,
}

typedef BleLogCallback = void Function(String message);

/// Gestionnaire du cycle de vie de connexion Bluetooth Low Energy vers la chaussure HealthKicks.
class BleConnectionManager {
  final PermissionService _permissionService;
  final BleLogCallback? onLog;

  BluetoothDevice? _connectedDevice;
  BluetoothDevice? get connectedDevice => _connectedDevice;

  BleConnectionStatus _status = BleConnectionStatus.disconnected;
  BleConnectionStatus get status => _status;

  final _statusController = StreamController<BleConnectionStatus>.broadcast();
  Stream<BleConnectionStatus> get statusStream => _statusController.stream;

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _deviceStateSubscription;
  Timer? _scanTimeoutTimer;

  int _negotiatedMtu = 23;
  int get negotiatedMtu => _negotiatedMtu;

  BleConnectionManager({
    PermissionService? permissionService,
    this.onLog,
  }) : _permissionService = permissionService ?? PermissionService();

  void _updateStatus(BleConnectionStatus newStatus) {
    _status = newStatus;
    if (!_statusController.isClosed) {
      _statusController.add(newStatus);
    }
  }

  /// Démarre le scan et se connecte automatiquement au premier périphérique HealthKicks détecté.
  /// Si aucun équipement n'est trouvé après [timeout] (par défaut 4 minutes), le scan s'arrête automatiquement.
  Future<void> startAutoConnect({
    String? targetDeviceId,
    Duration timeout = BleConstants.defaultScanTimeout,
    BleLogCallback? onLog,
  }) async {
    final log = onLog ?? this.onLog;
    log?.call('[BLE] Vérification des permissions...');

    final permsResult = await _permissionService.requestDetailedBlePermissions(
      onLog: (msg) => log?.call('[PERM] $msg'),
    );

    if (!permsResult.isGranted) {
      _updateStatus(BleConnectionStatus.disconnected);
      final reason = permsResult.isPermanentlyDenied
          ? 'Permissions Bluetooth/Localisation définitivement refusées. Activez-les dans les Paramètres de l\'application.'
          : 'Permissions Bluetooth ou Localisation non accordées (${permsResult.details}).';
      log?.call('[BLE] $reason');
      throw Exception(reason);
    }

    // Arrêter tout scan et timer antérieurs avant de relancer
    _scanTimeoutTimer?.cancel();
    _scanTimeoutTimer = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await _scanSubscription?.cancel();
    _scanSubscription = null;

    // Vérifier si le Bluetooth est allumé (avec timeout pour ne jamais bloquer)
    try {
      final state = await FlutterBluePlus.adapterState
          .first
          .timeout(const Duration(seconds: 2), onTimeout: () => BluetoothAdapterState.on);
      if (state != BluetoothAdapterState.on) {
        log?.call('[BLE] Bluetooth inactif, tentative d\'activation...');
        await FlutterBluePlus.turnOn().timeout(const Duration(seconds: 4));
      }
    } catch (e) {
      log?.call('[BLE] Avertissement adaptateur BT : $e');
    }

    _updateStatus(BleConnectionStatus.scanning);
    final timeoutLabel = timeout.inMinutes > 0
        ? '${timeout.inMinutes} minute(s)'
        : '${timeout.inSeconds} seconde(s)';
    log?.call('[BLE] Démarrage du scan (timeout: $timeoutLabel)...');

    // Déclencheur d'expiration du scan si aucun équipement n'est détecté
    _scanTimeoutTimer = Timer(timeout, () async {
      if (_status == BleConnectionStatus.scanning) {
        log?.call('[BLE] Aucun équipement détecté après $timeoutLabel. Arrêt du scan.');
        try {
          await FlutterBluePlus.stopScan();
        } catch (_) {}
        await _scanSubscription?.cancel();
        _scanSubscription = null;
        _updateStatus(BleConnectionStatus.disconnected);
      }
    });

    final seenDevices = <String>{};

    try {
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: false,
      );
    } catch (e) {
      _scanTimeoutTimer?.cancel();
      _scanTimeoutTimer = null;
      _updateStatus(BleConnectionStatus.disconnected);
      log?.call('[BLE] Erreur démarrage scan : $e');
      rethrow;
    }

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
      for (final r in results) {
        final deviceId = r.device.remoteId.str;
        final advName = r.advertisementData.advName;
        final platformName = r.device.platformName;
        final name = advName.isNotEmpty ? advName : platformName;

        if (!seenDevices.contains(deviceId)) {
          seenDevices.add(deviceId);
          final displayName = name.isNotEmpty ? name : 'Inconnu';
          log?.call('[BLE] Périphérique détecté : $displayName ($deviceId)');
        }

        final hasServiceUuid = r.advertisementData.serviceUuids.any(
          (u) => u.toString().toLowerCase() == BleConstants.footwearServiceUuid.toLowerCase(),
        );

        final matchesTargetName = targetDeviceId != null
            ? name.toLowerCase().contains(targetDeviceId.toLowerCase())
            : name.toLowerCase().contains('healthkicks');

        final matchesTargetMac = targetDeviceId != null &&
            deviceId.toLowerCase() == targetDeviceId.toLowerCase();

        if (hasServiceUuid || matchesTargetName || matchesTargetMac) {
          log?.call('[BLE] Cible trouvée ($name / $deviceId), tentative de connexion...');
          _scanTimeoutTimer?.cancel();
          _scanTimeoutTimer = null;
          try {
            await FlutterBluePlus.stopScan();
          } catch (_) {}
          await _scanSubscription?.cancel();
          _scanSubscription = null;

          await connectToDevice(r.device, onLog: log);
          break;
        }
      }
    });
  }

  /// Établit la connexion avec le périphérique et négocie le MTU maximal (>= 247).
  Future<void> connectToDevice(BluetoothDevice device, {BleLogCallback? onLog}) async {
    final log = onLog ?? this.onLog;
    _connectedDevice = device;
    _updateStatus(BleConnectionStatus.connecting);
    log?.call('[BLE] Connexion en cours vers ${device.platformName} (${device.remoteId.str})...');

    try {
      await device.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 15),
      );
      _updateStatus(BleConnectionStatus.connected);
      log?.call('[BLE] Connecté à ${device.remoteId.str}. Négociation MTU...');

      // Négocier le MTU maximal (standard 247 sous Android)
      if (Platform.isAndroid) {
        try {
          _negotiatedMtu = await device.requestMtu(247);
          log?.call('[BLE] MTU négocié : $_negotiatedMtu octets.');
        } catch (_) {
          _negotiatedMtu = 247;
          log?.call('[BLE] Négociation MTU par défaut (247 octets).');
        }
      } else {
        _negotiatedMtu = 247;
      }

      // Écouter l'état de connexion pour gérer la reconnexion automatique
      _deviceStateSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          log?.call('[BLE] Périphérique déconnecté.');
          _updateStatus(BleConnectionStatus.disconnected);
        } else if (state == BluetoothConnectionState.connected) {
          if (_status != BleConnectionStatus.ready) {
            log?.call('[BLE] Périphérique reconnecté.');
            _updateStatus(BleConnectionStatus.connected);
          }
        }
      });

      _updateStatus(BleConnectionStatus.ready);
      log?.call('[BLE] Périphérique prêt pour l\'initialisation des services.');
    } catch (e) {
      _updateStatus(BleConnectionStatus.disconnected);
      log?.call('[BLE] Erreur connexion : $e');
      rethrow;
    }
  }

  /// Déconnecte proprement le périphérique actif.
  Future<void> disconnect() async {
    _scanTimeoutTimer?.cancel();
    _scanTimeoutTimer = null;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await _deviceStateSubscription?.cancel();
    _deviceStateSubscription = null;

    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      _connectedDevice = null;
    }
    _updateStatus(BleConnectionStatus.disconnected);
  }

  void dispose() {
    _scanTimeoutTimer?.cancel();
    _scanTimeoutTimer = null;
    disconnect();
    _statusController.close();
  }
}
