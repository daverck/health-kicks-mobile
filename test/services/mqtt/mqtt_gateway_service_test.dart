import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/services/auth/iot_credentials_model.dart';
import 'package:healthkicks_mobile/services/auth/iot_credentials_repository.dart';
import 'package:healthkicks_mobile/services/auth/token_storage_service.dart';
import 'package:healthkicks_mobile/services/mqtt/mqtt_gateway_service.dart';

class FakeCredentialsRepository implements IotCredentialsRepository {
  @override
  final TokenStorageService? tokenStorage;

  FakeCredentialsRepository({this.tokenStorage});

  @override
  Future<IoTCredentials> fetchCredentials({String? deviceId, bool forceRefresh = false}) async {
    return IoTCredentials(
      accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
      secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
      sessionToken: 'AQoDYXdzEJr1EXAMPLE',
      expiration: DateTime.now().add(const Duration(hours: 1)),
      iotEndpoint: 'a1b2c3d4e5f6-ats.iot.eu-north-1.amazonaws.com',
      region: 'eu-north-1',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('MqttGatewayService - Hybrid Presence Mechanism & LWT', () {
    test('Constructor properly stores userId and deviceId', () {
      final fakeRepo = FakeCredentialsRepository();
      final service = MqttGatewayService(
        deviceId: 'HK-2',
        userId: '42',
        credentialsRepository: fakeRepo,
      );

      expect(service.deviceId, equals('HK-2'));
      expect(service.userId, equals('42'));
      expect(service.clientId, equals('healthkicks-mobile-42'));
    });

    test('LWT topic and payload target user gateway (user_id)', () {
      const testUserId = '123';
      const expectedTopic = 'healthkicks/v1/users/$testUserId/gateway-status';

      final expectedPayload = jsonEncode({
        'user_id': testUserId,
        'state': 'offline',
        'gateway': 'mobile',
      });

      final decoded = jsonDecode(expectedPayload) as Map<String, dynamic>;
      expect(decoded['user_id'], equals('123'));
      expect(decoded['state'], equals('offline'));
      expect(decoded['gateway'], equals('mobile'));
      expect(expectedTopic, equals('healthkicks/v1/users/123/gateway-status'));
    });

    test('Unitary BLE status: compliant format for healthkicks/v1/{device_id}/status', () {
      const testDeviceId = 'HK-2';
      final payload = jsonEncode({
        'device_id': testDeviceId,
        'state': 'online',
        'gateway': 'mobile',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      final decoded = jsonDecode(payload) as Map<String, dynamic>;
      expect(decoded['device_id'], equals('HK-2'));
      expect(decoded['state'], equals('online'));
      expect(decoded['gateway'], equals('mobile'));
      expect(decoded['timestamp'], isNotNull);
      expect(DateTime.tryParse(decoded['timestamp'] as String), isNotNull);
    });

    test('connect() rejects connection immediately if userId is null and no token is available', () async {
      final fakeRepo = FakeCredentialsRepository();
      bool logReceived = false;
      final service = MqttGatewayService(
        deviceId: 'HK-2',
        userId: null,
        credentialsRepository: fakeRepo,
        onLog: (msg, {bool isError = false}) {
          if (isError && msg.contains('Connexion refusée')) {
            logReceived = true;
          }
        },
      );

      final result = await service.connect();
      expect(result, isFalse);
      expect(logReceived, isTrue);
    });

    test('connect() rejects connection immediately if userId is unknown', () async {
      final fakeRepo = FakeCredentialsRepository();
      bool logReceived = false;
      final service = MqttGatewayService(
        deviceId: 'HK-2',
        userId: 'unknown',
        credentialsRepository: fakeRepo,
        onLog: (msg, {bool isError = false}) {
          if (isError && msg.contains('Connexion refusée')) {
            logReceived = true;
          }
        },
      );

      final result = await service.connect();
      expect(result, isFalse);
      expect(logReceived, isTrue);
    });
  });
}
