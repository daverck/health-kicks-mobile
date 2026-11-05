import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ble/ble_footwear_client.dart';

/// Service managing fall detection confidence threshold and cooldown user preferences
/// and synchronizing parameters with the HealthKicks footwear over BLE Characteristic 0004 (Device & Studio Control).
class FallSensitivitySettingsService extends ChangeNotifier {
  static const String keyThreshold = 'fall_confidence_threshold';
  static const String keyCooldownSeconds = 'fall_cooldown_seconds';

  /// Default confidence threshold for fall detection (65%)
  static const double defaultThreshold = 0.65;

  /// Minimum allowed confidence threshold
  static const double minThreshold = 0.35;

  /// Maximum allowed confidence threshold
  static const double maxThreshold = 0.85;

  /// Number of discrete slider divisions for the confidence UI
  static const int sliderDivisions = 10;

  /// Default cooldown between consecutive fall alerts in seconds (5s = 5000 ms)
  static const int defaultCooldownSeconds = 5;

  /// Minimum allowed fall cooldown in seconds (1s = 1000 ms)
  static const int minCooldownSeconds = 1;

  /// Maximum allowed fall cooldown in seconds (30s = 30000 ms)
  static const int maxCooldownSeconds = 30;

  /// Number of discrete slider divisions for the cooldown UI (1s steps from 1s to 30s)
  static const int cooldownSliderDivisions = 29;

  double _threshold = defaultThreshold;
  int _cooldownSeconds = defaultCooldownSeconds;
  bool _isSynced = false;

  double get threshold => _threshold;
  int get cooldownSeconds => _cooldownSeconds;
  int get cooldownMs => _cooldownSeconds * 1000;
  bool get isSynced => _isSynced;

  /// Get the threshold as a percentage (0-100)
  int get thresholdPercentage => (_threshold * 100).round();

  /// Get adaptive label based on threshold value
  String get sensitivityLabel {
    if (_threshold <= 0.40) {
      return 'Ultra sensible';
    } else if (_threshold <= 0.45) {
      return 'Démo';
    } else if (_threshold <= 0.55) {
      return 'Très sensible';
    } else if (_threshold <= 0.70) {
      return 'Équilibrée';
    } else if (_threshold <= 0.75) {
      return 'Recommandée';
    } else {
      return 'Robuste';
    }
  }

  /// Get description for the current sensitivity level
  String get sensitivityDescription {
    if (_threshold <= 0.40) {
      return 'Détecte presque toutes les anomalies de mouvement comme des chutes';
    } else if (_threshold <= 0.45) {
      return 'Mode démonstration - très perméable aux faux positifs';
    } else if (_threshold <= 0.55) {
      return 'Détection précoce avec quelques faux positifs acceptables';
    } else if (_threshold <= 0.70) {
      return 'Équilibre optimal entre détection et précision';
    } else if (_threshold <= 0.75) {
      return 'Recommandé pour un usage quotidien fiable';
    } else {
      return 'Seulement les chutes très certaines seront signalées';
    }
  }

  /// Loads persisted settings from SharedPreferences.
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _threshold = prefs.getDouble(keyThreshold) ?? defaultThreshold;
    // Clamp to valid range
    _threshold = _threshold.clamp(minThreshold, maxThreshold);

    _cooldownSeconds = prefs.getInt(keyCooldownSeconds) ?? defaultCooldownSeconds;
    _cooldownSeconds = _cooldownSeconds.clamp(minCooldownSeconds, maxCooldownSeconds);
    notifyListeners();
  }

  /// Sets the threshold value, persists to SharedPreferences, and syncs over BLE if client is connected.
  Future<void> setThreshold(double value, {BleFootwearClient? bleClient}) async {
    // Clamp to valid range
    value = value.clamp(minThreshold, maxThreshold);
    
    if (value == _threshold) return;
    
    _threshold = value;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(keyThreshold, _threshold);

    if (bleClient != null && bleClient.hasStudioControl) {
      await syncToBle(bleClient);
    } else {
      _isSynced = false;
      notifyListeners();
    }
  }

  /// Sets the fall cooldown in seconds, persists to SharedPreferences, and syncs over BLE if client is connected.
  Future<void> setCooldownSeconds(int seconds, {BleFootwearClient? bleClient}) async {
    seconds = seconds.clamp(minCooldownSeconds, maxCooldownSeconds);

    if (seconds == _cooldownSeconds) return;

    _cooldownSeconds = seconds;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyCooldownSeconds, _cooldownSeconds);

    if (bleClient != null && bleClient.hasStudioControl) {
      await syncToBle(bleClient);
    } else {
      _isSynced = false;
      notifyListeners();
    }
  }

  /// Pushes current fall confidence threshold and cooldown payloads (SET_FALL_CONFIDENCE & SET_FALL_COOLDOWN)
  /// to the footwear via Characteristic 0004.
  Future<bool> syncToBle(BleFootwearClient bleClient) async {
    try {
      await bleClient.sendFallConfidenceConfig(_threshold);
      await bleClient.sendFallCooldownConfig(cooldownMs);
      _isSynced = true;
      notifyListeners();
      return true;
    } catch (e) {
      _isSynced = false;
      notifyListeners();
      return false;
    }
  }

  /// Gets the slider value as a discrete index (0 to sliderDivisions)
  int getSliderIndex() {
    return ((_threshold - minThreshold) / (maxThreshold - minThreshold) * sliderDivisions).round();
  }

  /// Sets the threshold from a discrete slider index
  Future<void> setFromSliderIndex(int index, {BleFootwearClient? bleClient}) async {
    final value = minThreshold + (index / sliderDivisions) * (maxThreshold - minThreshold);
    await setThreshold(value, bleClient: bleClient);
  }

  /// Resets to default threshold and cooldown
  Future<void> resetToDefault({BleFootwearClient? bleClient}) async {
    await setThreshold(defaultThreshold, bleClient: bleClient);
    await setCooldownSeconds(defaultCooldownSeconds, bleClient: bleClient);
  }
}
