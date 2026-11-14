import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/firmware_release_model.dart';
import '../services/auth/auth_service.dart';
import '../services/ble/ble_footwear_client.dart';
import '../services/firmware/firmware_service.dart';

/// Coordinator encapsulating firmware version queries, OTA update detection,
/// release comparison, and update notification dispatching for the Gateway Dashboard.
class DashboardFirmwareCoordinator {
  final FirmwareService firmwareService;
  final AuthService? authService;

  FirmwareReleaseModel? _latestFirmwareRelease;
  String? _installedFirmwareVersion;
  DateTime? _installedFirmwareDate;
  String? _announcedFirmwareReleaseVersion;
  bool _isDisposed = false;

  FirmwareReleaseModel? get latestFirmwareRelease => _latestFirmwareRelease;
  String? get installedFirmwareVersion => _installedFirmwareVersion;
  DateTime? get installedFirmwareDate => _installedFirmwareDate;
  String? get announcedFirmwareReleaseVersion => _announcedFirmwareReleaseVersion;

  DashboardFirmwareCoordinator({
    FirmwareService? firmwareService,
    this.authService,
  }) : firmwareService = firmwareService ?? FirmwareService();

  Future<void> checkForFirmwareUpdate({
    required void Function(String tag, String message, {Color? color}) addLog,
    required void Function(String message, {Color? backgroundColor})? onShowSnackBar,
  }) async {
    if (_isDisposed) return;
    String? installedVersion;
    DateTime? installedDate;
    try {
      installedVersion = await firmwareService.getLocalInstalledVersion();
      installedDate = await firmwareService.getLocalInstalledDate();
      _installedFirmwareVersion = installedVersion;
      _installedFirmwareDate = installedDate;
    } catch (e) {
      addLog('FIRMWARE', 'Version locale non disponible : $e', color: Colors.orange);
    }
    if (_isDisposed) return;

    try {
      String? token;
      try {
        token = await authService?.getValidAccessToken();
      } catch (e) {
        addLog('FIRMWARE', 'Jeton API indisponible, tentative de vérification publique : $e', color: Colors.orange);
      }
      if (_isDisposed) return;

      final release = await firmwareService.fetchLatestRelease(
        backendUrl: authService?.backendBaseUrl,
        token: token,
      );
      if (_isDisposed) return;

      _latestFirmwareRelease = release;
      addLog('FIRMWARE', 'Vérification automatique terminée : ${release.version}.');
      notifyIfFirmwareUpdateAvailable(
        installedVersion: _installedFirmwareVersion ?? installedVersion,
        installedDate: _installedFirmwareDate ?? installedDate,
        addLog: addLog,
        onShowSnackBar: onShowSnackBar,
      );
    } catch (e) {
      if (!_isDisposed) {
        addLog('FIRMWARE', 'Échec de la vérification automatique du firmware : $e', color: Colors.red);
      }
    }
  }

  void notifyIfFirmwareUpdateAvailable({
    required String? installedVersion,
    required DateTime? installedDate,
    required void Function(String tag, String message, {Color? color}) addLog,
    required void Function(String message, {Color? backgroundColor})? onShowSnackBar,
  }) {
    if (_isDisposed) return;
    final release = _latestFirmwareRelease;
    if (release == null) return;

    if (installedVersion == null && installedDate == null) {
      addLog('FIRMWARE', 'Version installée inconnue ; comparaison reportée à la connexion BLE.');
      return;
    }

    final isNewer = firmwareService.isCloudReleaseNewer(
      cloudReleaseDate: release.releaseDate,
      installedDate: installedDate,
      cloudVersion: release.version,
      installedVersion: installedVersion,
    );
    if (!isNewer || _announcedFirmwareReleaseVersion == release.version) return;

    _announcedFirmwareReleaseVersion = release.version;
    addLog('FIRMWARE', 'Nouveau firmware disponible : ${release.version}.', color: Colors.orange);
    onShowSnackBar?.call(
      'Nouveau firmware disponible (${release.version}). Consultez Paramètres > Mise à jour du firmware.',
      backgroundColor: Colors.orange.shade800,
    );
  }

  void syncConnectedDeviceFirmware({
    required BluetoothDevice device,
    required BleFootwearClient client,
    required void Function(String tag, String message, {Color? color}) addLog,
    required void Function(String message, {Color? backgroundColor})? onShowSnackBar,
  }) {
    if (client.firmwareVersion != null && client.firmwareVersion!.isNotEmpty) {
      addLog('BLE', 'Firmware détecté : ${client.firmwareVersion} (${client.rawBuildString ?? ""})');
      _installedFirmwareVersion = client.firmwareVersion;
      _installedFirmwareDate = client.firmwareBuildDate ?? _installedFirmwareDate;
      notifyIfFirmwareUpdateAvailable(
        installedVersion: _installedFirmwareVersion,
        installedDate: _installedFirmwareDate,
        addLog: addLog,
        onShowSnackBar: onShowSnackBar,
      );
      firmwareService.saveLocalInstalledFirmware(
        installedDate: client.firmwareBuildDate ?? DateTime.now().toUtc(),
        version: client.firmwareVersion!,
      );
    } else {
      unawaited(firmwareService.readDeviceFirmwareInfo(device).then((info) {
        if (info.version != null && info.version!.isNotEmpty) {
          addLog('BLE', 'Firmware détecté : ${info.version} (${info.rawBuildString ?? ""})');
          _installedFirmwareVersion = info.version;
          _installedFirmwareDate = info.buildDate ?? _installedFirmwareDate;
          notifyIfFirmwareUpdateAvailable(
            installedVersion: _installedFirmwareVersion,
            installedDate: _installedFirmwareDate,
            addLog: addLog,
            onShowSnackBar: onShowSnackBar,
          );
          firmwareService.saveLocalInstalledFirmware(
            installedDate: info.buildDate ?? DateTime.now().toUtc(),
            version: info.version!,
          );
        }
      }));
    }
  }

  void dispose() {
    _isDisposed = true;
  }
}
