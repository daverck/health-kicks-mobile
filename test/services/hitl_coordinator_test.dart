import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/models/activity_detection_model.dart';
import 'package:healthkicks_mobile/models/imu_reading_model.dart';
import 'package:healthkicks_mobile/models/studio_session_model.dart';
import 'package:healthkicks_mobile/services/hitl/hitl_coordinator.dart';
import 'package:healthkicks_mobile/services/mqtt/mqtt_gateway_service.dart';

class FakeMqttGatewayService implements MqttGatewayService {
  final List<StudioSessionModel> publishedSessions = [];

  @override
  Future<void> publishStudioSession(StudioSessionModel session) async {
    publishedSessions.add(session);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('HitlCoordinator', () {
    late HitlCoordinator coordinator;

    setUp(() {
      coordinator = HitlCoordinator();
    });

    test('activates and clears FIFO buffer on deactivation', () async {
      expect(coordinator.isHitlActive, isFalse);

      await coordinator.setHitlActive(true);
      expect(coordinator.isHitlActive, isTrue);

      coordinator.registerDetection(const ActivityDetectionModel(
        stateCode: 0x01,
        eventType: 'walk',
        confidencePercent: 85,
        timestampEpochSec: 1729800000,
        isFall: false,
        isHapticTriggered: false,
      ));

      expect(coordinator.itemCount, equals(1));

      await coordinator.setHitlActive(false);
      expect(coordinator.isHitlActive, isFalse);
      expect(coordinator.itemCount, equals(0));
    });

    test('maintains FIFO buffer capped at maxFifoCapacity (15 items)', () async {
      await coordinator.setHitlActive(true);

      for (int i = 0; i < 20; i++) {
        coordinator.registerDetection(ActivityDetectionModel(
          stateCode: 0x01,
          eventType: 'activity_$i',
          confidencePercent: 70 + i,
          timestampEpochSec: 1729800000 + i,
          isFall: false,
          isHapticTriggered: false,
        ));
      }

      expect(coordinator.itemCount, equals(HitlCoordinator.maxFifoCapacity));
      expect(coordinator.items.first.detectedLabel, equals('activity_19'));
      expect(coordinator.items.last.detectedLabel, equals('activity_5'));
    });

    test('attaches incoming burst readings to latest pending detection', () async {
      await coordinator.setHitlActive(true);

      coordinator.registerDetection(const ActivityDetectionModel(
        stateCode: 0x05,
        eventType: 'sit_down',
        confidencePercent: 80,
        timestampEpochSec: 1729800000,
        isFall: false,
        isHapticTriggered: false,
      ));

      final item = coordinator.items.first;
      expect(item.isBurstReady, isFalse);
      expect(item.readings, isEmpty);

      final burst = List.generate(
        76,
        (i) => ImuReadingModel(deltaMs: i * 53, ax: 0.1, ay: 0.9, az: 0.0, gx: 0, gy: 0, gz: 0),
      );

      coordinator.attachBurstReadings(burst);

      expect(item.isBurstReady, isTrue);
      expect(item.readings.length, equals(76));
    });

    test('updates item label and dismisses items', () async {
      await coordinator.setHitlActive(true);

      final registered = coordinator.registerDetection(const ActivityDetectionModel(
        stateCode: 0x05,
        eventType: 'sit_down',
        confidencePercent: 88,
        timestampEpochSec: 1729800000,
        isFall: false,
        isHapticTriggered: false,
      ));

      coordinator.updateItemLabel(registered.id, 'idle');
      expect(coordinator.items.first.selectedLabel, equals('idle'));

      coordinator.dismissItem(registered.id);
      expect(coordinator.itemCount, equals(0));
    });

    test('updates services dynamically via updateServices', () {
      final fakeMqtt = FakeMqttGatewayService();
      expect(coordinator.mqttService, isNull);

      coordinator.updateServices(mqttService: fakeMqtt);
      expect(coordinator.mqttService, equals(fakeMqtt));
    });

    test('confirmAndPublish publishes to MQTT using item ID and marks item as synchronized', () async {
      final fakeMqtt = FakeMqttGatewayService();
      coordinator.updateServices(mqttService: fakeMqtt);
      await coordinator.setHitlActive(true);

      final registered = coordinator.registerDetection(const ActivityDetectionModel(
        stateCode: 0x01,
        eventType: 'walk',
        confidencePercent: 90,
        timestampEpochSec: 1729800000,
        isFall: false,
        isHapticTriggered: false,
      ));

      expect(registered.isSynchronized, isFalse);

      final result = await coordinator.confirmAndPublish(registered, deviceId: 'HK-SHOE-TEST');
      expect(result, isTrue);
      expect(coordinator.itemCount, equals(1));
      expect(coordinator.items.first.isSynchronized, isTrue);
      expect(fakeMqtt.publishedSessions.length, equals(1));
      expect(fakeMqtt.publishedSessions.first.sessionId, equals(registered.id));
      expect(fakeMqtt.publishedSessions.first.isHitl, isTrue);
    });
  });
}
