import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:healthkicks_mobile/services/inactivity_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InactivitySettingsService - Unit & Persistence Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Initializes with default values (50 min threshold, 10 min cooldown, enabled)', () async {
      final service = InactivitySettingsService();
      await service.loadSettings();

      expect(service.isEnabled, isTrue);
      expect(service.thresholdMinutes, equals(50));
      expect(service.cooldownMinutes, equals(10));
      expect(service.thresholdSec, equals(3000));
      expect(service.cooldownSec, equals(600));
      expect(service.isSynced, isFalse);
    });

    test('Loads persisted values from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        InactivitySettingsService.keyEnabled: false,
        InactivitySettingsService.keyThresholdMin: 45,
        InactivitySettingsService.keyCooldownMin: 15,
      });

      final service = InactivitySettingsService();
      await service.loadSettings();

      expect(service.isEnabled, isFalse);
      expect(service.thresholdMinutes, equals(45));
      expect(service.cooldownMinutes, equals(15));
      expect(service.thresholdSec, equals(2700));
      expect(service.cooldownSec, equals(900));
    });

    test('updateSettings updates state and persists to SharedPreferences', () async {
      final service = InactivitySettingsService();
      await service.loadSettings();

      await service.updateSettings(
        enabled: true,
        thresholdMinutes: 60,
        cooldownMinutes: 20,
      );

      expect(service.isEnabled, isTrue);
      expect(service.thresholdMinutes, equals(60));
      expect(service.cooldownMinutes, equals(20));
      expect(service.thresholdSec, equals(3600));
      expect(service.cooldownSec, equals(1200));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(InactivitySettingsService.keyEnabled), isTrue);
      expect(prefs.getInt(InactivitySettingsService.keyThresholdMin), equals(60));
      expect(prefs.getInt(InactivitySettingsService.keyCooldownMin), equals(20));
    });
  });
}

