import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/services/auth/token_storage_service.dart';
import 'package:healthkicks_mobile/services/studio/studio_api_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeFlutterSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value != null) {
      _data[key] = value;
    } else {
      _data.remove(key);
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _data[key];
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.clear();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StudioApiService - Déclaration REST des sessions Studio', () {
    late TokenStorageService tokenStorage;
    const testUuid = '11111111-2222-3333-4444-555555555555';

    setUp(() async {
      tokenStorage = TokenStorageService(storage: FakeFlutterSecureStorage());
      await tokenStorage.saveTokens(
        accessToken: 'initial-valid-jwt-token',
        refreshToken: 'valid-refresh-token',
      );
    });

    test('Émet un POST conforme avec Bearer token et retourne true sur code 201', () async {
      late http.Request capturedRequest;
      final mockClient = MockClient((request) async {
        capturedRequest = request;
        if (request.url.path == '/api/v1/studio/sessions' && request.method == 'POST') {
          return http.Response(
            jsonEncode({
              'id': testUuid,
              'device_id': 'HK-2',
              'label': 'test_gait',
              'duration_sec': 5.0,
              'sample_count': 94,
              'created_at': DateTime.now().toUtc().toIso8601String(),
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = StudioApiService(
        backendBaseUrl: 'https://healthkicks.duckdns.org:8443',
        httpClient: mockClient,
        tokenStorage: tokenStorage,
      );

      final result = await service.createStudioSession(
        id: testUuid,
        deviceId: 'HK-2',
        label: 'test_gait',
        durationSec: 5.0,
        sampleCount: 94,
      );

      expect(result, isTrue);
      expect(capturedRequest.url.toString(), equals('https://healthkicks.duckdns.org:8443/api/v1/studio/sessions'));
      expect(capturedRequest.headers['Authorization'], equals('Bearer initial-valid-jwt-token'));
      expect(capturedRequest.headers['Content-Type'], equals('application/json'));

      final payload = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(payload['id'], equals(testUuid));
      expect(payload['device_id'], equals('HK-2'));
      expect(payload['label'], equals('test_gait'));
      expect(payload['duration_sec'], equals(5.0));
      expect(payload['sample_count'], equals(94));
    });

    test('Lève une exception immédiate si aucun jeton d\'accès n\'est présent', () async {
      await tokenStorage.clearTokens();

      final service = StudioApiService(
        backendBaseUrl: 'https://healthkicks.duckdns.org:8443',
        tokenStorage: tokenStorage,
      );

      expect(
        () => service.createStudioSession(
          id: testUuid,
          deviceId: 'HK-2',
          label: 'test_gait',
          durationSec: 5.0,
          sampleCount: 94,
        ),
        throwsA(isA<HttpException>()),
      );
    });

    test('En cas de 401, rafraîchit le token et rejoue la requête avec succès', () async {
      int requestCount = 0;
      final tokensUsed = <String>[];

      final mockClient = MockClient((request) async {
        requestCount++;
        tokensUsed.add(request.headers['Authorization'] ?? '');

        if (requestCount == 1) {
          // Premier appel : token expiré
          return http.Response(jsonEncode({'detail': 'Token expired'}), 401);
        } else {
          // Deuxième appel : token rafraîchi
          return http.Response(
            jsonEncode({'id': testUuid, 'status': 'created'}),
            201,
          );
        }
      });

      bool refreshCalled = false;
      final service = StudioApiService(
        backendBaseUrl: 'https://healthkicks.duckdns.org:8443',
        httpClient: mockClient,
        tokenStorage: tokenStorage,
        refreshTokenFunction: () async {
          refreshCalled = true;
          await tokenStorage.saveTokens(
            accessToken: 'refreshed-jwt-token',
            refreshToken: 'new-refresh-token',
          );
          return true;
        },
      );

      final result = await service.createStudioSession(
        id: testUuid,
        deviceId: 'HK-2',
        label: 'course',
        durationSec: 10.0,
        sampleCount: 200,
      );

      expect(result, isTrue);
      expect(requestCount, equals(2));
      expect(refreshCalled, isTrue);
      expect(tokensUsed[0], equals('Bearer initial-valid-jwt-token'));
      expect(tokensUsed[1], equals('Bearer refreshed-jwt-token'));
    });

    test('En cas d\'échec de rafraîchissement après un 401, lève une HttpException', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'detail': 'Token expired'}), 401);
      });

      final service = StudioApiService(
        backendBaseUrl: 'https://healthkicks.duckdns.org:8443',
        httpClient: mockClient,
        tokenStorage: tokenStorage,
        refreshTokenFunction: () async => false, // Refresh échoue
      );

      expect(
        () => service.createStudioSession(
          id: testUuid,
          deviceId: 'HK-2',
          label: 'course',
          durationSec: 10.0,
          sampleCount: 200,
        ),
        throwsA(isA<HttpException>()),
      );
    });

    test('Lève une HttpException en cas de réponse HTTP 500 du serveur', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final service = StudioApiService(
        backendBaseUrl: 'https://healthkicks.duckdns.org:8443',
        httpClient: mockClient,
        tokenStorage: tokenStorage,
      );

      expect(
        () => service.createStudioSession(
          id: testUuid,
          deviceId: 'HK-2',
          label: 'course',
          durationSec: 10.0,
          sampleCount: 200,
        ),
        throwsA(isA<HttpException>()),
      );
    });
  });
}
