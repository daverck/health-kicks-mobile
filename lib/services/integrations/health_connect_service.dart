import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Installation and availability status of Google Health Connect on Android.
enum HealthConnectInstallationStatus {
  installed,
  notInstalled,
  unsupportedPlatform,
}

/// Service managing export synchronization with Google Health Connect (Android) and Apple HealthKit (iOS).
///
/// Ensures exclusive forward export (Footwear -> Health Connect / HealthKit) of net step counts
/// and biomechanical activities with deduplicated client record IDs.
class HealthConnectService extends ChangeNotifier {
  /// SharedPreferences key persisting whether Health Connect sync is active.
  static const String keyEnabled = 'hk_health_connect_enabled';

  /// SharedPreferences key persisting the UTC timestamp of the last successful sync.
  static const String keyLastSync = 'hk_health_connect_last_sync';

  final Health _health;
  final SharedPreferences? _prefs;
  final bool? isIosOverride;
  final bool? isAndroidOverride;

  bool _isConfigured = false;
  bool _isEnabled = false;
  DateTime? _lastSyncTime;

  HealthConnectService({
    Health? health,
    this._prefs,
    this.isIosOverride,
    this.isAndroidOverride,
  })  : _health = health ?? Health();

  /// Whether synchronization to health platform is currently enabled by user.
  bool get isEnabled => _isEnabled;

  /// Timestamp of the last successful sync to health platform.
  DateTime? get lastSyncTime => _lastSyncTime;

  /// Whether the host platform is iOS.
  bool get isIos => isIosOverride ?? (!kIsWeb && Platform.isIOS);

  /// Whether the host platform is Android.
  bool get isAndroid => isAndroidOverride ?? (!kIsWeb && Platform.isAndroid);

  /// Human-readable brand name of the underlying health sync service.
  String get platformServiceName => isIos ? 'Apple Santé' : 'Google Health Connect';

  static const List<HealthDataType> _dataTypes = [
    HealthDataType.STEPS,
  ];

  static const List<HealthDataAccess> _permissions = [
    HealthDataAccess.WRITE,
  ];

  /// Initialize state from SharedPreferences and configure Health plugin.
  Future<void> init() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool(keyEnabled) ?? false;
    final lastSyncStr = prefs.getString(keyLastSync);
    if (lastSyncStr != null) {
      _lastSyncTime = DateTime.tryParse(lastSyncStr);
    }

    try {
      await _health.configure();
      _isConfigured = true;
    } catch (e) {
      debugPrint('[HealthConnectService] Configure exception: $e');
    }
    notifyListeners();
  }

  /// Check whether health integration is available or installed on the current device.
  Future<HealthConnectInstallationStatus> checkInstallationStatus() async {
    if (isIos) {
      return HealthConnectInstallationStatus.installed;
    }
    if (isAndroid) {
      try {
        final isAvailable = await _health.isHealthConnectAvailable();
        if (isAvailable) {
          return HealthConnectInstallationStatus.installed;
        }
        return HealthConnectInstallationStatus.notInstalled;
      } catch (_) {
        return HealthConnectInstallationStatus.notInstalled;
      }
    }
    return HealthConnectInstallationStatus.unsupportedPlatform;
  }

  /// Open Google Play Store to install Google Health Connect (Android 9-13).
  Future<void> promptInstallHealthConnect() async {
    if (isAndroid) {
      try {
        await _health.installHealthConnect();
      } catch (e) {
        debugPrint('[HealthConnectService] Error launching install: $e');
      }
    }
  }

  /// Request Health Connect write permissions for steps and distance.
  Future<bool> requestWritePermissions() async {
    try {
      if (!_isConfigured) {
        await _health.configure();
        _isConfigured = true;
      }

      final status = await checkInstallationStatus();
      if (status != HealthConnectInstallationStatus.installed) {
        return false;
      }

      final hasPerm = await _health.hasPermissions(_dataTypes, permissions: _permissions);
      if (hasPerm == true) {
        return true;
      }

      final granted = await _health.requestAuthorization(_dataTypes, permissions: _permissions);
      return granted;
    } catch (e) {
      debugPrint('[HealthConnectService] requestWritePermissions error: $e');
      return false;
    }
  }

  /// Enable or disable synchronization.
  Future<void> setEnabled(bool enabled) async {
    _isEnabled = enabled;
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setBool(keyEnabled, enabled);
    notifyListeners();
  }

  /// Export daily net steps to Google Health Connect.
  Future<bool> syncDailySteps({
    required int steps,
    required DateTime date,
    String? deviceId,
  }) async {
    if (!_isEnabled || steps <= 0) {
      return false;
    }

    try {
      if (!_isConfigured) {
        await _health.configure();
        _isConfigured = true;
      }

      final startOfDay = DateTime.utc(date.year, date.month, date.day, 0, 0, 0);
      final isToday = date.year == DateTime.now().year &&
          date.month == DateTime.now().month &&
          date.day == DateTime.now().day;
      final endOfPeriod = isToday ? DateTime.now().toUtc() : DateTime.utc(date.year, date.month, date.day, 23, 59, 59);

      final clientRecordId = 'hk_steps_${deviceId ?? "footwear"}_${date.year}_${date.month}_${date.day}';

      final success = await _health.writeHealthData(
        value: steps.toDouble(),
        type: HealthDataType.STEPS,
        startTime: startOfDay,
        endTime: endOfPeriod,
        clientRecordId: clientRecordId,
      );

      if (success) {
        _lastSyncTime = DateTime.now().toUtc();
        final prefs = _prefs ?? await SharedPreferences.getInstance();
        await prefs.setString(keyLastSync, _lastSyncTime!.toIso8601String());
        notifyListeners();
      }
      return success;
    } catch (e) {
      debugPrint('[HealthConnectService] syncDailySteps failed: $e');
      return false;
    }
  }
}
