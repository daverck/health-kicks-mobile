import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

typedef PermissionLogCallback = void Function(String message);

/// Detailed result of BLE permission verification.
class BlePermissionResult {
  final bool isGranted;
  final bool isPermanentlyDenied;
  final PermissionStatus scanStatus;
  final PermissionStatus connectStatus;
  final PermissionStatus? locationStatus;
  final String details;

  const BlePermissionResult({
    required this.isGranted,
    required this.isPermanentlyDenied,
    required this.scanStatus,
    required this.connectStatus,
    this.locationStatus,
    required this.details,
  });
}

/// Service managing the verification and proactive acquisition of permissions
/// required for Bluetooth Low Energy operation (Android 12+ and iOS).
class PermissionService {
  /// Checks and requests Bluetooth and Location permissions
  /// required for GATT scanning and connection.
  Future<bool> requestBlePermissions({PermissionLogCallback? onLog}) async {
    final result = await requestDetailedBlePermissions(onLog: onLog);
    return result.isGranted;
  }

  /// Executes a verbose check with complete diagnostics.
  Future<BlePermissionResult> requestDetailedBlePermissions({PermissionLogCallback? onLog}) async {
    if (Platform.isAndroid) {
      // Android 12+ (SDK 31+) explicitly requires bluetoothScan and bluetoothConnect
      final scanStatus = await Permission.bluetoothScan.request();
      final connectStatus = await Permission.bluetoothConnect.request();

      onLog?.call('Scan: ${scanStatus.name}, Connect: ${connectStatus.name}');

      if (scanStatus.isGranted && connectStatus.isGranted) {
        return BlePermissionResult(
          isGranted: true,
          isPermanentlyDenied: false,
          scanStatus: scanStatus,
          connectStatus: connectStatus,
          details: 'Scan: ${scanStatus.name}, Connect: ${connectStatus.name}',
        );
      }

      // For devices requiring location (Android < 12 or vendor-specific ROMs)
      final locationStatus = await Permission.locationWhenInUse.request();
      onLog?.call('Fallback Location: ${locationStatus.name}');

      final isGranted = (scanStatus.isGranted && connectStatus.isGranted) || locationStatus.isGranted;
      final isPermanent = scanStatus.isPermanentlyDenied ||
          connectStatus.isPermanentlyDenied ||
          locationStatus.isPermanentlyDenied;

      final details = 'Scan: ${scanStatus.name}, Connect: ${connectStatus.name}, Location: ${locationStatus.name}';

      return BlePermissionResult(
        isGranted: isGranted,
        isPermanentlyDenied: isPermanent,
        scanStatus: scanStatus,
        connectStatus: connectStatus,
        locationStatus: locationStatus,
        details: details,
      );
    } else if (Platform.isIOS) {
      final bluetoothStatus = await Permission.bluetooth.request();
      onLog?.call('iOS Bluetooth: ${bluetoothStatus.name}');
      return BlePermissionResult(
        isGranted: bluetoothStatus.isGranted,
        isPermanentlyDenied: bluetoothStatus.isPermanentlyDenied,
        scanStatus: bluetoothStatus,
        connectStatus: bluetoothStatus,
        details: 'iOS Bluetooth: ${bluetoothStatus.name}',
      );
    }

    return const BlePermissionResult(
      isGranted: true,
      isPermanentlyDenied: false,
      scanStatus: PermissionStatus.granted,
      connectStatus: PermissionStatus.granted,
      details: 'Non-mobile platform',
    );
  }

  /// Opens the application system settings if permissions are permanently denied.
  Future<bool> openSettings() async {
    return await openAppSettings();
  }

  /// Indicates whether current BLE permissions are sufficient.
  Future<bool> hasBlePermissions() async {
    if (Platform.isAndroid) {
      final hasScan = await Permission.bluetoothScan.isGranted;
      final hasConnect = await Permission.bluetoothConnect.isGranted;
      if (hasScan && hasConnect) return true;
      return await Permission.locationWhenInUse.isGranted;
    } else if (Platform.isIOS) {
      return await Permission.bluetooth.isGranted;
    }
    return true;
  }
}
