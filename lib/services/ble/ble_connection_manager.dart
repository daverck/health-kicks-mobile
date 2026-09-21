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

/// Bluetooth Low Energy connection lifecycle manager for the HealthKicks footwear device.
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

  /// Starts scanning and automatically connects to the first detected HealthKicks device.
  /// If no device is found after [timeout] (default 3 minutes), scanning stops automatically.
  Future<void> startAutoConnect({
    String? targetDeviceId,
    Duration timeout = BleConstants.defaultScanTimeout,
    BleLogCallback? onLog,
  }) async {
    final log = onLog ?? this.onLog;
    log?.call('Checking permissions...');

    final permsResult = await _permissionService.requestDetailedBlePermissions(
      onLog: (msg) => log?.call(msg),
    );

    if (!permsResult.isGranted) {
      _updateStatus(BleConnectionStatus.disconnected);
      final reason = permsResult.isPermanentlyDenied
          ? 'Bluetooth/Location permissions permanently denied. Please enable them in app settings.'
          : 'Bluetooth or Location permissions not granted (${permsResult.details}).';
      log?.call(reason);
      throw Exception(reason);
    }

    // Cancel any prior scan and timer before restarting
    _scanTimeoutTimer?.cancel();
    _scanTimeoutTimer = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await _scanSubscription?.cancel();
    _scanSubscription = null;

    // Check if Bluetooth is turned on (with timeout to never block)
    try {
      final state = await FlutterBluePlus.adapterState
          .first
          .timeout(const Duration(seconds: 2), onTimeout: () => BluetoothAdapterState.on);
      if (state != BluetoothAdapterState.on) {
        log?.call('Bluetooth inactive, attempting activation...');
        await FlutterBluePlus.turnOn().timeout(const Duration(seconds: 4));
      }
    } catch (e) {
      log?.call('BT adapter warning: $e');
    }

    _updateStatus(BleConnectionStatus.scanning);
    final timeoutLabel = timeout.inMinutes > 0
        ? '${timeout.inMinutes} minute(s)'
        : '${timeout.inSeconds} second(s)';
    log?.call('Starting scan (timeout: $timeoutLabel)...');

    // Scan timeout trigger if no device is found
    _scanTimeoutTimer = Timer(timeout, () async {
      if (_status == BleConnectionStatus.scanning) {
        log?.call('No device detected after $timeoutLabel. Stopping scan.');
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
      log?.call('Error starting scan: $e');
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
          final displayName = name.isNotEmpty ? name : 'Unknown';
          log?.call('Device detected: $displayName ($deviceId)');
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
          log?.call('Target found ($name / $deviceId), attempting connection...');
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

  /// Establishes connection with device and negotiates maximum MTU (>= 247).
  Future<void> connectToDevice(BluetoothDevice device, {BleLogCallback? onLog}) async {
    final log = onLog ?? this.onLog;
    _connectedDevice = device;
    _updateStatus(BleConnectionStatus.connecting);
    log?.call('Connecting to ${device.platformName} (${device.remoteId.str})...');

    try {
      await device.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 15),
      );
      _updateStatus(BleConnectionStatus.connected);
      log?.call('Connected to ${device.remoteId.str}. Negotiating MTU...');

      // Negotiate maximum MTU (standard 247 on Android)
      if (Platform.isAndroid) {
        try {
          _negotiatedMtu = await device.requestMtu(247);
          log?.call('Negotiated MTU: $_negotiatedMtu bytes.');
        } catch (_) {
          _negotiatedMtu = 247;
          log?.call('Default MTU negotiation (247 bytes).');
        }
      } else {
        _negotiatedMtu = 247;
      }

      // Listen to connection state to handle automatic reconnection
      _deviceStateSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          log?.call('Device disconnected.');
          _updateStatus(BleConnectionStatus.disconnected);
        } else if (state == BluetoothConnectionState.connected) {
          if (_status != BleConnectionStatus.ready) {
            log?.call('Device reconnected.');
            _updateStatus(BleConnectionStatus.connected);
          }
        }
      });

      _updateStatus(BleConnectionStatus.ready);
      log?.call('Device ready for services initialization.');
    } catch (e) {
      _updateStatus(BleConnectionStatus.disconnected);
      log?.call('Connection error: $e');
      rethrow;
    }
  }

  /// Cleanly disconnects active device.
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
