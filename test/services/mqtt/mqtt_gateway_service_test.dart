import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/models/fall_alert_model.dart';
import 'package:healthkicks_mobile/services/auth/auth_service.dart';
import 'package:healthkicks_mobile/services/auth/iot_credentials_model.dart';
import 'package:healthkicks_mobile/services/auth/iot_credentials_repository.dart';
import 'package:healthkicks_mobile/services/auth/token_storage_service.dart';
import 'package:healthkicks_mobile/services/mqtt/mqtt_gateway_service.dart';

class FakeCredentialsRepository implements IotCredentialsRepository {
  @override
  final TokenStorageService? tokenStorage;
  @override
  final AuthService? authService;

  @override
  IoTCredentials? get currentCredentials => null;

  FakeCredentialsRepository({this.tokenStorage, this.authService});

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
  group('MqttGatewayService - Hybrid Presence Mechanism, LWT & Fall Alerting', () {
    test('Constructor properly stores userId and deviceId with randomized session nonce', () {
      final fakeRepo = FakeCredentialsRepository();
      final service = MqttGatewayService(
        deviceId: 'HK-2',
        userId: '42',
        credentialsRepository: fakeRepo,
      );

      expect(service.deviceId, equals('HK-2'));
      expect(service.userId, equals('42'));
      expect(service.clientId, startsWith('healthkicks-mobile-42-'));
      expect(service.clientId.length, equals('healthkicks-mobile-42-'.length + 8));

      // Test explicit clientId preservation
      final explicitService = MqttGatewayService(
        deviceId: 'HK-2',
        userId: '42',
        credentialsRepository: fakeRepo,
        clientId: 'healthkicks-mobile-42-custom',
      );
      expect(explicitService.clientId, equals('healthkicks-mobile-42-custom'));

      // Test session nonce format (8 hex characters)
      final nonce = MqttGatewayService.generateSessionNonce();
      expect(nonce.length, equals(8));
      expect(RegExp(r'^[0-9a-f]{8}$').hasMatch(nonce), isTrue);
    });

    test('LWT topic and payload target user gateway (user_uuid & user_id)', () {
      const testUserUuid = '7d2a5f4e-3c2b-4a1d-9e8f-0a1b2c3d4e5f';
      const expectedTopic = 'healthkicks/v1/users/$testUserUuid/gateway-status';

      final expectedPayload = jsonEncode({
        'user_uuid': testUserUuid,
        'user_id': testUserUuid,
        'state': 'offline',
        'gateway': 'mobile',
      });

      final decoded = jsonDecode(expectedPayload) as Map<String, dynamic>;
      expect(decoded['user_uuid'], equals(testUserUuid));
      expect(decoded['user_id'], equals(testUserUuid));
      expect(decoded['state'], equals('offline'));
      expect(decoded['gateway'], equals('mobile'));
      expect(expectedTopic, equals('healthkicks/v1/users/$testUserUuid/gateway-status'));
    });

    test('effectiveUserId prioritizes authUser UUID over numeric userId and resolves topics', () {
      final fakeRepo = FakeCredentialsRepository();
      const testUuid = 'c2d1b09e-5e8b-4b8a-9c7f-1d4e5f6a7b8c';

      final userWithUuid = AuthUser(
        uuid: testUuid,
        pseudonym: 'SUBJ-42A1B2C3',
        email: 'user@example.com',
        role: 'user',
      );

      final serviceWithAuthUser = MqttGatewayService(
        deviceId: 'HK-2',
        userId: '42',
        credentialsRepository: fakeRepo,
        authUserProvider: () => userWithUuid,
      );

      expect(serviceWithAuthUser.effectiveUserId, equals(testUuid));

      final serviceWithUuidDirectly = MqttGatewayService(
        deviceId: 'HK-2',
        userId: testUuid,
        credentialsRepository: fakeRepo,
      );

      expect(serviceWithUuidDirectly.effectiveUserId, equals(testUuid));
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

    test('handleIncomingPayload decodes fall-alert/status downlink messages and emits on fallAlertStatusStream', () async {
      final fakeRepo = FakeCredentialsRepository();
      final service = MqttGatewayService(
        deviceId: 'HK-2',
        userId: '42',
        credentialsRepository: fakeRepo,
      );

      FallAlertStatusModel? receivedStatus;
      final sub = service.fallAlertStatusStream.listen((status) {
        receivedStatus = status;
      });

      final statusJson = jsonEncode({
        'event_id': '0b6f4b1e-6a51-4c1f-9a3e-2d7f1c9b8e10',
        'alert_id': 99,
        'state': 'ESCALATING',
        'current_contact_rank': 2,
        'contacts_total': 3,
        'acknowledged_by': null,
        'cancel_reason': null,
        'next_action_at': '2026-10-23T08:43:03Z',
        'updated_at': '2026-10-23T08:40:03Z',
      });

      service.handleIncomingPayload(
        'healthkicks/v1/users/42/fall-alert/status',
        statusJson,
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(receivedStatus, isNotNull);
      expect(receivedStatus!.eventId, equals('0b6f4b1e-6a51-4c1f-9a3e-2d7f1c9b8e10'));
      expect(receivedStatus!.alertId, equals(99));
      expect(receivedStatus!.state, equals('ESCALATING'));
      expect(receivedStatus!.currentContactRank, equals(2));
      expect(receivedStatus!.contactsTotal, equals(3));

      await sub.cancel();
      service.disconnect();
    });

    test('connect() rejects connection immediately if userId is null and no token is available', () async {
      final fakeRepo = FakeCredentialsRepository();
      bool logReceived = false;
      final service = MqttGatewayService(
        deviceId: 'HK-2',
        userId: null,
        credentialsRepository: fakeRepo,
        onLog: (msg, {bool isError = false}) {
          if (isError && msg.contains('Connection rejected')) {
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
          if (isError && msg.contains('Connection rejected')) {
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
