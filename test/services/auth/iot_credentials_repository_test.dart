import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:healthkicks_mobile/services/auth/auth_service.dart';
import 'package:healthkicks_mobile/services/auth/iot_credentials_model.dart';
import 'package:healthkicks_mobile/services/auth/iot_credentials_repository.dart';

void main() {
  group('IotCredentialsRepository & IoTCredentials Model', () {
    const validJson = {
      'access_key_id': 'ASIA_TEST_ACCESS_KEY',
      'secret_access_key': 'test_secret_key_123',
      'session_token': 'test_session_token_xyz',
      'expiration': '2099-01-01T00:00:00Z',
      'iot_endpoint': 'a2k10w7ebf2tx9-ats.iot.eu-north-1.amazonaws.com',
      'region': 'eu-north-1',
    };

    test('IoTCredentials - Deserialization and isExpired evaluation', () {
      final creds = IoTCredentials.fromJson(validJson);
      expect(creds.accessKeyId, equals('ASIA_TEST_ACCESS_KEY'));
      expect(creds.secretAccessKey, equals('test_secret_key_123'));
      expect(creds.sessionToken, equals('test_session_token_xyz'));
      expect(creds.iotEndpoint, equals('a2k10w7ebf2tx9-ats.iot.eu-north-1.amazonaws.com'));
      expect(creds.region, equals('eu-north-1'));
      expect(creds.isExpired, isFalse);

      final expiredCreds = IoTCredentials(
        accessKeyId: 'K',
        secretAccessKey: 'S',
        sessionToken: 'T',
        expiration: DateTime.now().toUtc().subtract(const Duration(minutes: 10)),
        iotEndpoint: 'ep',
        region: 'eu-north-1',
      );
      expect(expiredCreds.isExpired, isTrue);

      // Verify 5-minute margin: if expiring in 3 minutes, isExpired must be true
      final soonExpiringCreds = IoTCredentials(
        accessKeyId: 'K',
        secretAccessKey: 'S',
        sessionToken: 'T',
        expiration: DateTime.now().toUtc().add(const Duration(minutes: 3)),
        iotEndpoint: 'ep',
        region: 'eu-north-1',
      );
      expect(soonExpiringCreds.isExpired, isTrue);

      final credsWithUser = IoTCredentials.fromJson({
        ...validJson,
        'user_id': '42',
      });
      expect(credsWithUser.userId, equals('42'));
      expect(credsWithUser.toJson()['user_id'], equals('42'));
    });

    test('fetchCredentials - Fetches credentials via HTTP POST and caches them', () async {
      int requestCount = 0;

      final mockClient = MockClient((request) async {
        requestCount++;
        expect(request.url.path, equals('/api/v1/auth/iot-credentials'));
        expect(request.headers['Authorization'], equals('Bearer mock_jwt_token'));
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (requestCount <= 2) {
          expect(body['device_id'], equals('HK-1'));
        } else {
          expect(body['device_id'], equals('HK-2'));
        }

        return http.Response(jsonEncode(validJson), 200, headers: {
          'content-type': 'application/json',
        });
      });

      final repo = IotCredentialsRepository(
        backendBaseUrl: 'http://192.168.1.100:8000',
        httpClient: mockClient,
        authTokenProvider: () => 'mock_jwt_token',
      );

      // First call: must send an HTTP request
      final creds1 = await repo.fetchCredentials(deviceId: 'HK-1');
      expect(creds1.accessKeyId, equals('ASIA_TEST_ACCESS_KEY'));
      expect(requestCount, equals(1));

      // Second immediate call with same deviceId: must use cache
      final creds2 = await repo.fetchCredentials(deviceId: 'HK-1');
      expect(creds2.accessKeyId, equals('ASIA_TEST_ACCESS_KEY'));
      expect(requestCount, equals(1)); // No new HTTP request

      // Third call with forceRefresh = true: must resend HTTP request
      await repo.fetchCredentials(deviceId: 'HK-1', forceRefresh: true);
      expect(requestCount, equals(2));

      // Fourth call with changed deviceId: must refresh cache
      await repo.fetchCredentials(deviceId: 'HK-2');
      expect(requestCount, equals(3));
    });

    test('fetchCredentials - Throws an exception if backend API returns 401 error', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'detail': 'Unauthorized'}), 401);
      });

      final repo = IotCredentialsRepository(
        backendBaseUrl: 'http://192.168.1.100:8000',
        httpClient: mockClient,
        authTokenProvider: () => 'valid_token',
      );

      expect(
        () => repo.fetchCredentials(deviceId: 'HK-1'),
        throwsA(isA<Exception>()),
      );
    });

    test('fetchCredentials - Throws clear exception if no token is available', () async {
      final repo = IotCredentialsRepository(
        backendBaseUrl: 'http://192.168.1.100:8000',
      );

      expect(
        () => repo.fetchCredentials(deviceId: 'HK-1'),
        throwsA(isA<Exception>()),
      );
    });

    test('fetchCredentials - On 401, attempts refreshToken then replays successfully', () async {
      int requestCount = 0;
      final mockClient = MockClient((request) async {
        requestCount++;
        if (requestCount == 1) {
          expect(request.headers['Authorization'], equals('Bearer old_token'));
          return http.Response(jsonEncode({'detail': 'token expired'}), 401);
        } else {
          expect(request.headers['Authorization'], equals('Bearer new_token'));
          return http.Response(jsonEncode(validJson), 200, headers: {
            'content-type': 'application/json',
          });
        }
      });

      final fakeAuth = FakeAuthServiceForRepoTest(shouldSucceedRefresh: true);
      String currentToken = 'old_token';

      final repo = IotCredentialsRepository(
        backendBaseUrl: 'http://192.168.1.100:8000',
        httpClient: mockClient,
        authService: fakeAuth,
        authTokenProvider: () => currentToken,
      );

      fakeAuth.onRefreshHook = () {
        currentToken = 'new_token';
      };

      final creds = await repo.fetchCredentials(deviceId: 'HK-1');
      expect(creds.accessKeyId, equals('ASIA_TEST_ACCESS_KEY'));
      expect(fakeAuth.refreshTokenCalled, isTrue);
      expect(fakeAuth.logoutCalled, isFalse);
      expect(requestCount, equals(2));
    });

    test('fetchCredentials - On 401 with failed refreshToken, calls authService.logout() for SSO return', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'detail': 'token expired'}), 401);
      });

      final fakeAuth = FakeAuthServiceForRepoTest(shouldSucceedRefresh: false);

      final repo = IotCredentialsRepository(
        backendBaseUrl: 'http://192.168.1.100:8000',
        httpClient: mockClient,
        authService: fakeAuth,
        authTokenProvider: () => 'expired_token',
      );

      expect(
        () => repo.fetchCredentials(deviceId: 'HK-1'),
        throwsA(isA<Exception>()),
      );

      // Let async cycle complete
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fakeAuth.refreshTokenCalled, isTrue);
      expect(fakeAuth.logoutCalled, isTrue);
    });
  });
}

class FakeAuthServiceForRepoTest extends AuthService {
  bool refreshTokenCalled = false;
  bool logoutCalled = false;
  bool shouldSucceedRefresh = false;
  void Function()? onRefreshHook;

  FakeAuthServiceForRepoTest({this.shouldSucceedRefresh = false});

  @override
  Future<bool> refreshToken() async {
    refreshTokenCalled = true;
    onRefreshHook?.call();
    return shouldSucceedRefresh;
  }

  @override
  Future<void> logout() async {
    logoutCalled = true;
  }
}

