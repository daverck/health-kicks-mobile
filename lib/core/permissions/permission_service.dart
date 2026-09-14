import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

/// Service gérant la vérification et l'obtention proactive des permissions
/// nécessaires au fonctionnement du Bluetooth Low Energy (Android 12+ et iOS).
class PermissionService {
  /// Vérifie et sollicite les autorisations Bluetooth et de localisation
  /// nécessaires pour le scan et la connexion GATT.
  Future<bool> requestBlePermissions() async {
    if (Platform.isAndroid) {
      // Android 12+ (SDK 31+) requiert explicitement bluetoothScan et bluetoothConnect
      final scanStatus = await Permission.bluetoothScan.request();
      final connectStatus = await Permission.bluetoothConnect.request();

      if (scanStatus.isGranted && connectStatus.isGranted) {
        return true;
      }

      // Pour les appareils plus anciens (Android 11 et inférieur), la localisation est obligatoire pour le scan BLE
      final locationStatus = await Permission.locationWhenInUse.request();
      return locationStatus.isGranted;
    } else if (Platform.isIOS) {
      final bluetoothStatus = await Permission.bluetooth.request();
      return bluetoothStatus.isGranted;
    }

    return true;
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
