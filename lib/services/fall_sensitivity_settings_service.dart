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

  /// Default cooldown between consecutive fall alerts in seconds (3.0s = 3000 ms)
  static const double defaultCooldownSeconds = 3.0;

  /// Minimum allowed fall cooldown in seconds (0.5s = 500 ms)
  static const double minCooldownSeconds = 0.5;

  /// Maximum allowed fall cooldown in seconds (30.0s = 30000 ms)
  static const double maxCooldownSeconds = 30.0;

  /// Number of discrete slider divisions for the cooldown UI (0.5s steps from 0.5s to 30.0s)
  static const int cooldownSliderDivisions = 59;

  double _threshold = defaultThreshold;
  double _cooldownSeconds = defaultCooldownSeconds;
  bool _isSynced = false;

  double get threshold => _threshold;
  double get cooldownSeconds => _cooldownSeconds;
  int get cooldownMs => (_cooldownSeconds * 1000).round();
  bool get isSynced => _isSynced;

  /// Formats the cooldown in seconds for display (e.g., "0.5 s", "3 s", "15 s").
  String get cooldownFormatted => formatCooldownSeconds(_cooldownSeconds);

  /// Formats any cooldown value in seconds cleanly (omitting ".0" for whole seconds).
  static String formatCooldownSeconds(double seconds) {
    if (seconds == seconds.roundToDouble()) {
      return '${seconds.toInt()} s';
    }
    return '${seconds.toStringAsFixed(1)} s';
  }

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

    final rawCooldown = prefs.get(keyCooldownSeconds);
    final loadedCooldown = rawCooldown is num ? rawCooldown.toDouble() : defaultCooldownSeconds;
    _cooldownSeconds = ((loadedCooldown * 2).round() / 2.0).clamp(minCooldownSeconds, maxCooldownSeconds);
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

  /// Sets the fall cooldown in seconds (0.5s increments), persists to SharedPreferences, and syncs over BLE if client is connected.
  Future<void> setCooldownSeconds(num seconds, {BleFootwearClient? bleClient}) async {
    final clamped = ((seconds.toDouble() * 2).round() / 2.0).clamp(minCooldownSeconds, maxCooldownSeconds);

    if (clamped == _cooldownSeconds) return;

    _cooldownSeconds = clamped;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(keyCooldownSeconds, _cooldownSeconds);

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
