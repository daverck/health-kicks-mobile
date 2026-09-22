import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ble/ble_footwear_client.dart';

/// Service managing prolonged inactivity (sedentary reminder) user preferences
/// and synchronizing parameters with the HealthKicks footwear over BLE Characteristic 0003.
class InactivitySettingsService extends ChangeNotifier {
  static const String keyEnabled = 'inact_enabled';
  static const String keyRepeatEnabled = 'inact_repeat_enabled';
  static const String keyThresholdMin = 'inact_threshold_min';
  static const String keyCooldownMin = 'inact_cooldown_min';

  bool _isEnabled = true;
  bool _isRepeatEnabled = true;
  int _thresholdMinutes = 50;
  int _cooldownMinutes = 10;
  bool _isSynced = false;

  bool get isEnabled => _isEnabled;
  bool get isRepeatEnabled => _isRepeatEnabled;
  int get thresholdMinutes => _thresholdMinutes;
  int get cooldownMinutes => _cooldownMinutes;
  int get thresholdSec => _thresholdMinutes * 60;
  int get cooldownSec => _isRepeatEnabled ? _cooldownMinutes * 60 : 0;
  bool get isSynced => _isSynced;

  /// Loads persisted settings from SharedPreferences.
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool(keyEnabled) ?? true;
    _isRepeatEnabled = prefs.getBool(keyRepeatEnabled) ?? true;
    _thresholdMinutes = prefs.getInt(keyThresholdMin) ?? 50;
    _cooldownMinutes = prefs.getInt(keyCooldownMin) ?? 10;
    notifyListeners();
  }

  /// Updates inactivity settings, persists to SharedPreferences, and syncs over BLE if client is connected.
  Future<void> updateSettings({
    required bool enabled,
    bool? repeatEnabled,
    required int thresholdMinutes,
    required int cooldownMinutes,
    BleFootwearClient? bleClient,
  }) async {
    _isEnabled = enabled;
    if (repeatEnabled != null) {
      _isRepeatEnabled = repeatEnabled;
    }
    _thresholdMinutes = thresholdMinutes;
    _cooldownMinutes = cooldownMinutes;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyEnabled, _isEnabled);
    await prefs.setBool(keyRepeatEnabled, _isRepeatEnabled);
    await prefs.setInt(keyThresholdMin, _thresholdMinutes);
    await prefs.setInt(keyCooldownMin, _cooldownMinutes);

    if (bleClient != null && bleClient.hasHaptic) {
      await syncToBle(bleClient);
    } else {
      _isSynced = false;
      notifyListeners();
    }
  }

  /// Pushes current inactivity settings payload (Opcode 0x06) to the footwear.
  Future<bool> syncToBle(BleFootwearClient bleClient) async {
    try {
      await bleClient.sendInactivityConfig(
        enabled: _isEnabled,
        thresholdSec: thresholdSec,
        cooldownSec: cooldownSec,
      );
      _isSynced = true;
      notifyListeners();
      return true;
    } catch (e) {
      _isSynced = false;
      notifyListeners();
      return false;
    }
  }
}

