import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Available theme modes for the HealthKicks mobile application.
enum AppThemeMode {
  system,
  light,
  dark,
}

/// Service managing the application's visual theme mode with local persistence.
class ThemeService extends ChangeNotifier {
  static const String themeStorageKey = 'hk_app_theme_mode';

  AppThemeMode _currentMode = AppThemeMode.system;

  AppThemeMode get currentMode => _currentMode;

  /// Translates [AppThemeMode] to Flutter's native [ThemeMode].
  ThemeMode get themeMode {
    switch (_currentMode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }

  /// Loads the persisted theme mode from [SharedPreferences].
  Future<void> loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedMode = prefs.getString(themeStorageKey);
      if (storedMode != null) {
        if (storedMode == 'light') {
          _currentMode = AppThemeMode.light;
        } else if (storedMode == 'dark') {
          _currentMode = AppThemeMode.dark;
        } else {
          _currentMode = AppThemeMode.system;
        }
        notifyListeners();
      }
    } catch (_) {
      // Fallback gracefully to system default if storage read fails
    }
  }

  /// Updates and persists the selected [AppThemeMode].
  Future<void> setThemeMode(AppThemeMode mode) async {
    _currentMode = mode;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      String modeStr;
      switch (mode) {
        case AppThemeMode.light:
          modeStr = 'light';
          break;
        case AppThemeMode.dark:
          modeStr = 'dark';
          break;
        case AppThemeMode.system:
          modeStr = 'system';
          break;
      }
      await prefs.setString(themeStorageKey, modeStr);
    } catch (_) {
      // Ignore write errors to maintain responsive UI
    }
  }
}
