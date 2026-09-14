import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:healthkicks_mobile/services/auth/auth_service.dart';
import 'package:healthkicks_mobile/services/auth/token_storage_service.dart';
import 'token_storage_service_test.dart';

void main() {
  group('AuthService - Flux SSO OAuth2 et Deep Links', () {
    late FakeFlutterSecureStorage fakeStorage;
    late TokenStorageService tokenStorage;

    setUp(() {
      fakeStorage = FakeFlutterSecureStorage();
      tokenStorage = TokenStorageService(storage: fakeStorage);
    });

    test('signInWithGoogle - Lance l\'URL OAuth Google avec redirect=true', () async {
      Uri? launchedUri;
      LaunchMode? launchedMode;

      final authService = AuthService(
        backendBaseUrl: 'http://127.0.0.1:8000',
        tokenStorage: tokenStorage,
        urlLauncher: (uri, {mode = LaunchMode.platformDefault}) async {
          launchedUri = uri;
          launchedMode = mode;
          return true;
        },
      );

      final success = await authService.signInWithGoogle();

      expect(success, isTrue);
      expect(launchedUri, isNotNull);
      expect(launchedUri.toString(), equals('http://127.0.0.1:8000/api/v1/auth/google/login?redirect=true'));
      expect(launchedMode, equals(LaunchMode.externalApplication));
    });

    test('signInWithGoogle - Gère proprement le slash final sur https://healthkicks.duckdns.org/', () async {
      Uri? launchedUri;

      final authService = AuthService(
        backendBaseUrl: 'https://healthkicks.duckdns.org/',
        tokenStorage: tokenStorage,
        urlLauncher: (uri, {mode = LaunchMode.platformDefault}) async {
          launchedUri = uri;
          return true;
        },
      );

      final success = await authService.signInWithGoogle();

      expect(success, isTrue);
      expect(launchedUri, isNotNull);
      expect(
        launchedUri.toString(),
        equals('https://healthkicks.duckdns.org/api/v1/auth/google/login?redirect=true'),
      );
    });

    test('signInWithAzure - Lance l\'URL OAuth Azure avec redirect=true', () async {
      Uri? launchedUri;
      LaunchMode? launchedMode;

      final authService = AuthService(
        backendBaseUrl: 'http://127.0.0.1:8000',
        tokenStorage: tokenStorage,
        urlLauncher: (uri, {mode = LaunchMode.platformDefault}) async {
          launchedUri = uri;
          launchedMode = mode;
          return true;
        },
      );

      final success = await authService.signInWithAzure();

      expect(success, isTrue);
      expect(launchedUri, isNotNull);
      expect(launchedUri.toString(), equals('http://127.0.0.1:8000/api/v1/auth/azure/login?redirect=true'));
      expect(launchedMode, equals(LaunchMode.externalApplication));
    });

    test('signInWithAzure - Gère proprement le slash final et backendUrl explicite', () async {
      Uri? launchedUri;

      final authService = AuthService(
        backendBaseUrl: 'https://healthkicks.duckdns.org',
        tokenStorage: tokenStorage,
        urlLauncher: (uri, {mode = LaunchMode.platformDefault}) async {
          launchedUri = uri;
          return true;
        },
      );

      final success = await authService.signInWithAzure(backendUrl: 'https://healthkicks.duckdns.org/');

      expect(success, isTrue);
      expect(launchedUri, isNotNull);
      expect(
        launchedUri.toString(),
        equals('https://healthkicks.duckdns.org/api/v1/auth/azure/login?redirect=true'),
      );
    });

    test('handleDeepLink - Succès : extrait les tokens, interroge /me et passe en authenticated', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/me') {
          expect(request.headers['Authorization'], equals('Bearer jwt_access_abc'));
          return http.Response(
            jsonEncode({
              'id': 42,
              'email': 'sso_user@example.com',
              'name': 'SSO User',
              'role': 'user',
              'is_active': true,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final authService = AuthService(
        backendBaseUrl: 'http://127.0.0.1:8000',
        tokenStorage: tokenStorage,
        httpClient: mockClient,
      );

      final callbackUri = Uri.parse(
        'healthkicks://auth/callback?access_token=jwt_access_abc&refresh_token=jwt_refresh_xyz',
      );

      final result = await authService.handleDeepLink(callbackUri);

      expect(result, isTrue);
      expect(authService.state, equals(AuthState.authenticated));
      expect(authService.currentUser?.id, equals(42));
      expect(authService.currentUser?.email, equals('sso_user@example.com'));
      expect(await tokenStorage.getAccessToken(), equals('jwt_access_abc'));
      expect(await tokenStorage.getRefreshToken(), equals('jwt_refresh_xyz'));
    });

    test('handleDeepLink - Erreur OAuth : capture le message d\'erreur et passe en unauthenticated', () async {
      final authService = AuthService(
        backendBaseUrl: 'http://127.0.0.1:8000',
        tokenStorage: tokenStorage,
      );

      final callbackUri = Uri.parse(
        'healthkicks://auth/callback?error=access_denied&error_description=Utilisateur+a+refuse',
      );

      final result = await authService.handleDeepLink(callbackUri);

      expect(result, isFalse);
      expect(authService.state, equals(AuthState.unauthenticated));
      expect(authService.lastError, contains('Utilisateur a refuse'));
      expect(await tokenStorage.hasValidToken(), isFalse);
    });

    test('handleDeepLink - Ignore les URIs non destinées à healthkicks://auth', () async {
      final authService = AuthService(
        backendBaseUrl: 'http://127.0.0.1:8000',
        tokenStorage: tokenStorage,
      );

      final foreignUri = Uri.parse('https://example.com/callback?access_token=123');
      final result = await authService.handleDeepLink(foreignUri);

      expect(result, isFalse);
      expect(authService.state, equals(AuthState.initial));
    });

    test('logout - Supprime les jetons et réinitialise l\'état', () async {
      await tokenStorage.saveTokens(accessToken: 'token_to_clear');
      final authService = AuthService(
        backendBaseUrl: 'http://127.0.0.1:8000',
        tokenStorage: tokenStorage,
      );

      await authService.logout();

      expect(authService.state, equals(AuthState.unauthenticated));
      expect(authService.currentUser, isNull);
      expect(await tokenStorage.hasValidToken(), isFalse);
    });
  });
}


