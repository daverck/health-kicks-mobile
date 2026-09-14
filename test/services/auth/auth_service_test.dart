import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:healthkicks_mobile/services/auth/auth_service.dart';
import 'package:healthkicks_mobile/services/auth/token_storage_service.dart';
import 'token_storage_service_test.dart';

void main() {
  group('AuthService - Flux de connexion et rafraîchissement', () {
    late FakeFlutterSecureStorage fakeStorage;
    late TokenStorageService tokenStorage;

    setUp(() {
      fakeStorage = FakeFlutterSecureStorage();
      tokenStorage = TokenStorageService(storage: fakeStorage);
    });

    test('loginWithCredentials - Succès HTTP 200 sauvegarde les jetons et authentifie', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/v1/auth/login'));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['email'], equals('user@example.com'));
        expect(body['password'], equals('secret123'));

        return http.Response(
          jsonEncode({
            'access_token': 'jwt_access_abc',
            'refresh_token': 'jwt_refresh_xyz',
            'user': {
              'id': 42,
              'email': 'user@example.com',
              'name': 'Jean Dupont',
              'role': 'user',
              'is_active': true,
            },
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

      final success = await authService.loginWithCredentials(
        email: 'user@example.com',
        password: 'secret123',
      );

      expect(success, isTrue);
      expect(authService.state, equals(AuthState.authenticated));
      expect(authService.currentUser?.id, equals(42));
      expect(authService.currentUser?.email, equals('user@example.com'));
      expect(await tokenStorage.getAccessToken(), equals('jwt_access_abc'));
      expect(await tokenStorage.getRefreshToken(), equals('jwt_refresh_xyz'));
    });

    test('loginWithCredentials - Échec HTTP 401 met à jour lastError et reste non-authentifié', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Identifiants invalides'}),
          401,
          headers: {'content-type': 'application/json'},
        );
      });

      final authService = AuthService(
        backendBaseUrl: 'http://127.0.0.1:8000',
        tokenStorage: tokenStorage,
        httpClient: mockClient,
      );

      final success = await authService.loginWithCredentials(
        email: 'wrong@example.com',
        password: 'bad',
      );

      expect(success, isFalse);
      expect(authService.state, equals(AuthState.unauthenticated));
      expect(authService.lastError, contains('Identifiants invalides'));
      expect(await tokenStorage.hasValidToken(), isFalse);
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
