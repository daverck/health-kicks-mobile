import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/core/localization/app_language.dart';
import 'package:healthkicks_mobile/services/locale_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocaleService - Unit & Persistence Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Initializes with default French language', () {
      final service = LocaleService();
      expect(service.currentLocale, isNull);
      expect(service.currentLanguage.code, 'fr');
      expect(service.currentLanguage.nativeName, 'Français');
      expect(service.isRtl, isFalse);
    });

    test('Loads persisted locale from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        LocaleService.localeStorageKey: 'en',
      });

      final service = LocaleService();
      await service.loadLocale();

      expect(service.currentLocale, const Locale('en'));
      expect(service.currentLanguage.code, 'en');
      expect(service.currentLanguage.nativeName, 'English');
      expect(service.isRtl, isFalse);
    });

    test('Identifies Arabic as RTL language', () async {
      final service = LocaleService();
      await service.setLanguageCode('ar');

      expect(service.currentLocale, const Locale('ar'));
      expect(service.currentLanguage.code, 'ar');
      expect(service.currentLanguage.nativeName, 'العربية');
      expect(service.isRtl, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(LocaleService.localeStorageKey), 'ar');
    });

    test('Supports all 7 frontend languages correctly', () async {
      final service = LocaleService();
      const expectedCodes = ['fr', 'en', 'nl', 'es', 'de', 'ar', 'zh'];

      for (final code in expectedCodes) {
        await service.setLanguageCode(code);
        expect(service.currentLanguage.code, code);
        expect(AppLanguage.fromCode(code).code, code);
      }
    });

    test('Ignores invalid or unsupported language code', () async {
      final service = LocaleService();
      await service.setLanguageCode('fr');
      expect(service.currentLanguage.code, 'fr');

      // Attempt setting invalid language
      await service.setLocale(const Locale('xx'));
      expect(service.currentLanguage.code, 'fr');
    });
  });
}

