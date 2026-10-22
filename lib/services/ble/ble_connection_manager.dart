import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
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
///
/// ### Connection State Machine
/// ```text
///  [ disconnected ]
///         │  startAutoConnect()
///         ▼
///    [ scanning ] ──(timeout / not found)──► [ disconnected ]
///         │  (matched HealthKicks advert)
///         ▼
///   [ connecting ] ──(GATT failure / timeout)──► [ disconnected ]
///         │  (device.connect() OK)
///         ▼
///   [ connected ] ──(discover services & negotiate MTU)
///         │
///         ▼
///     [ ready ] ──(unexpected disconnect / link drop)──► [ disconnected ]
/// ```
///
/// Responsibilities:
/// - Verifies runtime BLE and location permissions before scanning.
/// - Scans advertising packets for devices matching `HealthKicks-` or target device ID.
/// - Connects to the peripheral and requests MTU expansion (up to 512 bytes).
/// - Monitors peripheral connection states to emit status notifications across the app.
class BleConnectionManager extends ChangeNotifier {
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
  Timer? _reconnectTimer;
  Timer? _autoReconnectWindowTimer;
  Stopwatch? _autoReconnectWindow;
  bool _autoReconnectEnabled = false;
  String? _autoReconnectTargetDeviceId;
  Duration _autoReconnectScanTimeout = BleConstants.defaultScanTimeout;
  BleLogCallback? _autoReconnectLog;
  int _connectionAttemptId = 0;

  static const Duration _autoReconnectDelay = Duration(seconds: 2);
  static const Duration _autoReconnectErrorDelay = Duration(seconds: 30);
  static const Duration _autoReconnectMaxDuration = Duration(minutes: 2);

  int _negotiatedMtu = 23;
  int get negotiatedMtu => _negotiatedMtu;

  BleConnectionManager({
    PermissionService? permissionService,
    this.onLog,
  }) : _permissionService = permissionService ?? PermissionService();

  bool _isDisposed = false;

  void _updateStatus(BleConnectionStatus newStatus) {
    if (_isDisposed) return;
    _status = newStatus;
    notifyListeners();
    if (!_statusController.isClosed) {
      _statusController.add(newStatus);
    }
  }

  @visibleForTesting
  void updateStatusForTesting(BleConnectionStatus newStatus) =>
      _updateStatus(newStatus);

  /// Starts scanning and automatically connects to the first detected HealthKicks device.
  /// If no device is found after [timeout] (default 3 minutes), scanning stops automatically.
  Future<void> startAutoConnect({
    String? targetDeviceId,
    Duration timeout = BleConstants.defaultScanTimeout,
    BleLogCallback? onLog,
  }) async {
    final log = onLog ?? this.onLog;
    final attemptId = ++_connectionAttemptId;
    _autoReconnectEnabled = true;
    _autoReconnectTargetDeviceId = targetDeviceId;
    _autoReconnectScanTimeout = timeout;
    _autoReconnectLog = log;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    log?.call('Checking permissions...');

    final permsResult = await _permissionService.requestDetailedBlePermissions(
      onLog: (msg) => log?.call(msg),
    );

    if (!_isCurrentConnectionAttempt(attemptId)) return;
    if (!permsResult.isGranted) {
      if (permsResult.isPermanentlyDenied) {
        _autoReconnectEnabled = false;
        _clearAutoReconnectWindow();
      }
      _updateStatus(BleConnectionStatus.disconnected);
      final reason = permsResult.isPermanentlyDenied
          ? 'Bluetooth/Location permissions permanently denied. Please enable them in app settings.'
          : 'Bluetooth or Location permissions not granted (${permsResult.details}).';
      log?.call(reason);
      throw Exception(reason);
    }

    // Cancel any prior scan, timer and reset connected device before restarting
    _connectedDevice = null;
    _negotiatedMtu = 23;
    _scanTimeoutTimer?.cancel();
    _scanTimeoutTimer = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    await _scanSubscription?.cancel();
    _scanSubscription = null;

    // Check if Bluetooth is turned on (with timeout to never block)
    try {
      final state = await FlutterBluePlus.adapterState.first.timeout(
          const Duration(seconds: 2),
          onTimeout: () => BluetoothAdapterState.on);
      if (!_isCurrentConnectionAttempt(attemptId)) return;
      if (state != BluetoothAdapterState.on) {
        log?.call('Bluetooth inactive, attempting activation...');
        await FlutterBluePlus.turnOn().timeout(const Duration(seconds: 4));
      }
      if (!_isCurrentConnectionAttempt(attemptId)) return;
    } catch (e) {
      if (!_isCurrentConnectionAttempt(attemptId)) return;
      log?.call('BT adapter warning: $e');
    }

    final remainingReconnectTime = _remainingAutoReconnectTime;
    if (remainingReconnectTime != null &&
        remainingReconnectTime <= Duration.zero) {
      await _expireAutoReconnectWindow();
      return;
    }
    final scanTimeout =
        remainingReconnectTime == null || timeout <= remainingReconnectTime
            ? timeout
            : remainingReconnectTime;

    _updateStatus(BleConnectionStatus.scanning);
    final timeoutLabel = scanTimeout.inMinutes > 0
        ? '${scanTimeout.inMinutes} minute(s)'
        : '${scanTimeout.inSeconds} second(s)';
    log?.call('Starting scan (timeout: $timeoutLabel)...');

    // Scan timeout trigger if no device is found
    _scanTimeoutTimer = Timer(scanTimeout, () async {
      if (_isCurrentConnectionAttempt(attemptId) &&
          _status == BleConnectionStatus.scanning) {
        log?.call('No device detected after $timeoutLabel. Stopping scan.');
        try {
          await FlutterBluePlus.stopScan();
        } catch (_) {}
        await _scanSubscription?.cancel();
        _scanSubscription = null;
        _updateStatus(BleConnectionStatus.disconnected);
        _scheduleAutoReconnect();
      }
    });

    final seenDevices = <String>{};

    try {
      await FlutterBluePlus.startScan(
        timeout: scanTimeout,
        androidUsesFineLocation: false,
      );
    } catch (e) {
      if (!_isCurrentConnectionAttempt(attemptId)) return;
      _scanTimeoutTimer?.cancel();
      _scanTimeoutTimer = null;
      _updateStatus(BleConnectionStatus.disconnected);
      log?.call('Error starting scan: $e');
      rethrow;
    }

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) async {
      if (!_isCurrentConnectionAttempt(attemptId)) return;
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
          (u) =>
              u.toString().toLowerCase() ==
              BleConstants.footwearServiceUuid.toLowerCase(),
        );

        final matchesTargetName = targetDeviceId != null
            ? name.toLowerCase().contains(targetDeviceId.toLowerCase())
            : name.toLowerCase().contains('healthkicks');

        final matchesTargetMac = targetDeviceId != null &&
            deviceId.toLowerCase() == targetDeviceId.toLowerCase();

        if (hasServiceUuid || matchesTargetName || matchesTargetMac) {
          log?.call(
              'Target found ($name / $deviceId), attempting connection...');
          _scanTimeoutTimer?.cancel();
          _scanTimeoutTimer = null;
          try {
            await FlutterBluePlus.stopScan();
          } catch (_) {}
          await _scanSubscription?.cancel();
          _scanSubscription = null;

          bool connected = false;
          try {
            await connectToDevice(
              r.device,
              onLog: log,
              connectionAttemptId: attemptId,
            );
            connected = true;
          } catch (e) {
            log?.call('Auto-connect attempt failed: $e');
          }

          if (!connected &&
              _status != BleConnectionStatus.ready &&
              _status != BleConnectionStatus.connected) {
            log?.call(
                'Auto-connect attempt failed. Re-initiating scan in 2s...');
            _scheduleAutoReconnect();
          }
          break;
        }
      }
    });
  }

  bool _isCurrentConnectionAttempt(int attemptId) =>
      !_isDisposed &&
      _autoReconnectEnabled &&
      attemptId == _connectionAttemptId;

  Duration? get _remainingAutoReconnectTime {
    final window = _autoReconnectWindow;
    if (window == null) return null;
    return _autoReconnectMaxDuration - window.elapsed;
  }

  void _startAutoReconnectWindow() {
    if (_autoReconnectWindow != null || !_autoReconnectEnabled || _isDisposed) {
      return;
    }

    _autoReconnectWindow = Stopwatch()..start();
    _autoReconnectWindowTimer = Timer(
      _autoReconnectMaxDuration,
      _expireAutoReconnectWindow,
    );
  }

  void _clearAutoReconnectWindow() {
    _autoReconnectWindowTimer?.cancel();
    _autoReconnectWindowTimer = null;
    _autoReconnectWindow?.stop();
    _autoReconnectWindow = null;
  }

  Future<void> _expireAutoReconnectWindow() async {
    if (!_autoReconnectEnabled || _isDisposed) return;

    _autoReconnectEnabled = false;
    final expiredAttemptId = ++_connectionAttemptId;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _scanTimeoutTimer?.cancel();
    _scanTimeoutTimer = null;
    _autoReconnectLog?.call(
      'Automatic BLE reconnection stopped after 2 minutes.',
    );

    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    if (_isDisposed || expiredAttemptId != _connectionAttemptId) return;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await _deviceStateSubscription?.cancel();
    _deviceStateSubscription = null;

    final device = _connectedDevice;
    _connectedDevice = null;
    _negotiatedMtu = 23;
    if (device != null) {
      try {
        await device.disconnect();
      } catch (_) {}
    }
    _clearAutoReconnectWindow();
    _updateStatus(BleConnectionStatus.disconnected);
  }

  void _scheduleAutoReconnect({Duration delay = _autoReconnectDelay}) {
    if (!_autoReconnectEnabled ||
        _isDisposed ||
        _reconnectTimer?.isActive == true ||
        _status == BleConnectionStatus.ready ||
        _status == BleConnectionStatus.connected ||
        _status == BleConnectionStatus.scanning ||
        _status == BleConnectionStatus.connecting) {
      return;
    }

    _startAutoReconnectWindow();
    final remainingTime = _remainingAutoReconnectTime;
    if (remainingTime == null || remainingTime <= Duration.zero) {
      unawaited(_expireAutoReconnectWindow());
      return;
    }

    final retryDelay = delay <= remainingTime ? delay : remainingTime;
    _autoReconnectLog?.call(
      'Unexpected disconnect. Retrying BLE connection in ${retryDelay.inSeconds}s...',
    );
    _reconnectTimer = Timer(
      retryDelay,
      () async {
        _reconnectTimer = null;
        if (!_autoReconnectEnabled || _isDisposed) return;

        try {
          await startAutoConnect(
            targetDeviceId: _autoReconnectTargetDeviceId,
            timeout: _autoReconnectScanTimeout,
            onLog: _autoReconnectLog,
          );
        } catch (error) {
          _autoReconnectLog?.call('Automatic BLE reconnection failed: $error');
          _scheduleAutoReconnect(delay: _autoReconnectErrorDelay);
        }
      },
    );
  }

  /// Establishes connection with device and negotiates maximum MTU (>= 247).
  Future<void> connectToDevice(BluetoothDevice device,
      {BleLogCallback? onLog, int? connectionAttemptId}) async {
    final log = onLog ?? this.onLog;
    _connectedDevice = device;
    _updateStatus(BleConnectionStatus.connecting);
    log?.call(
        'Connecting to ${device.platformName} (${device.remoteId.str})...');

    try {
      await device.connect(
        license: License.nonprofit,
        autoConnect: false,
        timeout: const Duration(seconds: 15),
      );
      if (connectionAttemptId != null &&
          !_isCurrentConnectionAttempt(connectionAttemptId)) {
        await device.disconnect();
        return;
      }
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
      if (connectionAttemptId != null &&
          !_isCurrentConnectionAttempt(connectionAttemptId)) {
        await device.disconnect();
        return;
      }
      notifyListeners();

      // Listen to connection state to handle automatic reconnection & unexpected drops
      await _deviceStateSubscription?.cancel();
      _deviceStateSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          log?.call('Device disconnected.');
          _connectedDevice = null;
          _negotiatedMtu = 23;
          _deviceStateSubscription?.cancel();
          _deviceStateSubscription = null;
          _updateStatus(BleConnectionStatus.disconnected);
          _startAutoReconnectWindow();
          _scheduleAutoReconnect();
        } else if (state == BluetoothConnectionState.connected) {
          _reconnectTimer?.cancel();
          _reconnectTimer = null;
          if (_status != BleConnectionStatus.ready) {
            log?.call('Device reconnected.');
            _connectedDevice = device;
            _updateStatus(BleConnectionStatus.connected);
            _updateStatus(BleConnectionStatus.ready);
          }
        }
      });

      _updateStatus(BleConnectionStatus.ready);
      _clearAutoReconnectWindow();
      log?.call('Device ready for services initialization.');
    } catch (e) {
      _connectedDevice = null;
      _negotiatedMtu = 23;
      await _deviceStateSubscription?.cancel();
      _deviceStateSubscription = null;
      _updateStatus(BleConnectionStatus.disconnected);
      log?.call('Connection error: $e');
      rethrow;
    }
  }

  /// Cleanly disconnects active device.
  Future<void> disconnect() async {
    _autoReconnectEnabled = false;
    _connectionAttemptId++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _clearAutoReconnectWindow();
    _scanTimeoutTimer?.cancel();
    _scanTimeoutTimer = null;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await _deviceStateSubscription?.cancel();
    _deviceStateSubscription = null;

    if (_connectedDevice != null) {
      try {
        await _connectedDevice!.disconnect();
      } catch (_) {}
      _connectedDevice = null;
    }
    _negotiatedMtu = 23;
    _updateStatus(BleConnectionStatus.disconnected);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _autoReconnectEnabled = false;
    _connectionAttemptId++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _clearAutoReconnectWindow();
    _scanTimeoutTimer?.cancel();
    _scanTimeoutTimer = null;
    _scanSubscription?.cancel();
    _deviceStateSubscription?.cancel();
    if (_connectedDevice != null) {
      try {
        _connectedDevice!.disconnect();
      } catch (_) {}
      _connectedDevice = null;
    }
    _statusController.close();
    super.dispose();
  }
}
