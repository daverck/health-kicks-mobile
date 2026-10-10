import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/localization/app_language.dart';

/// Service managing the application's locale and language settings with local persistence.
class LocaleService extends ChangeNotifier {
  static const String localeStorageKey = 'hk_app_language';

  Locale? _currentLocale; // If null, defaults to French or system language

  /// Returns the current active [Locale], or null if following system/default.
  Locale? get currentLocale => _currentLocale;

  /// Returns the [AppLanguage] metadata for the current locale.
  AppLanguage get currentLanguage {
    if (_currentLocale == null) {
      return AppLanguage.supported.first; // Default French
    }
    return AppLanguage.fromCode(_currentLocale!.languageCode);
  }

  /// Whether current language is Right-to-Left (e.g. Arabic).
  bool get isRtl => currentLanguage.isRtl;

  /// Loads the persisted locale from [SharedPreferences].
  Future<void> loadLocale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedCode = prefs.getString(localeStorageKey);
      if (storedCode != null &&
          AppLanguage.supportedLocales.any((l) => l.languageCode == storedCode)) {
        _currentLocale = Locale(storedCode);
        notifyListeners();
      }
    } catch (_) {
      // Graceful fallback to default on read failure
    }
  }

  /// Updates and persists the selected [Locale].
  Future<void> setLocale(Locale locale) async {
    if (!AppLanguage.supportedLocales
        .any((l) => l.languageCode == locale.languageCode)) {
      return;
    }
    _currentLocale = locale;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(localeStorageKey, locale.languageCode);
    } catch (_) {
      // Ignore write errors to keep UI responsive
    }
  }

  /// Convenience helper to set language by string code (e.g. 'fr', 'en', 'ar').
  Future<void> setLanguageCode(String code) async {
    await setLocale(Locale(code));
  }
}

