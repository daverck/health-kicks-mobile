import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/controllers/fall_alert_controller.dart';
import 'package:healthkicks_mobile/models/activity_detection_model.dart';
import 'package:healthkicks_mobile/models/fall_alert_model.dart';
import 'package:healthkicks_mobile/services/location/fall_location_provider.dart';

void main() {
  group('FallAlertController lifecycle', () {
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
  });
}
