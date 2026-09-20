import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import '../services/ble/ble_connection_manager.dart';

/// Top-level entry point required by flutter_foreground_task for background isolate execution.
@pragma('vm:entry-point')
void startSurveillanceCallback() {
  FlutterForegroundTask.setTaskHandler(SurveillanceTaskHandler());
}

/// Task handler managing background notifications and button actions.
class SurveillanceTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isDestroyed) async {}

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'btn_stop') {
      FlutterForegroundTask.stopService();
    }
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationDismissed() {}
}

/// Service managing persistent Android Foreground Service (Mode Surveillance Active)
/// and automatic BLE disconnection timeout.
class BackgroundSurveillanceService extends ChangeNotifier {
  static const String _prefKeySurveillance = 'healthkicks_surveillance_active';
  static const String notificationChannelId = 'healthkicks_surveillance_channel';
  static const String notificationChannelName = 'Mode Surveillance Active';
  static const String notificationChannelDesc =
      'Maintient la passerelle BLE et MQTT active en arrière-plan';

  final void Function(String tag, String message, {bool isError})? onLog;
  final Duration disconnectTimeout;

  bool _isSurveillanceActive = false;
  bool _isInitialized = false;
  Timer? _disconnectTimer;
  BleConnectionStatus _currentBleStatus = BleConnectionStatus.disconnected;
  String _currentDeviceName = 'HK-2';

  BackgroundSurveillanceService({
    this.onLog,
    this.disconnectTimeout = AppConfig.bleDisconnectTimeout,
  });

  bool get isSurveillanceActive => _isSurveillanceActive;
  bool get isSupported => !kIsWeb && Platform.isAndroid;
  BleConnectionStatus get currentBleStatus => _currentBleStatus;

  /// Initializes the service and loads persisted user preference.
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    if (!isSupported) {
      _log('FOREGROUND', 'Foreground service non supporté sur cet OS (Android uniquement)');
      return;
    }

    _initForegroundTask();

    // Check if the service is already running natively
    final isRunning = await FlutterForegroundTask.isRunningService;
    final prefs = await SharedPreferences.getInstance();
    final savedPref = prefs.getBool(_prefKeySurveillance) ?? false;

    _isSurveillanceActive = isRunning || savedPref;
    if (_isSurveillanceActive && !isRunning) {
      // Restore active service if user had it enabled
      await startSurveillance(fromInit: true);
    }

    // Listen to task data or service stopped events if needed
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);

    notifyListeners();
  }

  void _onReceiveTaskData(dynamic data) {
    if (data == 'stop_surveillance') {
      stopSurveillance(reason: 'Arrêt demandé via la notification');
    }
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: notificationChannelId,
        channelName: notificationChannelName,
        channelDescription: notificationChannelDesc,
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Request Android notification and battery optimization exemptions.
  Future<bool> requestPermissions() async {
    if (!isSupported) return true;

    // Check notification permission for Android 13+
    final notifPermission = await FlutterForegroundTask.checkNotificationPermission();
    if (notifPermission != NotificationPermission.granted) {
      final reqResult = await FlutterForegroundTask.requestNotificationPermission();
      if (reqResult != NotificationPermission.granted) {
        _log('FOREGROUND', 'Permission de notification refusée pour le foreground service', isError: true);
        return false;
      }
    }

    // Battery optimization exemption
    final isIgnoringBattery = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    if (!isIgnoringBattery) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    return true;
  }

  /// Enables or disables the Mode Surveillance Active.
  Future<void> toggleSurveillance(bool enable) async {
    if (enable) {
      final granted = await requestPermissions();
      if (!granted) {
        _isSurveillanceActive = false;
        notifyListeners();
        return;
      }
      await startSurveillance();
    } else {
      await stopSurveillance(reason: 'Désactivé par l\'utilisateur');
    }
  }

  /// Starts the Foreground Service with permanent notification.
  Future<void> startSurveillance({bool fromInit = false}) async {
    _isSurveillanceActive = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeySurveillance, true);

    if (isSupported) {
      final notificationText = _getNotificationText(_currentBleStatus);
      final isRunning = await FlutterForegroundTask.isRunningService;
      if (isRunning) {
        await FlutterForegroundTask.updateService(
          notificationTitle: 'HealthKicks - Mode Surveillance Active',
          notificationText: notificationText,
          notificationButtons: [
            const NotificationButton(id: 'btn_stop', text: 'Arrêter'),
          ],
        );
      } else {
        await FlutterForegroundTask.startService(
          serviceId: 256,
          notificationTitle: 'HealthKicks - Mode Surveillance Active',
          notificationText: notificationText,
          notificationButtons: [
            const NotificationButton(id: 'btn_stop', text: 'Arrêter'),
          ],
          callback: startSurveillanceCallback,
        );
      }
    }

    _log('FOREGROUND', 'Mode Surveillance Active démarré (Foreground Service actif)');

    // Check if we need to start the disconnect timer immediately
    _handleDisconnectTimer(_currentBleStatus);
    notifyListeners();
  }

  /// Stops the Foreground Service and cleans up disconnect timer.
  Future<void> stopSurveillance({String? reason}) async {
    _isSurveillanceActive = false;
    _cancelDisconnectTimer();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeySurveillance, false);

    if (isSupported) {
      await FlutterForegroundTask.stopService();
    }

    _log('FOREGROUND', 'Mode Surveillance Active arrêté${reason != null ? " ($reason)" : ""}');
    notifyListeners();
  }

  /// Called when the BLE connection status changes.
  /// Updates notification text and manages the 5-minute inactivity timer.
  void onBleStatusChanged(BleConnectionStatus status, {String? deviceName}) {
    _currentBleStatus = status;
    if (deviceName != null && deviceName.isNotEmpty) {
      _currentDeviceName = deviceName;
    }

    if (!_isSurveillanceActive) return;

    _updateNotification();
    _handleDisconnectTimer(status);
  }

  void _handleDisconnectTimer(BleConnectionStatus status) {
    if (!_isSurveillanceActive) {
      _cancelDisconnectTimer();
      return;
    }

    final isConnected = (status == BleConnectionStatus.connected || status == BleConnectionStatus.ready);

    if (isConnected) {
      if (_disconnectTimer != null) {
        _log('FOREGROUND', 'Connexion BLE rétablie : annulation du timer d\'inactivité (5 min)');
        _cancelDisconnectTimer();
      }
    } else {
      // Disconnected or scanning: start 5-minute timeout timer if not already running
      if (_disconnectTimer == null) {
        _log('FOREGROUND', 'Signal BLE perdu : démarrage du timer d\'inactivité (${disconnectTimeout.inMinutes} min)');
        _disconnectTimer = Timer(disconnectTimeout, () {
          _log(
            'FOREGROUND',
            'Timeout d\'inactivité BLE (${disconnectTimeout.inMinutes} min) expiré : arrêt automatique du service',
            isError: true,
          );
          stopSurveillance(reason: 'Timeout d\'inactivité BLE (5 min)');
        });
      }
    }
  }

  void _cancelDisconnectTimer() {
    _disconnectTimer?.cancel();
    _disconnectTimer = null;
  }

  Future<void> _updateNotification() async {
    if (!isSupported || !_isSurveillanceActive) return;

    final isRunning = await FlutterForegroundTask.isRunningService;
    if (!isRunning) return;

    final notificationText = _getNotificationText(_currentBleStatus);
    await FlutterForegroundTask.updateService(
      notificationTitle: 'HealthKicks - Mode Surveillance Active',
      notificationText: notificationText,
      notificationButtons: [
        const NotificationButton(id: 'btn_stop', text: 'Arrêter'),
      ],
    );
  }

  String _getNotificationText(BleConnectionStatus status) {
    switch (status) {
      case BleConnectionStatus.ready:
      case BleConnectionStatus.connected:
        return 'Connecté à la chaussure ($_currentDeviceName)';
      case BleConnectionStatus.scanning:
        return 'Recherche du device $_currentDeviceName...';
      case BleConnectionStatus.connecting:
        return 'Connexion en cours à $_currentDeviceName...';
      case BleConnectionStatus.disconnected:
      default:
        return 'Recherche du device... (Arrêt auto dans 5 min)';
    }
  }

  void _log(String tag, String message, {bool isError = false}) {
    if (onLog != null) {
      onLog!(tag, message, isError: isError);
    }
  }

  @override
  void dispose() {
    _cancelDisconnectTimer();
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    super.dispose();
  }
}
