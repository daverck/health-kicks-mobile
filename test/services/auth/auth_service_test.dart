import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:healthkicks_mobile/services/auth/auth_service.dart';
import 'package:healthkicks_mobile/services/auth/token_storage_service.dart';
import 'token_storage_service_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthService - SSO OAuth2 Flow and Deep Links', () {
    late FakeFlutterSecureStorage fakeStorage;
    late TokenStorageService tokenStorage;

    setUp(() {
      fakeStorage = FakeFlutterSecureStorage();
      tokenStorage = TokenStorageService(storage: fakeStorage);
    });

    test('signInWithGoogle - Launches Google OAuth URL with redirect=true and PKCE S256', () async {
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
      expect(
        launchedUri.toString(),
        startsWith('http://127.0.0.1:8000/api/v1/auth/google/login?redirect=true'),
      );
      expect(launchedUri.toString(), contains('code_challenge='));
      expect(launchedUri.toString(), contains('code_challenge_method=S256'));
      expect(authService.pendingCodeVerifier, isNotNull);
      expect(authService.pendingCodeVerifier!.length, equals(64));
      expect(
        launchedUri!.queryParameters['code_challenge'],
        equals(AuthService.computePkceChallenge(authService.pendingCodeVerifier!)),
      );
      expect(launchedMode, equals(LaunchMode.externalApplication));
    });

    test('signInWithGoogle - Cleanly handles trailing slash on https://healthkicks.duckdns.org/', () async {
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
        startsWith('https://healthkicks.duckdns.org/api/v1/auth/google/login?redirect=true'),
      );
      expect(launchedUri.toString(), contains('code_challenge='));
      expect(launchedUri.toString(), contains('code_challenge_method=S256'));
    });

    test('signInWithAzure - Launches Azure OAuth URL with redirect=true and PKCE S256', () async {
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
      expect(
        launchedUri.toString(),
        startsWith('http://127.0.0.1:8000/api/v1/auth/azure/login?redirect=true'),
      );
      expect(launchedUri.toString(), contains('code_challenge='));
      expect(launchedUri.toString(), contains('code_challenge_method=S256'));
      expect(authService.pendingCodeVerifier, isNotNull);
      expect(
        launchedUri!.queryParameters['code_challenge'],
        equals(AuthService.computePkceChallenge(authService.pendingCodeVerifier!)),
      );
      expect(launchedMode, equals(LaunchMode.externalApplication));
    });

    test('signInWithAzure - Cleanly handles trailing slash and explicit backendUrl', () async {
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
        startsWith('https://healthkicks.duckdns.org/api/v1/auth/azure/login?redirect=true'),
      );
      expect(launchedUri.toString(), contains('code_challenge='));
      expect(launchedUri.toString(), contains('code_challenge_method=S256'));
    });

    test('handleDeepLink - Ticket exchange (PKCE S256): exchanges ticket via POST /api/v1/auth/token/exchange', () async {
      Map<String, dynamic>? capturedExchangeBody;

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/token/exchange' && request.method == 'POST') {
          capturedExchangeBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'access_token': 'jwt_pkce_access_123',
              'refresh_token': 'jwt_pkce_refresh_456',
              'token_type': 'bearer',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/v1/auth/me') {
          expect(request.headers['Authorization'], equals('Bearer jwt_pkce_access_123'));
          return http.Response(
            jsonEncode({
              'id': 99,
              'email': 'pkce_user@example.com',
              'name': 'PKCE User',
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
        urlLauncher: (uri, {mode = LaunchMode.platformDefault}) async => true,
      );

      await authService.signInWithGoogle();
      final generatedVerifier = authService.pendingCodeVerifier;
      expect(generatedVerifier, isNotNull);

      final callbackUri = Uri.parse(
        'healthkicks://auth/callback?ticket=one_time_ticket_789&state=csrf_state_token',
      );

      final result = await authService.handleDeepLink(callbackUri);

      expect(result, isTrue);
      expect(capturedExchangeBody, isNotNull);
      expect(capturedExchangeBody!['ticket'], equals('one_time_ticket_789'));
      expect(capturedExchangeBody!['code_verifier'], equals(generatedVerifier));
      expect(authService.pendingCodeVerifier, isNull);
      expect(authService.state, equals(AuthState.authenticated));
      expect(authService.currentUser?.id, equals(99));
      expect(authService.currentUser?.email, equals('pkce_user@example.com'));
      expect(await tokenStorage.getAccessToken(), equals('jwt_pkce_access_123'));
      expect(await tokenStorage.getRefreshToken(), equals('jwt_pkce_refresh_456'));
    });

    test('handleDeepLink - Success: exchanges ticket without user payload, queries /me, and transitions to authenticated', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/token/exchange') {
          return http.Response(
            jsonEncode({
              'access_token': 'jwt_access_abc',
              'refresh_token': 'jwt_refresh_xyz',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
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
        'healthkicks://auth/callback?ticket=valid_ticket_123&state=test_state',
      );

      final result = await authService.handleDeepLink(callbackUri);

      expect(result, isTrue);
      expect(authService.state, equals(AuthState.authenticated));
      expect(authService.currentUser?.id, equals(42));
      expect(authService.currentUser?.email, equals('sso_user@example.com'));
      expect(await tokenStorage.getAccessToken(), equals('jwt_access_abc'));
      expect(await tokenStorage.getRefreshToken(), equals('jwt_refresh_xyz'));
    });

    test('handleDeepLink - Missing ticket: fails with unauthenticated and captures error message', () async {
      final authService = AuthService(
        backendBaseUrl: 'http://127.0.0.1:8000',
        tokenStorage: tokenStorage,
      );

      final callbackUri = Uri.parse(
        'healthkicks://auth/callback?state=no_ticket_present',
      );

      final result = await authService.handleDeepLink(callbackUri);

      expect(result, isFalse);
      expect(authService.state, equals(AuthState.unauthenticated));
      expect(authService.lastError, contains('ticket missing'));
    });

    test('handleDeepLink - OAuth error: captures error message and transitions to unauthenticated', () async {
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

    test('handleDeepLink - Ignores URIs not intended for healthkicks://auth', () async {
      final authService = AuthService(
        backendBaseUrl: 'http://127.0.0.1:8000',
        tokenStorage: tokenStorage,
      );

      final foreignUri = Uri.parse('https://example.com/callback?access_token=123');
      final result = await authService.handleDeepLink(foreignUri);

      expect(result, isFalse);
      expect(authService.state, equals(AuthState.initial));
    });

    test('AuthService - Defaults to AppConfig.backendBaseUrl (port 8443)', () {
      final authService = AuthService(
        tokenStorage: tokenStorage,
      );

      expect(authService.backendBaseUrl, equals('https://healthkicks.duckdns.org:8443'));
    });

    test('logout - Deletes tokens and resets state', () async {
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

    test('refreshCurrentUser - Reloads profile and notifies listeners', () async {
      await tokenStorage.saveTokens(accessToken: 'valid_access_token');
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/v1/auth/me');
        return http.Response(
          jsonEncode({
            'id': 42,
            'email': 'clinician@example.com',
            'role': 'clinician',
            'is_active': true,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final authService = AuthService(
        backendBaseUrl: 'http://127.0.0.1:8000',
        tokenStorage: tokenStorage,
        httpClient: mockClient,
      );
      var notifications = 0;
      authService.addListener(() => notifications++);

      final refreshed = await authService.refreshCurrentUser();

      expect(refreshed, isTrue);
      expect(authService.currentUser?.role, 'clinician');
      expect(notifications, 1);
    });

    test('initialize - Reloads profile after refreshing an expired token', () async {
      await tokenStorage.saveTokens(
        accessToken: 'expired_access_token',
        refreshToken: 'valid_refresh_token',
      );
      var profileRequests = 0;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/me') {
          profileRequests++;
          if (profileRequests == 1) {
            return http.Response('Unauthorized', 401);
          }
          return http.Response(
            jsonEncode({
              'id': 42,
              'email': 'clinician@example.com',
              'role': 'clinician',
              'is_active': true,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path == '/api/v1/auth/refresh') {
          return http.Response(
            jsonEncode({
              'access_token': 'refreshed_access_token',
              'refresh_token': 'refreshed_refresh_token',
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

      final initialized = await authService.initialize();

      expect(initialized, isTrue);
      expect(authService.currentUser?.role, 'clinician');
      expect(profileRequests, 2);
    });

    test('AuthUser - deserializes uuid and pseudonym, and resolves effectiveUserUuid correctly', () {
      final userWithUuid = AuthUser.fromJson({
        'id': 42,
        'uuid': 'c2d1b09e-5e8b-4b8a-9c7f-1d4e5f6a7b8c',
        'pseudonym': 'SUBJ-42A1B2C3',
        'email': 'user@example.com',
        'role': 'user',
        'is_active': true,
      });

      expect(userWithUuid.id, equals(42));
      expect(userWithUuid.uuid, equals('c2d1b09e-5e8b-4b8a-9c7f-1d4e5f6a7b8c'));
      expect(userWithUuid.pseudonym, equals('SUBJ-42A1B2C3'));
      expect(userWithUuid.effectiveUserUuid, equals('c2d1b09e-5e8b-4b8a-9c7f-1d4e5f6a7b8c'));

      final legacyUserWithoutUuid = AuthUser.fromJson({
        'id': 99,
        'email': 'legacy@example.com',
        'role': 'admin',
      });

      expect(legacyUserWithoutUuid.uuid, isNull);
      expect(legacyUserWithoutUuid.pseudonym, isNull);
      expect(legacyUserWithoutUuid.effectiveUserUuid, equals('99'));
    });
  });
}
