import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/controllers/fall_alert_controller.dart';
import 'package:healthkicks_mobile/models/activity_detection_model.dart';
import 'package:healthkicks_mobile/models/fall_alert_model.dart';
import 'package:healthkicks_mobile/services/audio/fall_alert_audio_service.dart';
import 'package:healthkicks_mobile/services/location/fall_location_provider.dart';

class MockFallAlertAudioService extends FallAlertAudioService {
  int startAlarmCalls = 0;
  int stopAlarmCalls = 0;
  int disposeCalls = 0;

  MockFallAlertAudioService() : super(enableAudio: false);

  @override
  Future<void> startEscalationAlarm() async {
    startAlarmCalls++;
  }

  @override
  Future<void> stopAlarm() async {
    stopAlarmCalls++;
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
  }
}

void main() {
  group('FallAlertAudioService integration with FallAlertController', () {
    const liveFallDetection = ActivityDetectionModel(
      stateCode: 0x10,
      eventType: 'fall_forward',
      confidencePercent: 95,
      timestampEpochSec: 1792745943,
      isFall: true,
      isHapticTriggered: true,
    );

    test('Plays emergency siren upon ESCALATING and stops when alert is called off or acknowledged', () async {
      final mockAudio = MockFallAlertAudioService();
      final controller = FallAlertController(
        deviceId: 'HK-1',
        locationProvider: const StaticFallLocationProvider(),
        isMqttConnectedGetter: () => true,
        audioService: mockAudio,
        onPublishUplink: (_) async => true,
      );

      // 1. Initial state -> no alarm
      expect(mockAudio.startAlarmCalls, equals(0));

      // 2. Fall detected -> PENDING (countdown)
      await controller.onActivityDetected(liveFallDetection);
      expect(controller.state, equals('PENDING'));
      expect(mockAudio.startAlarmCalls, equals(0));

      // 3. User taps "J'ai besoin d'aide maintenant" or countdown expires -> ESCALATING
      await controller.confirmEmergencyNow();
      expect(controller.state, equals('ESCALATING'));
      expect(mockAudio.startAlarmCalls, equals(1));

      // 4. Alert acknowledged by contact -> alarm stops
      controller.onDownlinkStatusReceived(FallAlertStatusModel(
        eventId: controller.activeEventId!,
        alertId: 10,
        state: 'ACKNOWLEDGED',
        acknowledgedBy: const FallAlertAcknowledgedBy(firstName: 'Alice'),
      ));
      expect(controller.state, equals('ACKNOWLEDGED'));
      expect(mockAudio.stopAlarmCalls, greaterThanOrEqualTo(1));

      controller.dispose();
      expect(mockAudio.disposeCalls, equals(1));
    });

    test('Stops siren immediately when user cancels alert during escalation', () async {
      final mockAudio = MockFallAlertAudioService();
      final controller = FallAlertController(
        deviceId: 'HK-1',
        locationProvider: const StaticFallLocationProvider(),
        isMqttConnectedGetter: () => true,
        audioService: mockAudio,
        onPublishUplink: (_) async => true,
      );

      await controller.onActivityDetected(liveFallDetection);
      await controller.confirmEmergencyNow();
      expect(controller.state, equals('ESCALATING'));
      expect(mockAudio.startAlarmCalls, equals(1));

      // User taps "Je vais bien (Annuler l'alerte)"
      await controller.cancelByUser();
      expect(controller.state, equals('CANCELLED'));
      expect(mockAudio.stopAlarmCalls, greaterThanOrEqualTo(1));

      controller.dispose();
    });

    test('Stops siren when fall_recovery is detected during escalation', () async {
      final mockAudio = MockFallAlertAudioService();
      final controller = FallAlertController(
        deviceId: 'HK-1',
        locationProvider: const StaticFallLocationProvider(),
        isMqttConnectedGetter: () => true,
        audioService: mockAudio,
        onPublishUplink: (_) async => true,
      );

      await controller.onActivityDetected(liveFallDetection);
      await controller.confirmEmergencyNow();
      expect(controller.state, equals('ESCALATING'));
      expect(mockAudio.startAlarmCalls, equals(1));

      // Sensor sends fall_recovery event (0x13)
      const recoveryDetection = ActivityDetectionModel(
        stateCode: 0x13,
        eventType: 'fall_recovery',
        confidencePercent: 90,
        timestampEpochSec: 1792745970,
        isFall: false,
        isHapticTriggered: false,
      );

      await controller.onActivityDetected(recoveryDetection);
      expect(controller.state, equals('CANCELLED'));
      expect(mockAudio.stopAlarmCalls, greaterThanOrEqualTo(1));

      controller.dispose();
    });
  });
}

