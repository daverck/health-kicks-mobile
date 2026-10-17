import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/localization/app_language.dart';
import 'core/localization/app_localizations.dart';
import 'core/theme/app_theme.dart';
import 'services/auth/auth_service.dart';
import 'services/auth/token_storage_service.dart';
import 'services/locale_service.dart';
import 'services/theme_service.dart';
import 'ui/screens/gateway_dashboard_screen.dart';
import 'ui/screens/login_screen.dart';

export 'ui/screens/gateway_dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themeService = ThemeService();
  await themeService.loadTheme();
  final localeService = LocaleService();
  await localeService.loadLocale();
  runApp(HealthKicksApp(
    themeService: themeService,
    localeService: localeService,
  ));
}

class HealthKicksApp extends StatefulWidget {
  final AuthService? authService;
  final ThemeService? themeService;
  final LocaleService? localeService;

  const HealthKicksApp({
    super.key,
    this.authService,
    this.themeService,
    this.localeService,
  });

  @override
  State<HealthKicksApp> createState() => _HealthKicksAppState();
}

class _HealthKicksAppState extends State<HealthKicksApp> {
  late final ThemeService _themeService;
  late final LocaleService _localeService;

  @override
  void initState() {
    super.initState();
    _themeService = widget.themeService ?? ThemeService();
    if (widget.themeService == null) {
      _themeService.loadTheme();
    }
    _localeService = widget.localeService ?? LocaleService();
    if (widget.localeService == null) {
      _localeService.loadLocale();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_themeService, _localeService]),
      builder: (context, _) {
        return MaterialApp(
          title: 'HealthKicks Mobile',
          debugShowCheckedModeBanner: false,
          themeMode: _themeService.themeMode,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          locale: _localeService.currentLocale,
          supportedLocales: AppLanguage.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: AuthGate(
            authService: widget.authService,
            themeService: _themeService,
            localeService: _localeService,
          ),
        );
      },
    );
  }
}

/// Route guard: checks for presence of a valid JWT session at startup.
class AuthGate extends StatefulWidget {
  final AuthService? authService;
  final ThemeService? themeService;
  final LocaleService? localeService;

  const AuthGate({
    super.key,
    this.authService,
    this.themeService,
    this.localeService,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AuthService _authService;
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ??
        AuthService(
          tokenStorage: TokenStorageService(),
        );
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await _authService.initialize();
    if (mounted) {
      setState(() {
        _isChecking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF0F766E)),
              SizedBox(height: 16),
              Text(
                'Vérification de session...',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _authService,
      builder: (context, _) {
        if (_authService.state == AuthState.authenticated) {
          return GatewayDashboardScreen(
            authService: _authService,
            themeService: widget.themeService,
            localeService: widget.localeService,
            onLogout: () async {
              await _authService.logout();
            },
          );
        }

        return LoginScreen(
          authService: _authService,
          onLoginSuccess: () {
            // State change via notifyListeners() automatically switches screen
          },
        );
      },
    );
  }
}
