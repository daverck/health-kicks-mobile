import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:healthkicks_mobile/services/fall_sensitivity_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FallSensitivitySettingsService - Unit & Persistence Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Initializes with default threshold value (0.65)', () async {
      final service = FallSensitivitySettingsService();
      await service.loadSettings();

      expect(service.threshold, equals(0.65));
      expect(service.thresholdPercentage, equals(65));
      expect(service.isSynced, isFalse);
    });

    test('Clamps threshold to valid range on initialization', () async {
      SharedPreferences.setMockInitialValues({
        FallSensitivitySettingsService.keyThreshold: 0.20, // Below minimum
      });

      final service = FallSensitivitySettingsService();
      await service.loadSettings();

      expect(service.threshold, equals(FallSensitivitySettingsService.minThreshold));
      expect(service.threshold, equals(0.35));

      SharedPreferences.setMockInitialValues({
        FallSensitivitySettingsService.keyThreshold: 0.95, // Above maximum
      });

      final service2 = FallSensitivitySettingsService();
      await service2.loadSettings();

      expect(service2.threshold, equals(FallSensitivitySettingsService.maxThreshold));
      expect(service2.threshold, equals(0.85));
    });

    test('Returns correct sensitivity label based on threshold', () async {
      final service = FallSensitivitySettingsService();

      // Test Ultra sensible (threshold <= 0.40)
      await service.setThreshold(0.35);
      expect(service.sensitivityLabel, equals('Ultra sensible'));

      // Test Demo (threshold > 0.40 && <= 0.45)
      await service.setThreshold(0.43);
      expect(service.sensitivityLabel, equals('Démo'));

      // Test Très sensible (threshold > 0.45 && <= 0.55)
      await service.setThreshold(0.50);
      expect(service.sensitivityLabel, equals('Très sensible'));

      // Test Équilibrée (threshold > 0.55 && <= 0.70)
      await service.setThreshold(0.65);
      expect(service.sensitivityLabel, equals('Équilibrée'));

      // Test Recommandée (threshold > 0.70 && <= 0.75)
      await service.setThreshold(0.72);
      expect(service.sensitivityLabel, equals('Recommandée'));

      // Test Robuste (threshold > 0.75)
      await service.setThreshold(0.85);
      expect(service.sensitivityLabel, equals('Robuste'));
    });

    test('Returns correct sensitivity description based on threshold', () async {
      final service = FallSensitivitySettingsService();

      // Test Ultra sensible
      await service.setThreshold(0.35);
      expect(service.sensitivityDescription, 
          contains('Détecte presque toutes les anomalies'));

      // Test Demo
      await service.setThreshold(0.43);
      expect(service.sensitivityDescription, 
          contains('Mode démonstration'));

      // Test Équilibrée
      await service.setThreshold(0.65);
      expect(service.sensitivityDescription, 
          contains('Équilibre optimal'));

      // Test Robuste
      await service.setThreshold(0.85);
      expect(service.sensitivityDescription, 
          contains('Seulement les chutes très certaines'));
    });

    test('Loads persisted threshold value from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        FallSensitivitySettingsService.keyThreshold: 0.55,
      });

      final service = FallSensitivitySettingsService();
      await service.loadSettings();

      expect(service.threshold, equals(0.55));
      expect(service.thresholdPercentage, equals(55));
    });

    test('setThreshold updates state and persists to SharedPreferences', () async {
      final service = FallSensitivitySettingsService();
      await service.loadSettings();

      await service.setThreshold(0.50);

      expect(service.threshold, equals(0.50));
      expect(service.thresholdPercentage, equals(50));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(FallSensitivitySettingsService.keyThreshold), equals(0.50));
    });

    test('setThreshold clamps value to valid range', () async {
      final service = FallSensitivitySettingsService();
      await service.loadSettings();

      // Test below minimum
      await service.setThreshold(0.20);
      expect(service.threshold, equals(FallSensitivitySettingsService.minThreshold));

      // Test above maximum
      await service.setThreshold(0.95);
      expect(service.threshold, equals(FallSensitivitySettingsService.maxThreshold));

      // Test within range
      await service.setThreshold(0.50);
      expect(service.threshold, equals(0.50));
    });

    test('getSliderIndex and setFromSliderIndex work correctly', () async {
      final service = FallSensitivitySettingsService();
      await service.loadSettings();

      // Test slider index calculations with default threshold 0.65
      // Calculation: ((0.65 - 0.35) / (0.85 - 0.35) * 10) = (0.30 / 0.50 * 10) = 6
      final defaultIndex = service.getSliderIndex();
      expect(defaultIndex, equals(6));

      // Set to minimum
      await service.setFromSliderIndex(0);
      expect(service.threshold, closeTo(FallSensitivitySettingsService.minThreshold, 0.01));

      // Set to maximum
      await service.setFromSliderIndex(FallSensitivitySettingsService.sliderDivisions);
      expect(service.threshold, closeTo(FallSensitivitySettingsService.maxThreshold, 0.01));

      // Set to middle
      await service.setFromSliderIndex(FallSensitivitySettingsService.sliderDivisions ~/ 2);
      final expectedMiddle = FallSensitivitySettingsService.minThreshold +
          (FallSensitivitySettingsService.maxThreshold - FallSensitivitySettingsService.minThreshold) / 2;
      expect(service.threshold, closeTo(expectedMiddle, 0.01));
    });

    test('resetToDefault sets threshold back to default value', () async {
      final service = FallSensitivitySettingsService();
      await service.loadSettings();

      // Change threshold
      await service.setThreshold(0.40);
      expect(service.threshold, equals(0.40));

      // Reset to default
      await service.resetToDefault();
      expect(service.threshold, equals(FallSensitivitySettingsService.defaultThreshold));
      expect(service.threshold, equals(0.65));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(FallSensitivitySettingsService.keyThreshold), 
          equals(FallSensitivitySettingsService.defaultThreshold));
    });

    test('sliderDivisions constant has correct value', () {
      expect(FallSensitivitySettingsService.sliderDivisions, equals(10));
    });

    test('minThreshold and maxThreshold constants have correct values', () {
      expect(FallSensitivitySettingsService.minThreshold, equals(0.35));
      expect(FallSensitivitySettingsService.maxThreshold, equals(0.85));
    });

    test('defaultThreshold constant has correct value', () {
      expect(FallSensitivitySettingsService.defaultThreshold, equals(0.65));
    });

    test('Initializes with default cooldown value (3s / 3000ms)', () async {
      final service = FallSensitivitySettingsService();
      await service.loadSettings();

      expect(service.cooldownSeconds, equals(3.0));
      expect(service.cooldownMs, equals(3000));
      expect(service.cooldownFormatted, equals('3 s'));
    });

    test('setCooldownSeconds updates state, supports 0.5s steps, clamps to valid range, and persists to SharedPreferences', () async {
      final service = FallSensitivitySettingsService();
      await service.loadSettings();

      await service.setCooldownSeconds(0.5);
      expect(service.cooldownSeconds, equals(0.5));
      expect(service.cooldownMs, equals(500));
      expect(service.cooldownFormatted, equals('0.5 s'));

      await service.setCooldownSeconds(12);
      expect(service.cooldownSeconds, equals(12.0));
      expect(service.cooldownMs, equals(12000));
      expect(service.cooldownFormatted, equals('12 s'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(FallSensitivitySettingsService.keyCooldownSeconds), equals(12.0));

      // Below minimum
      await service.setCooldownSeconds(0.1);
      expect(service.cooldownSeconds, equals(FallSensitivitySettingsService.minCooldownSeconds));
      expect(service.cooldownSeconds, equals(0.5));

      // Above maximum
      await service.setCooldownSeconds(90);
      expect(service.cooldownSeconds, equals(FallSensitivitySettingsService.maxCooldownSeconds));
      expect(service.cooldownSeconds, equals(30.0));

      // Reset to default restores both threshold and cooldown
      await service.resetToDefault();
      expect(service.cooldownSeconds, equals(FallSensitivitySettingsService.defaultCooldownSeconds));
      expect(service.cooldownSeconds, equals(3.0));
    });
  });
}
