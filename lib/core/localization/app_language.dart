import 'package:flutter/material.dart';

/// Represents a language supported by the HealthKicks mobile application.
/// Matches the language suite supported by the web frontend.
class AppLanguage {
  final String code;
  final String name;
  final String nativeName;
  final String flag;
  final bool isRtl;

  const AppLanguage({
    required this.code,
    required this.name,
    required this.nativeName,
    required this.flag,
    this.isRtl = false,
  });

  Locale get locale => Locale(code);

  /// List of all 7 supported languages, matching health-kicks-frontend.
  static const List<AppLanguage> supported = [
    AppLanguage(
      code: 'fr',
      name: 'Français',
      nativeName: 'Français',
      flag: '🇫🇷',
    ),
    AppLanguage(
      code: 'en',
      name: 'Anglais',
      nativeName: 'English',
      flag: '🇬🇧',
    ),
    AppLanguage(
      code: 'nl',
      name: 'Néerlandais',
      nativeName: 'Nederlands',
      flag: '🇳🇱',
    ),
    AppLanguage(
      code: 'es',
      name: 'Espagnol',
      nativeName: 'Español',
      flag: '🇪🇸',
    ),
    AppLanguage(
      code: 'de',
      name: 'Allemand',
      nativeName: 'Deutsch',
      flag: '🇩🇪',
    ),
    AppLanguage(
      code: 'ar',
      name: 'Arabe',
      nativeName: 'العربية',
      flag: '🇸🇦',
      isRtl: true,
    ),
    AppLanguage(
      code: 'zh',
      name: 'Chinois',
      nativeName: '中文',
      flag: '🇨🇳',
    ),
  ];

  /// Supported Flutter locales for MaterialApp.
  static const List<Locale> supportedLocales = [
    Locale('fr'),
    Locale('en'),
    Locale('nl'),
    Locale('es'),
    Locale('de'),
    Locale('ar'),
    Locale('zh'),
  ];

  /// Resolves an [AppLanguage] from its ISO code, falling back to French.
  static AppLanguage fromCode(String? code) {
    if (code == null) return supported.first;
    return supported.firstWhere(
      (lang) => lang.code.toLowerCase() == code.toLowerCase(),
      orElse: () => supported.first,
    );
  }
}

