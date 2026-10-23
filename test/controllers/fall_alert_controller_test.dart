import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/controllers/fall_alert_controller.dart';
import 'package:healthkicks_mobile/models/activity_detection_model.dart';
import 'package:healthkicks_mobile/models/fall_alert_model.dart';
import 'package:healthkicks_mobile/services/location/fall_location_provider.dart';
import 'package:healthkicks_mobile/services/sms/fall_sms_sender.dart';

class FakeFallSmsSender implements FallSmsSender {
  bool permissionGranted = true;
  bool shouldSucceed = true;
  String? failureErrorMessage = 'SEND_SMS permission not granted';
  final List<Map<String, String>> sentMessages = [];

  @override
  Future<bool> requestSmsPermission() async => permissionGranted;

  @override
  Future<SmsSendResult> sendSms({
    required String phone,
    required String message,
  }) async {
    sentMessages.add({'phone': phone, 'message': message});
    if (shouldSucceed) {
      return const SmsSendResult(success: true);
    }
    return SmsSendResult(
      success: false,
      errorMessage: failureErrorMessage,
    );
  }
}

void main() {
  group('FallAlertController lifecycle & SMS relay', () {
    const mockLocation = FallAlertLocation(
      lat: 50.8466,
      lon: 4.3528,
      accuracyM: 10.0,
      capturedAt: 1792745941000,
    );

    const liveFallDetection = ActivityDetectionModel(
      stateCode: 0x10,
      eventType: 'fall_forward',
      confidencePercent: 91,
      timestampEpochSec: 1792745943,
      isFall: true,
      isHapticTriggered: true,
      isOfflineBuffered: false,
    );

    const offlineBufferedFallDetection = ActivityDetectionModel(
      stateCode: 0x11,
      eventType: 'fall_backward',
      confidencePercent: 88,
      timestampEpochSec: 1792745900,
      isFall: true,
      isHapticTriggered: true,
      isOfflineBuffered: true,
    );

    const fallRecoveryDetection = ActivityDetectionModel(
      stateCode: 0x13,
      eventType: 'fall_recovery',
      confidencePercent: 95,
      timestampEpochSec: 1792745950,
      isFall: false,
      isHapticTriggered: false,
      isOfflineBuffered: false,
    );

    test('Live fall detection enters PENDING, opens screen, and publishes DETECTED (live) with GPS', () async {
      final published = <FallAlertUplinkPayload>[];
      final controller = FallAlertController(
        deviceId: 'HK-1',
        locationProvider: const StaticFallLocationProvider(location: mockLocation),
        isMqttConnectedGetter: () => true,
        onPublishUplink: (payload) async {
          published.add(payload);
          return true;
        },
      );

      await controller.onActivityDetected(liveFallDetection);

      expect(controller.state, equals('PENDING'));
      expect(controller.isAlertScreenVisible, isTrue);
      expect(controller.activeEventId, isNotNull);
      expect(controller.remainingSeconds, equals(60));
      expect(published.length, equals(1));

      final sent = published.first;
      expect(sent.action, equals('DETECTED'));
      expect(sent.delivery, equals('live'));
      expect(sent.deviceId, equals('HK-1'));
      expect(sent.eventType, equals('fall_forward'));
      expect(sent.confidence, closeTo(0.91, 0.001));
      expect(sent.location?.lat, closeTo(50.8466, 0.0001));
      expect(sent.eventId, equals(controller.activeEventId));

      controller.dispose();
    });

    test('Offline buffered fall (NVS bit 2) or disconnected MQTT publishes delivery=replayed without opening screen', () async {
      final published = <FallAlertUplinkPayload>[];
      var mqttOnline = true;
      final controller = FallAlertController(
        deviceId: 'HK-1',
        locationProvider: const StaticFallLocationProvider(location: mockLocation),
        isMqttConnectedGetter: () => mqttOnline,
        onPublishUplink: (payload) async {
          published.add(payload);
          return true;
        },
      );

      // 1. Offline-buffered NVS flag = true while MQTT is online
      await controller.onActivityDetected(offlineBufferedFallDetection);
      expect(controller.isAlertScreenVisible, isFalse);
      expect(published.length, equals(1));
      expect(published.first.action, equals('DETECTED'));
      expect(published.first.delivery, equals('replayed'));

      // 2. Live fall while MQTT is disconnected -> queued and flushed when MQTT reconnects
      mqttOnline = false;
      await controller.onActivityDetected(liveFallDetection);
      expect(controller.isAlertScreenVisible, isFalse);
      expect(controller.pendingReplayedPayloads.length, equals(1));
      expect(controller.pendingReplayedPayloads.first.delivery, equals('replayed'));

      mqttOnline = true;
      await controller.flushPendingReplayedPayloads();
      expect(controller.pendingReplayedPayloads, isEmpty);
      expect(published.length, equals(2));
      expect(published.last.delivery, equals('replayed'));

      controller.dispose();
    });

    test('User cancellation publishes CANCEL with user_cancel and closes screen', () async {
      final published = <FallAlertUplinkPayload>[];
      final controller = FallAlertController(
        deviceId: 'HK-1',
        locationProvider: const StaticFallLocationProvider(location: mockLocation),
        isMqttConnectedGetter: () => true,
        onPublishUplink: (payload) async {
          published.add(payload);
          return true;
        },
      );

      await controller.onActivityDetected(liveFallDetection);
      final eventId = controller.activeEventId!;
      expect(controller.isAlertScreenVisible, isTrue);

      await controller.cancelByUser();

      expect(controller.state, equals('CANCELLED'));
      expect(controller.isAlertScreenVisible, isFalse);
      expect(controller.activeEventId, isNull);
      expect(published.length, equals(2));
      expect(published.last.action, equals('CANCEL'));
      expect(published.last.cancelReason, equals('user_cancel'));
      expect(published.last.eventId, equals(eventId));

      controller.dispose();
    });

    test('Automatic cancellation on BLE fall_recovery (0x13) publishes CANCEL with fall_recovery and closes screen', () async {
      final published = <FallAlertUplinkPayload>[];
      final controller = FallAlertController(
        deviceId: 'HK-1',
        locationProvider: const StaticFallLocationProvider(location: mockLocation),
        isMqttConnectedGetter: () => true,
        onPublishUplink: (payload) async {
          published.add(payload);
          return true;
        },
      );

      await controller.onActivityDetected(liveFallDetection);
      final eventId = controller.activeEventId!;
      expect(controller.isAlertScreenVisible, isTrue);

      await controller.onActivityDetected(fallRecoveryDetection);

      expect(controller.state, equals('CANCELLED'));
      expect(controller.isAlertScreenVisible, isFalse);
      expect(controller.activeEventId, isNull);
      expect(published.length, equals(2));
      expect(published.last.action, equals('CANCEL'));
      expect(published.last.cancelReason, equals('fall_recovery'));
      expect(published.last.eventId, equals(eventId));

      controller.dispose();
    });

    test('Immediate confirmation (CONFIRM) transitions to ESCALATING, and downlink updates ESCALATING -> ACKNOWLEDGED -> EXHAUSTED', () async {
      final published = <FallAlertUplinkPayload>[];
      var call112Invoked = false;
      final controller = FallAlertController(
        deviceId: 'HK-1',
        locationProvider: const StaticFallLocationProvider(location: mockLocation),
        isMqttConnectedGetter: () => true,
        onPublishUplink: (payload) async {
          published.add(payload);
          return true;
        },
        onCall112: () async {
          call112Invoked = true;
        },
      );

      await controller.onActivityDetected(liveFallDetection);
      final eventId = controller.activeEventId!;

      // User presses "J'ai besoin d'aide maintenant"
      await controller.confirmEmergencyNow();
      expect(controller.state, equals('ESCALATING'));
      expect(controller.isConfirmSent, isTrue);
      expect(published.length, equals(2));
      expect(published.last.action, equals('CONFIRM'));
      expect(published.last.eventId, equals(eventId));

      // Downlink ESCALATING rank 1 / 3
      controller.onDownlinkStatusReceived(FallAlertStatusModel(
        eventId: eventId,
        alertId: 42,
        state: 'ESCALATING',
        currentContactRank: 1,
        contactsTotal: 3,
      ));
      expect(controller.state, equals('ESCALATING'));
      expect(controller.currentContactRank, equals(1));
      expect(controller.contactsTotal, equals(3));
      expect(controller.isAlertScreenVisible, isTrue);

      // Downlink ACKNOWLEDGED by Marie
      controller.onDownlinkStatusReceived(FallAlertStatusModel(
        eventId: eventId,
        alertId: 42,
        state: 'ACKNOWLEDGED',
        currentContactRank: 1,
        contactsTotal: 3,
        acknowledgedBy: const FallAlertAcknowledgedBy(firstName: 'Marie', lastName: 'Dupont'),
      ));
      expect(controller.state, equals('ACKNOWLEDGED'));
      expect(controller.acknowledgedByName, equals('Marie'));
      expect(controller.isAlertScreenVisible, isTrue);

      // Downlink EXHAUSTED -> 112 fallback
      controller.onDownlinkStatusReceived(FallAlertStatusModel(
        eventId: eventId,
        alertId: 42,
        state: 'EXHAUSTED',
        currentContactRank: 3,
        contactsTotal: 3,
      ));
      expect(controller.state, equals('EXHAUSTED'));
      expect(controller.isAlertScreenVisible, isTrue);

      await controller.callEmergency112();
      expect(call112Invoked, isTrue);

      controller.dispose();
    });

    test('Downlink ESCALATING with sms_command sends SMS, publishes SMS_STATUS (SENT / FAILED), and deduplicates notification_id', () async {
      final published = <FallAlertUplinkPayload>[];
      final fakeSms = FakeFallSmsSender();
      final controller = FallAlertController(
        deviceId: 'HK-1',
        locationProvider: const StaticFallLocationProvider(location: mockLocation),
        smsSender: fakeSms,
        isMqttConnectedGetter: () => true,
        onPublishUplink: (payload) async {
          published.add(payload);
          return true;
        },
      );

      await controller.onActivityDetected(liveFallDetection);
      final eventId = controller.activeEventId!;
      expect(published.length, equals(1)); // DETECTED

      final escalatingWithSms = FallAlertStatusModel(
        eventId: eventId,
        alertId: 42,
        state: 'ESCALATING',
        currentContactRank: 1,
        contactsTotal: 2,
        smsCommand: const FallAlertSmsCommand(
          notificationId: 102,
          contactId: 7,
          contactFirstName: 'Marie',
          recipientPhone: '+32470123456',
          message: '[HealthKicks URGENCE] Chute détectée.',
          isTest: false,
        ),
      );

      controller.onDownlinkStatusReceived(escalatingWithSms);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(fakeSms.sentMessages.length, equals(1));
      expect(fakeSms.sentMessages.first['phone'], equals('+32470123456'));
      expect(published.length, equals(2));
      expect(published.last.action, equals('SMS_STATUS'));
      expect(published.last.notificationId, equals(102));
      expect(published.last.smsStatus, equals('SENT'));
      expect(published.last.errorMessage, isNull);

      // Duplicate downlink with same notification_id = 102 is ignored
      controller.onDownlinkStatusReceived(escalatingWithSms);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fakeSms.sentMessages.length, equals(1));
      expect(published.length, equals(2));

      // Second contact (notification_id = 105) where SMS fails -> publishes SMS_STATUS FAILED
      fakeSms.shouldSucceed = false;
      fakeSms.failureErrorMessage = 'Modem error';
      controller.onDownlinkStatusReceived(FallAlertStatusModel(
        eventId: eventId,
        alertId: 42,
        state: 'ESCALATING',
        currentContactRank: 2,
        contactsTotal: 2,
        smsCommand: const FallAlertSmsCommand(
          notificationId: 105,
          contactId: 8,
          contactFirstName: 'Paul',
          recipientPhone: '+32470999888',
          message: '[HealthKicks URGENCE] Chute détectée.',
          isTest: false,
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(fakeSms.sentMessages.length, equals(2));
      expect(published.length, equals(3));
      expect(published.last.action, equals('SMS_STATUS'));
      expect(published.last.notificationId, equals(105));
      expect(published.last.smsStatus, equals('FAILED'));
      expect(published.last.errorMessage, equals('Modem error'));

      controller.dispose();
    });

    test('Downlink TEST_SMS sends test SMS without opening alert screen or modifying state', () async {
      final published = <FallAlertUplinkPayload>[];
      final fakeSms = FakeFallSmsSender();
      final controller = FallAlertController(
        deviceId: 'HK-1',
        locationProvider: const StaticFallLocationProvider(location: mockLocation),
        smsSender: fakeSms,
        isMqttConnectedGetter: () => true,
        onPublishUplink: (payload) async {
          published.add(payload);
          return true;
        },
      );

      controller.onDownlinkStatusReceived(const FallAlertStatusModel(
        eventId: 'test-sms-uuid-1',
        state: 'TEST_SMS',
        smsCommand: FallAlertSmsCommand(
          contactId: 7,
          contactFirstName: 'Marie',
          recipientPhone: '+32470123456',
          message: '[HealthKicks TEST] SMS de vérification.',
          isTest: true,
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.isAlertScreenVisible, isFalse);
      expect(controller.state, isNull);
      expect(controller.activeEventId, isNull);
      expect(fakeSms.sentMessages.length, equals(1));
      expect(fakeSms.sentMessages.first['phone'], equals('+32470123456'));
      expect(published, isEmpty);

      controller.dispose();
    });
  });
}
