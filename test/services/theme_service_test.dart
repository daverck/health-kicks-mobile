import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:healthkicks_mobile/services/theme_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeService - Unit & Persistence Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Initializes with default system mode', () async {
      final service = ThemeService();
      await service.loadTheme();

      expect(service.currentMode, equals(AppThemeMode.system));
      expect(service.themeMode, equals(ThemeMode.system));
    });

    test('Loads persisted light theme from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        ThemeService.themeStorageKey: 'light',
      });

      final service = ThemeService();
      await service.loadTheme();

      expect(service.currentMode, equals(AppThemeMode.light));
      expect(service.themeMode, equals(ThemeMode.light));
    });

    test('Loads persisted dark theme from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        ThemeService.themeStorageKey: 'dark',
      });

      final service = ThemeService();
      await service.loadTheme();

      expect(service.currentMode, equals(AppThemeMode.dark));
      expect(service.themeMode, equals(ThemeMode.dark));
    });

    test('setThemeMode updates state, notifies listeners, and persists value', () async {
      final service = ThemeService();
      await service.loadTheme();

      int notificationsCount = 0;
      service.addListener(() {
        notificationsCount++;
      });

      await service.setThemeMode(AppThemeMode.light);
      expect(service.currentMode, equals(AppThemeMode.light));
      expect(service.themeMode, equals(ThemeMode.light));
      expect(notificationsCount, equals(1));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ThemeService.themeStorageKey), equals('light'));

      await service.setThemeMode(AppThemeMode.dark);
      expect(service.currentMode, equals(AppThemeMode.dark));
      expect(service.themeMode, equals(ThemeMode.dark));
      expect(notificationsCount, equals(2));
      expect(prefs.getString(ThemeService.themeStorageKey), equals('dark'));

      await service.setThemeMode(AppThemeMode.system);
      expect(service.currentMode, equals(AppThemeMode.system));
      expect(service.themeMode, equals(ThemeMode.system));
      expect(notificationsCount, equals(3));
      expect(prefs.getString(ThemeService.themeStorageKey), equals('system'));
    });
  });
}
