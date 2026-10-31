import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:healthkicks_mobile/services/fall_sensitivity_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FallSensitivitySettingsService - Unit & Persistence Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Initializes with default values (1.38 g threshold, Équilibrée / Recommandée)', () async {
      final service = FallSensitivitySettingsService();
      await service.loadSettings();

      expect(service.thresholdG, equals(1.38));
      expect(service.thresholdMs2, closeTo(13.53, 0.05));
      expect(service.sensitivityLabel, equals('Équilibrée (Recommandée)'));
      expect(service.isSynced, isFalse);
    });

    test('Loads persisted values from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        FallSensitivitySettingsService.keyThresholdG: 1.10,
      });

      final service = FallSensitivitySettingsService();
      await service.loadSettings();

      expect(service.thresholdG, equals(1.10));
      expect(service.thresholdMs2, closeTo(10.79, 0.05));
      expect(service.sensitivityLabel, equals('Très sensible'));
    });

    test('Clamps out-of-range values to default on load', () async {
      SharedPreferences.setMockInitialValues({
        FallSensitivitySettingsService.keyThresholdG: 5.0,
      });

      final service = FallSensitivitySettingsService();
      await service.loadSettings();

      expect(service.thresholdG, equals(FallSensitivitySettingsService.defaultThresholdG));
    });

    test('updateThreshold updates state, snaps to 0.05 step, and persists to SharedPreferences', () async {
      final service = FallSensitivitySettingsService();
      await service.loadSettings();

      await service.updateThreshold(0.82); // Should snap to 0.80
      expect(service.thresholdG, equals(0.80));
      expect(service.sensitivityLabel, equals('Ultra sensible (Démo)'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(FallSensitivitySettingsService.keyThresholdG), equals(0.80));

      await service.updateThreshold(1.88); // Should snap to 1.90
      expect(service.thresholdG, equals(1.90));
      expect(service.sensitivityLabel, equals('Robuste'));
    });

    test('Labels cover full spectrum correctly', () {
      expect(FallSensitivitySettingsService.getSensitivityLabel(0.80), equals('Ultra sensible (Démo)'));
      expect(FallSensitivitySettingsService.getSensitivityLabel(1.00), equals('Très sensible'));
      expect(FallSensitivitySettingsService.getSensitivityLabel(1.20), equals('Sensible'));
      expect(FallSensitivitySettingsService.getSensitivityLabel(1.35), equals('Équilibrée (Recommandée)'));
      expect(FallSensitivitySettingsService.getSensitivityLabel(1.40), equals('Équilibrée (Recommandée)'));
      expect(FallSensitivitySettingsService.getSensitivityLabel(1.50), equals('Modérée'));
      expect(FallSensitivitySettingsService.getSensitivityLabel(1.65), equals('Modérée'));
      expect(FallSensitivitySettingsService.getSensitivityLabel(1.70), equals('Robuste'));
      expect(FallSensitivitySettingsService.getSensitivityLabel(1.90), equals('Robuste'));
    });
  });
}
