import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

typedef PermissionLogCallback = void Function(String message);

/// Résultat détaillé de la vérification des permissions BLE.
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

/// Service gérant la vérification et l'obtention proactive des permissions
/// nécessaires au fonctionnement du Bluetooth Low Energy (Android 12+ et iOS).
class PermissionService {
  /// Vérifie et sollicite les autorisations Bluetooth et de localisation
  /// nécessaires pour le scan et la connexion GATT.
  Future<bool> requestBlePermissions({PermissionLogCallback? onLog}) async {
    final result = await requestDetailedBlePermissions(onLog: onLog);
    return result.isGranted;
  }

  /// Exécute une vérification verbeuse avec diagnostic complet.
  Future<BlePermissionResult> requestDetailedBlePermissions({PermissionLogCallback? onLog}) async {
    if (Platform.isAndroid) {
      // Android 12+ (SDK 31+) requiert explicitement bluetoothScan et bluetoothConnect
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

      // Pour les appareils nécessitant la localisation (Android < 12 ou ROM constructeur spécifique)
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

  /// Ouvre les paramètres système de l'application si les permissions sont définitivement refusées.
  Future<bool> openSettings() async {
    return await openAppSettings();
  }

  /// Indique si les autorisations BLE actuelles sont suffisantes.
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
