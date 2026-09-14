import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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

    test('IoTCredentials - Désérialisation et évaluation isExpired', () {
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

      // Vérifie la marge de 5 minutes : si expiration dans 3 minutes, isExpired doit être true
      final soonExpiringCreds = IoTCredentials(
        accessKeyId: 'K',
        secretAccessKey: 'S',
        sessionToken: 'T',
        expiration: DateTime.now().toUtc().add(const Duration(minutes: 3)),
        iotEndpoint: 'ep',
        region: 'eu-north-1',
      );
      expect(soonExpiringCreds.isExpired, isTrue);
    });

    test('fetchCredentials - Récupère les credentials via HTTP POST et les met en cache', () async {
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

      // Premier appel : doit émettre une requête HTTP
      final creds1 = await repo.fetchCredentials(deviceId: 'HK-1');
      expect(creds1.accessKeyId, equals('ASIA_TEST_ACCESS_KEY'));
      expect(requestCount, equals(1));

      // Second appel immédiat avec même deviceId : doit utiliser le cache
      final creds2 = await repo.fetchCredentials(deviceId: 'HK-1');
      expect(creds2.accessKeyId, equals('ASIA_TEST_ACCESS_KEY'));
      expect(requestCount, equals(1)); // Pas de nouvelle requête HTTP

      // Troisième appel avec forceRefresh = true : doit réémettre la requête HTTP
      await repo.fetchCredentials(deviceId: 'HK-1', forceRefresh: true);
      expect(requestCount, equals(2));

      // Quatrième appel avec changement de deviceId : doit rafraîchir le cache
      await repo.fetchCredentials(deviceId: 'HK-2');
      expect(requestCount, equals(3));
    });

    test('fetchCredentials - Lève une exception si l\'API backend répond en erreur 401', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'detail': 'Unauthorized'}), 401);
      });

      final repo = IotCredentialsRepository(
        backendBaseUrl: 'http://192.168.1.100:8000',
        httpClient: mockClient,
      );

      expect(
        () => repo.fetchCredentials(deviceId: 'HK-1'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
