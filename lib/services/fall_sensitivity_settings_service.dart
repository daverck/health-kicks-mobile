import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ble/ble_footwear_client.dart';

/// Service managing user preference for on-device fall detection sensitivity (impact threshold in g / m/s^2)
/// and synchronizing parameters with the HealthKicks footwear over BLE Characteristic 0004 (SET_FALL_IMPACT).
class FallSensitivitySettingsService extends ChangeNotifier {
  static const String keyThresholdG = 'fall_impact_threshold_g';
  static const double defaultThresholdG = 1.65;
  static const double gravityMs2 = 9.80665;

  // Discrete range: 1.40 g to 1.90 g with 10 divisions (step of 0.05 g)
  static const double minThresholdG = 1.40;
  static const double maxThresholdG = 1.90;
  static const int divisions = 10;

  double _thresholdG = defaultThresholdG;
  bool _isSynced = false;

  double get thresholdG => _thresholdG;
  double get thresholdMs2 => _thresholdG * gravityMs2;
  bool get isSynced => _isSynced;

  String get sensitivityLabel => getSensitivityLabel(_thresholdG);

  static String getSensitivityLabel(double g) {
    if (g <= 1.42) return 'Très sensible';
    if (g <= 1.47) return 'Sensibilité ++';
    if (g <= 1.57) return 'Sensible';
    if (g <= 1.67) return 'Équilibrée (Recommandée)';
    if (g <= 1.82) return 'Modérée';
    return 'Robuste';
  }

  /// Loads persisted settings from SharedPreferences.
  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _thresholdG = prefs.getDouble(keyThresholdG) ?? defaultThresholdG;
    if (_thresholdG < minThresholdG || _thresholdG > maxThresholdG) {
      _thresholdG = defaultThresholdG;
    }
    notifyListeners();
  }

  /// Updates fall sensitivity threshold, persists to SharedPreferences, and syncs over BLE if client is connected.
  Future<void> updateThreshold(
    double thresholdG, {
    BleFootwearClient? bleClient,
  }) async {
    final stepped = (thresholdG * 20).round() / 20.0;
    _thresholdG = stepped.clamp(minThresholdG, maxThresholdG);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(keyThresholdG, _thresholdG);

    if (bleClient != null && bleClient.hasStudioControl) {
      await syncToBle(bleClient);
    } else {
      _isSynced = false;
      notifyListeners();
    }
  }

  /// Pushes current fall impact threshold to the footwear over BLE.
  Future<bool> syncToBle(BleFootwearClient bleClient) async {
    try {
      await bleClient.sendFallImpactConfig(thresholdMs2);
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
