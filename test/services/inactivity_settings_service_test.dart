import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:healthkicks_mobile/services/inactivity_settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InactivitySettingsService - Unit & Persistence Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Initializes with default values (50 min threshold, 10 min cooldown, enabled, repeatEnabled)', () async {
      final service = InactivitySettingsService();
      await service.loadSettings();

      expect(service.isEnabled, isTrue);
      expect(service.isRepeatEnabled, isTrue);
      expect(service.thresholdMinutes, equals(50));
      expect(service.cooldownMinutes, equals(10));
      expect(service.thresholdSec, equals(3000));
      expect(service.cooldownSec, equals(600));
      expect(service.isSynced, isFalse);
    });

    test('Loads persisted values from SharedPreferences including repeatEnabled', () async {
      SharedPreferences.setMockInitialValues({
        InactivitySettingsService.keyEnabled: false,
        InactivitySettingsService.keyRepeatEnabled: false,
        InactivitySettingsService.keyThresholdMin: 45,
        InactivitySettingsService.keyCooldownMin: 15,
      });

      final service = InactivitySettingsService();
      await service.loadSettings();

      expect(service.isEnabled, isFalse);
      expect(service.isRepeatEnabled, isFalse);
      expect(service.thresholdMinutes, equals(45));
      expect(service.cooldownMinutes, equals(15));
      expect(service.thresholdSec, equals(2700));
      expect(service.cooldownSec, equals(0)); // When repeat is disabled, cooldownSec is 0
    });

    test('updateSettings updates state and persists to SharedPreferences', () async {
      final service = InactivitySettingsService();
      await service.loadSettings();

      await service.updateSettings(
        enabled: true,
        repeatEnabled: false,
        thresholdMinutes: 60,
        cooldownMinutes: 20,
      );

      expect(service.isEnabled, isTrue);
      expect(service.isRepeatEnabled, isFalse);
      expect(service.thresholdMinutes, equals(60));
      expect(service.cooldownMinutes, equals(20));
      expect(service.thresholdSec, equals(3600));
      expect(service.cooldownSec, equals(0)); // 0 when repeatEnabled is false

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(InactivitySettingsService.keyEnabled), isTrue);
      expect(prefs.getBool(InactivitySettingsService.keyRepeatEnabled), isFalse);
      expect(prefs.getInt(InactivitySettingsService.keyThresholdMin), equals(60));
      expect(prefs.getInt(InactivitySettingsService.keyCooldownMin), equals(20));

      // Re-enable repeats
      await service.updateSettings(
        enabled: true,
        repeatEnabled: true,
        thresholdMinutes: 60,
        cooldownMinutes: 20,
      );
      expect(service.isRepeatEnabled, isTrue);
      expect(service.cooldownSec, equals(1200));
    });
  });
}

