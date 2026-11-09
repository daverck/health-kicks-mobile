import 'dart:async';
import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../services/auth/auth_service.dart';
import '../services/auth/iot_credentials_repository.dart';
import '../services/auth/token_storage_service.dart';
import '../services/mqtt/mqtt_gateway_service.dart';

/// Coordinator encapsulating AWS IoT Core MQTT connectivity, credentials repository,
/// connection state notifiers, and device/gateway presence publishing for the Gateway Dashboard.
class DashboardMqttCoordinator {
  final String deviceId;
  final AuthService? authService;
  final TokenStorageService _tokenStorage;

  IotCredentialsRepository? _credentialsRepo;
  MqttGatewayService? _mqttService;
  bool _mqttConnected = false;
  final ValueNotifier<bool> _mqttConnectedNotifier = ValueNotifier<bool>(false);
  bool _isDisposed = false;

  MqttGatewayService? get mqttService => _mqttService;
  IotCredentialsRepository? get credentialsRepo => _credentialsRepo;
  bool get isMqttConnected => _mqttConnected;
  ValueNotifier<bool> get mqttConnectedNotifier => _mqttConnectedNotifier;

  DashboardMqttCoordinator({
    required this.deviceId,
    this.authService,
    IotCredentialsRepository? credentialsRepo,
    MqttGatewayService? mqttService,
    TokenStorageService? tokenStorage,
  })  : _credentialsRepo = credentialsRepo,
        _mqttService = mqttService,
        _tokenStorage = tokenStorage ?? TokenStorageService();

  Future<void> connectMqtt({
    required void Function(String tag, String message, {Color? color}) addLog,
    required void Function(bool connected) onMqttStateChanged,
    required Future<void> Function() onConnectionRestored,
    required bool Function() isBleConnectedGetter,
    required Future<void> Function() onBleOnlineSync,
  }) async {
    try {
      _credentialsRepo ??= IotCredentialsRepository(
        backendBaseUrl: AppConfig.backendBaseUrl,
        tokenStorage: _tokenStorage,
        authService: authService,
        onLog: (msg, {bool isError = false}) {
          addLog('AUTH', msg, color: isError ? Colors.red : Colors.cyan);
        },
      );

      var currentUserId = authService?.currentUserId;
      if (currentUserId == null || currentUserId.isEmpty) {
        currentUserId = await _tokenStorage.getUserIdFromToken();
      }

      if (currentUserId == null || currentUserId.isEmpty) {
        for (int i = 0; i < 6 && (currentUserId == null || currentUserId.isEmpty); i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (_isDisposed) return;
          currentUserId = authService?.currentUserId;
          if (currentUserId == null || currentUserId.isEmpty) {
            currentUserId = await _tokenStorage.getUserIdFromToken();
          }
        }
      }

      if (currentUserId == null || currentUserId.isEmpty || currentUserId == 'unknown') {
        addLog(
          'MQTT',
          'Connexion MQTT différée : utilisateur non authentifié ou userId introuvable.',
          color: Colors.amber,
        );
        _setConnected(false);
        onMqttStateChanged(false);
        return;
      }

      if (_mqttService != null && _mqttService!.userId != currentUserId) {
        _mqttService?.disconnect();
        _mqttService = null;
      }

      _mqttService ??= MqttGatewayService(
        deviceId: deviceId,
        userId: currentUserId,
        credentialsRepository: _credentialsRepo!,
        authService: authService,
        onLog: (msg, {bool isError = false}) {
          addLog('MQTT', msg, color: isError ? Colors.red : Colors.teal);
        },
        onConnectionLost: () {
          if (_isDisposed) return;
          _setConnected(false);
          onMqttStateChanged(false);
        },
        onConnectionRestored: () async {
          if (_isDisposed) return;
          _setConnected(true);
          onMqttStateChanged(true);
          await onConnectionRestored();
        },
      );

      final connected = await _mqttService!.connect();
      _setConnected(connected);
      onMqttStateChanged(connected);

      if (connected) {
        if (isBleConnectedGetter()) {
          await onBleOnlineSync();
        } else {
          addLog('GATEWAY', 'MQTT connecté et BLE en mode scan/déconnecté : notification statut offline...', color: Colors.grey);
          await _mqttService!.publishDeviceStatus(online: false);
        }
      }
    } catch (e) {
      addLog('MQTT', 'Erreur MQTT inattendue : $e', color: Colors.red);
      _setConnected(false);
      onMqttStateChanged(false);
    }
  }

  void _setConnected(bool value) {
    _mqttConnected = value;
    _mqttConnectedNotifier.value = value;
  }

  Future<void> publishDeviceStatus({required bool online}) async {
    await _mqttService?.publishDeviceStatus(online: online);
  }

  Future<void> publishGatewayStatus({required bool online}) async {
    await _mqttService?.publishGatewayStatus(online: online);
  }

  void disconnect() {
    _mqttService?.disconnect();
    _setConnected(false);
  }

  void dispose() {
    _isDisposed = true;
    _mqttService?.disconnect();
    _mqttConnectedNotifier.dispose();
  }
}
