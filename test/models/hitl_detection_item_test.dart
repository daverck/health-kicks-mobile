import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/models/activity_detection_model.dart';
import 'package:healthkicks_mobile/models/hitl/hitl_detection_item.dart';
import 'package:healthkicks_mobile/models/imu_reading_model.dart';

void main() {
  group('HitlDetectionItem', () {
    test('initializes correctly and converts to StudioSessionModel with isHitl=true', () {
      final detection = const ActivityDetectionModel(
        stateCode: 0x05,
        eventType: 'sit_down',
        confidencePercent: 92,
        timestampEpochSec: 1729800000,
        isFall: false,
        isHapticTriggered: false,
      );

      final item = HitlDetectionItem(
        id: 'test-item-uuid',
        timestamp: detection.effectiveTimestamp,
        detectedLabel: detection.eventType,
        confidencePercent: detection.confidencePercent,
        isFall: detection.isFall,
        rawDetection: detection,
      );

      expect(item.detectedLabel, equals('sit_down'));
      expect(item.selectedLabel, equals('sit_down'));
      expect(item.confidencePercent, equals(92));
      expect(item.isBurstReady, isFalse);
      expect(item.readings, isEmpty);

      // Reclassify label
      item.selectedLabel = 'idle';
      item.readings = [
        const ImuReadingModel(deltaMs: 0, ax: 0.1, ay: 0.9, az: -0.1, gx: 0, gy: 0, gz: 0),
        const ImuReadingModel(deltaMs: 53, ax: 0.1, ay: 0.9, az: -0.1, gx: 0, gy: 0, gz: 0),
      ];
      item.isBurstReady = true;

      final session = item.toStudioSession(deviceId: 'HK-2', sessionId: 'custom-session-id');
      expect(session.sessionId, equals('custom-session-id'));
      expect(session.deviceId, equals('HK-2'));
      expect(session.label, equals('idle'));
      expect(session.isHitl, isTrue);
      expect(session.durationSec, equals(4.0));
      expect(session.readings.length, equals(2));

      final restPayload = session.toRestApiPayload();
      expect(restPayload['is_hitl'], isTrue);
      expect(restPayload['label'], equals('idle'));
    });
  });
}

