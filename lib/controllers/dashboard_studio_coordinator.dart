import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/config/app_config.dart';
import '../services/auth/auth_service.dart';
import '../services/auth/token_storage_service.dart';
import '../services/ble/ble_connection_manager.dart';
import '../services/ble/ble_footwear_client.dart';
import '../services/gateway_coordinator.dart';
import '../services/studio/studio_api_service.dart';
import '../ui/widgets/studio_session_dialog.dart';

/// Delegate coordinator handling Studio session triggers, activity preference caching,
/// and interaction with StudioApiService and GatewayCoordinator.
class DashboardStudioCoordinator {
  final String deviceId;
  final AuthService? authService;
  final void Function(String tag, String message, {Color? color}) onLog;
  final VoidCallback onStateUpdated;
  final Future<void> Function() onEnsureMqttConnected;
  final GatewayCoordinator? Function() getCoordinator;
  final void Function() onSetupCoordinator;
  final BleFootwearClient? Function() getBleClient;
  final BleConnectionStatus Function() getBleStatus;
  final bool Function() getIsSensorCalibrated;

  StudioApiService? _studioApiService;
  String _lastStudioActivityKey = 'walk';
  String _lastStudioCustomLabel = '';

  DashboardStudioCoordinator({
    required this.deviceId,
    this.authService,
    required this.onLog,
    required this.onStateUpdated,
    required this.onEnsureMqttConnected,
    required this.getCoordinator,
    required this.onSetupCoordinator,
    required this.getBleClient,
    required this.getBleStatus,
    required this.getIsSensorCalibrated,
    StudioApiService? studioApiService,
  }) : _studioApiService = studioApiService;

  String get lastStudioActivityKey => _lastStudioActivityKey;
  String get lastStudioCustomLabel => _lastStudioCustomLabel;

  StudioApiService get studioApiService {
    _studioApiService ??= StudioApiService(
      backendBaseUrl: AppConfig.backendBaseUrl,
      tokenStorage: TokenStorageService(),
      authService: authService,
      onLog: (msg, {bool isError = false}) {
        onLog('STUDIO', msg, color: isError ? Colors.red : Colors.green);
      },
    );
    return _studioApiService!;
  }

  Future<void> loadLastStudioActivity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = prefs.getString(StudioSessionDialog.prefLastActivityKey);
      final custom = prefs.getString(StudioSessionDialog.prefLastCustomLabel);
      if (key != null && StudioSessionDialog.defaultActivities.any((a) => a.key == key)) {
        _lastStudioActivityKey = key;
        if (custom != null) _lastStudioCustomLabel = custom;
        onStateUpdated();
      }
    } catch (_) {}
  }

  void rememberStudioActivity({
    required String activityKey,
    required String customLabel,
  }) {
    _lastStudioActivityKey = activityKey;
    if (activityKey == 'custom') {
      _lastStudioCustomLabel = customLabel;
    }
    onStateUpdated();
  }

  Future<StudioDatasetStats?> fetchStudioStats() async {
    try {
      return await studioApiService.getStudioStats(deviceId: deviceId);
    } catch (e) {
      onLog('STUDIO', 'Impossible de charger les statistiques Studio : $e', color: Colors.orange);
      return null;
    }
  }

  Future<bool> triggerStudioSession({
    required String label,
    required double durationSec,
  }) async {
    final client = getBleClient();
    final status = getBleStatus();
    final isConnected = client != null &&
        (status == BleConnectionStatus.ready || status == BleConnectionStatus.connected) &&
        client.hasStudioControl;

    if (!isConnected) {
      onLog('STUDIO', 'Chaussure non connectée ou service Studio indisponible.', color: Colors.red);
      return false;
    }

    if (!getIsSensorCalibrated()) {
      onLog('STUDIO', 'Enregistrement annulé : le capteur d\'assiette n\'a pas encore été calibré.', color: Colors.orange);
      return false;
    }

    onLog('STUDIO', 'Démarrage session Studio (${durationSec.toStringAsFixed(1)}s, label: $label)...');

    try {
      await onEnsureMqttConnected();

      var coordinator = getCoordinator();
      if (coordinator == null) {
        onSetupCoordinator();
        coordinator = getCoordinator();
      }

      if (coordinator != null) {
        onLog('STUDIO', 'Réservation REST de la session auprès du backend FastAPI (/commands/studio/start)...');
        await coordinator.triggerStudioSession(
          label: label,
          durationSec: durationSec,
        );
      } else {
        String sessionId;
        try {
          onLog('STUDIO', 'Réservation REST directe auprès du backend FastAPI...');
          final resp = await studioApiService.startStudioSession(
            deviceId: deviceId,
            label: label,
            durationSec: durationSec,
          );
          sessionId = resp.sessionId;
          onLog('STUDIO', 'Session réservée : $sessionId', color: Colors.green);
        } catch (e) {
          sessionId = const Uuid().v4();
          onLog('STUDIO', 'Erreur réservation REST ($e), fallback local : $sessionId', color: Colors.orange);
        }

        await client.startStudioSession(
          label: label,
          durationSec: durationSec,
          sessionId: sessionId,
        );
      }
      onLog('STUDIO', 'Ordre START envoyé à la chaussure. En attente du flux burst...', color: Colors.indigo);
      return true;
    } catch (e) {
      onLog('STUDIO', 'Échec lancement session Studio : $e', color: Colors.red);
      return false;
    }
  }
}
