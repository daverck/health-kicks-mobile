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

/// Gestionnaire du cycle de vie de connexion Bluetooth Low Energy vers la chaussure HealthKicks.
class BleConnectionManager {
  final PermissionService _permissionService;

  BluetoothDevice? _connectedDevice;
  BluetoothDevice? get connectedDevice => _connectedDevice;

  BleConnectionStatus _status = BleConnectionStatus.disconnected;
  BleConnectionStatus get status => _status;

  final _statusController = StreamController<BleConnectionStatus>.broadcast();
  Stream<BleConnectionStatus> get statusStream => _statusController.stream;

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _deviceStateSubscription;

  int _negotiatedMtu = 23;
  int get negotiatedMtu => _negotiatedMtu;

  BleConnectionManager({PermissionService? permissionService})
      : _permissionService = permissionService ?? PermissionService();

  void _updateStatus(BleConnectionStatus newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  /// Démarre le scan et se connecte automatiquement au premier périphérique HealthKicks détecté.
  Future<void> startAutoConnect({String? targetDeviceId, Duration timeout = const Duration(seconds: 15)}) async {
    final hasPerms = await _permissionService.requestBlePermissions();
    if (!hasPerms) {
      _updateStatus(BleConnectionStatus.disconnected);
      throw Exception('Permissions Bluetooth ou Localisation refusées.');
    }

    // Vérifier si le Bluetooth est allumé
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      await FlutterBluePlus.turnOn();
    }

    _updateStatus(BleConnectionStatus.scanning);

    await FlutterBluePlus.startScan(
      timeout: timeout,
    );

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
      for (final r in results) {
        final advName = r.advertisementData.advName;
        final platformName = r.device.platformName;
        final name = advName.isNotEmpty ? advName : platformName;

        final hasServiceUuid = r.advertisementData.serviceUuids.any(
          (u) => u.toString().toLowerCase() == BleConstants.footwearServiceUuid.toLowerCase(),
        );

        final matchesTarget = targetDeviceId != null
            ? name.toLowerCase().contains(targetDeviceId.toLowerCase())
            : name.toLowerCase().contains('healthkicks');

        if (hasServiceUuid || matchesTarget) {
          await FlutterBluePlus.stopScan();
          await _scanSubscription?.cancel();
          _scanSubscription = null;
          await connectToDevice(r.device);
          break;
        }
      }
    });
  }

  /// Établit la connexion avec le périphérique et négocie le MTU maximal (>= 247).
  Future<void> connectToDevice(BluetoothDevice device) async {
    _connectedDevice = device;
    _updateStatus(BleConnectionStatus.connecting);

    try {
      await device.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 15),
      );
      _updateStatus(BleConnectionStatus.connected);

      // Négocier le MTU maximal (standard 247 sous Android)
      if (Platform.isAndroid) {
        try {
          _negotiatedMtu = await device.requestMtu(247);
        } catch (_) {
          _negotiatedMtu = 247;
        }
      } else {
        _negotiatedMtu = 247;
      }

      // Écouter l'état de connexion pour gérer la reconnexion automatique
      _deviceStateSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _updateStatus(BleConnectionStatus.disconnected);
        } else if (state == BluetoothConnectionState.connected) {
          _updateStatus(BleConnectionStatus.connected);
        }
      });

      _updateStatus(BleConnectionStatus.ready);
    } catch (e) {
      _updateStatus(BleConnectionStatus.disconnected);
      rethrow;
    }
  }

  /// Déconnecte proprement le périphérique actif.
  Future<void> disconnect() async {
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
    disconnect();
    _statusController.close();
  }
}
