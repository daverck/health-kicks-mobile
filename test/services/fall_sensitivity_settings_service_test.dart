import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:healthkicks_mobile/services/fall_sensitivity_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FallSensitivitySettingsService - Unit & Persistence Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Initializes with default values (1.65 g threshold, Équilibrée / Recommandée)', () async {
      final service = FallSensitivitySettingsService();
      await service.loadSettings();

      expect(service.thresholdG, equals(1.65));
      expect(service.thresholdMs2, closeTo(16.18, 0.02));
      expect(service.sensitivityLabel, equals('Équilibrée (Recommandée)'));
      expect(service.isSynced, isFalse);
    });

    test('Loads persisted values from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        FallSensitivitySettingsService.keyThresholdG: 1.50,
      });

      final service = FallSensitivitySettingsService();
      await service.loadSettings();

      expect(service.thresholdG, equals(1.50));
      expect(service.thresholdMs2, closeTo(14.71, 0.02));
      expect(service.sensitivityLabel, equals('Sensible'));
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

      await service.updateThreshold(1.42); // Should snap to 1.40
      expect(service.thresholdG, equals(1.40));
      expect(service.sensitivityLabel, equals('Très sensible'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(FallSensitivitySettingsService.keyThresholdG), equals(1.40));

      await service.updateThreshold(1.88); // Should snap to 1.90
      expect(service.thresholdG, equals(1.90));
      expect(service.sensitivityLabel, equals('Robuste'));
    });

    test('Labels cover full spectrum correctly', () {
      expect(FallSensitivitySettingsService.getSensitivityLabel(1.40), equals('Très sensible'));
      expect(FallSensitivitySettingsService.getSensitivityLabel(1.45), equals('Sensibilité ++'));
      expect(FallSensitivitySettingsService.getSensitivityLabel(1.50), equals('Sensible'));
      expect(FallSensitivitySettingsService.getSensitivityLabel(1.55), equals('Sensible'));
      expect(FallSensitivitySettingsService.getSensitivityLabel(1.60), equals('Équilibrée (Recommandée)'));
      expect(FallSensitivitySettingsService.getSensitivityLabel(1.65), equals('Équilibrée (Recommandée)'));
      expect(FallSensitivitySettingsService.getSensitivityLabel(1.70), equals('Modérée'));
      expect(FallSensitivitySettingsService.getSensitivityLabel(1.80), equals('Modérée'));
      expect(FallSensitivitySettingsService.getSensitivityLabel(1.85), equals('Robuste'));
      expect(FallSensitivitySettingsService.getSensitivityLabel(1.90), equals('Robuste'));
    });
  });
}
