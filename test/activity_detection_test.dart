import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/models/activity_detection_model.dart';

void main() {
  group('ActivityDetectionModel - 7-byte Binary Decoding & MQTT Mapping', () {
    test('Correctly decodes a walk event without fall', () {
      // Offset 0: state_code = 0x01 (walk)
      // Offset 1: confidence = 85%
      // Offset 2..5: timestamp = 1726224000 (0x66E41C80)
      // Offset 6: flags = 0x00
      final byteData = ByteData(7);
      byteData.setUint8(0, 0x01);
      byteData.setUint8(1, 85);
      byteData.setUint32(2, 1726224000, Endian.big);
      byteData.setUint8(6, 0x00);

      final model = ActivityDetectionModel.fromBytes(byteData.buffer.asUint8List());

      expect(model.stateCode, equals(0x01));
      expect(model.eventType, equals('walk'));
      expect(model.confidencePercent, equals(85));
      expect(model.timestampEpochSec, equals(1726224000));
      expect(model.isFall, isFalse);
      expect(model.isHapticTriggered, isFalse);
      expect(model.isOfflineBuffered, isFalse);
      expect(model.isFallRecovery, isFalse);

      final mqtt = model.toMqttPayload('HK-1');
      expect(mqtt['device_id'], equals('HK-1'));
      expect(mqtt['event_type'], equals('walk'));
      expect(mqtt['confidence'], closeTo(0.85, 0.001));
      expect(mqtt['timestamp'], equals(1726224000000));
      expect(mqtt['is_fall'], isFalse);
    });

    test('Correctly decodes a fall alert with flags enabled', () {
      // Offset 0: state_code = 0x10 (fall_forward)
      // Offset 1: confidence = 92%
      // Offset 2..5: timestamp = 1726224050
      // Offset 6: flags = 0x03 (bit 0: isFall, bit 1: hapticTriggered)
      final byteData = ByteData(7);
      byteData.setUint8(0, 0x10);
      byteData.setUint8(1, 92);
      byteData.setUint32(2, 1726224050, Endian.big);
      byteData.setUint8(6, 0x03);

      final model = ActivityDetectionModel.fromBytes(byteData.buffer.asUint8List());

      expect(model.stateCode, equals(0x10));
      expect(model.eventType, equals('fall_forward'));
      expect(model.confidencePercent, equals(92));
      expect(model.isFall, isTrue);
      expect(model.isHapticTriggered, isTrue);
      expect(model.isOfflineBuffered, isFalse);

      final mqtt = model.toMqttPayload('HK-42');
      expect(mqtt['device_id'], equals('HK-42'));
      expect(mqtt['event_type'], equals('fall_forward'));
      expect(mqtt['confidence'], closeTo(0.92, 0.001));
      expect(mqtt['timestamp'], equals(1726224050000));
      expect(mqtt['is_fall'], isTrue);
      expect(mqtt['haptic_triggered'], isTrue);
    });

    test('Correctly decodes isOfflineBuffered (bit 2 of flags = 0x04) and isFallRecovery (0x13)', () {
      // Offline buffered fall: flags = 0x05 (bit 0 = fall, bit 2 = offline NVS buffered)
      final offlineFallBytes = ByteData(7);
      offlineFallBytes.setUint8(0, 0x12); // fall_lateral
      offlineFallBytes.setUint8(1, 94);
      offlineFallBytes.setUint32(2, 1726224100, Endian.big);
      offlineFallBytes.setUint8(6, 0x05);

      final offlineFall = ActivityDetectionModel.fromBytes(offlineFallBytes.buffer.asUint8List());
      expect(offlineFall.stateCode, equals(0x12));
      expect(offlineFall.eventType, equals('fall_lateral'));
      expect(offlineFall.isFall, isTrue);
      expect(offlineFall.isHapticTriggered, isFalse);
      expect(offlineFall.isOfflineBuffered, isTrue);
      expect(offlineFall.isFallRecovery, isFalse);

      // Fall recovery event: stateCode = 0x13
      final recoveryBytes = ByteData(7);
      recoveryBytes.setUint8(0, 0x13); // fall_recovery
      recoveryBytes.setUint8(1, 89);
      recoveryBytes.setUint32(2, 1726224115, Endian.big);
      recoveryBytes.setUint8(6, 0x00);

      final recovery = ActivityDetectionModel.fromBytes(recoveryBytes.buffer.asUint8List());
      expect(recovery.stateCode, equals(0x13));
      expect(recovery.eventType, equals('fall_recovery'));
      expect(recovery.isFallRecovery, isTrue);
      expect(recovery.isFall, isFalse);
      expect(recovery.isOfflineBuffered, isFalse);
    });

    test('Correctly decodes stairs_up (0x03) and stairs_down (0x04) activities', () {
      final byteDataUp = ByteData(7);
      byteDataUp.setUint8(0, 0x03);
      byteDataUp.setUint8(1, 88);
      byteDataUp.setUint32(2, 1726224010, Endian.big);
      byteDataUp.setUint8(6, 0x00);

      final modelUp = ActivityDetectionModel.fromBytes(byteDataUp.buffer.asUint8List());
      expect(modelUp.stateCode, equals(0x03));
      expect(modelUp.eventType, equals('stairs_up'));
      expect(modelUp.confidencePercent, equals(88));
      expect(modelUp.isFall, isFalse);

      final byteDataDown = ByteData(7);
      byteDataDown.setUint8(0, 0x04);
      byteDataDown.setUint8(1, 85);
      byteDataDown.setUint32(2, 1726224015, Endian.big);
      byteDataDown.setUint8(6, 0x00);

      final modelDown = ActivityDetectionModel.fromBytes(byteDataDown.buffer.asUint8List());
      expect(modelDown.stateCode, equals(0x04));
      expect(modelDown.eventType, equals('stairs_down'));
      expect(modelDown.confidencePercent, equals(85));
      expect(modelDown.isFall, isFalse);
    });

    test('Correctly decodes stumble_recover event (0x1E)', () {
      final byteData = ByteData(7);
      byteData.setUint8(0, 0x1E);
      byteData.setUint8(1, 75);
      byteData.setUint32(2, 1726224020, Endian.big);
      byteData.setUint8(6, 0x00);

      final model = ActivityDetectionModel.fromBytes(byteData.buffer.asUint8List());

      expect(model.stateCode, equals(0x1E));
      expect(model.eventType, equals('stumble_recover'));
      expect(model.confidencePercent, equals(75));
      expect(model.isFall, isFalse);

      final mqtt = model.toMqttPayload('HK-2');
      expect(mqtt['event_type'], equals('stumble_recover'));
      expect(mqtt['confidence'], closeTo(0.75, 0.001));
    });

    test('Correctly decodes all standard activity and fall state codes', () {
      final stateMappings = {
        0x00: 'idle',
        0x01: 'walk',
        0x02: 'run',
        0x03: 'stairs_up',
        0x04: 'stairs_down',
        0x05: 'sit_down',
        0x06: 'stand_up',
        0x07: 'lying_supine',
        0x08: 'lying_prone',
        0x09: 'lying_lateral',
        0x10: 'fall_forward',
        0x11: 'fall_backward',
        0x12: 'fall_lateral',
        0x13: 'fall_recovery',
        0x1E: 'stumble_recover',
        0x1F: 'fall_generic',
        0x20: 'inactivity_alert',
        0x42: 'unknown_0x42',
      };

      for (final entry in stateMappings.entries) {
        final byteData = ByteData(7);
        byteData.setUint8(0, entry.key);
        byteData.setUint8(1, 90);
        byteData.setUint32(2, 1726224000, Endian.big);
        byteData.setUint8(6, 0x00);

        final model = ActivityDetectionModel.fromBytes(byteData.buffer.asUint8List());
        expect(model.stateCode, equals(entry.key));
        expect(model.eventType, equals(entry.value));
        if (entry.key == 0x00 || entry.key == 0x05 || entry.key == 0x07 || entry.key == 0x08 || entry.key == 0x09) {
          expect(model.activityCategory, ActivityCategory.sedentary);
          expect(model.isSedentary, isTrue);
        }
        if (entry.key >= 0x07 && entry.key <= 0x09) {
          expect(model.isLying, isTrue);
        }
        if (entry.key == 0x13) {
          expect(model.isFallRecovery, isTrue);
        } else {
          expect(model.isFallRecovery, isFalse);
        }
      }
    });

    test('Classifies locomotion states as active and seated posture as sedentary', () {
      const sitDown = ActivityDetectionModel(
        stateCode: 0x05,
        eventType: 'sit_down',
        confidencePercent: 90,
        timestampEpochSec: 1726224000,
        isFall: false,
        isHapticTriggered: false,
      );
      const walk = ActivityDetectionModel(
        stateCode: 0x01,
        eventType: 'walk',
        confidencePercent: 90,
        timestampEpochSec: 1726224000,
        isFall: false,
        isHapticTriggered: false,
      );

      expect(sitDown.isSeated, isTrue);
      expect(sitDown.activityCategory, ActivityCategory.sedentary);
      expect(walk.activityCategory, ActivityCategory.active);
    });

    test('Correctly handles MCU boot uptime (< 10^9) by using current UTC timestamp', () {
      // Offset 0: state_code = 0x11 (fall_backward)
      // Offset 1: confidence = 86%
      // Offset 2..5: timestamp = 24 (uptime in seconds)
      // Offset 6: flags = 0x03 (fall + haptic)
      final byteData = ByteData(7);
      byteData.setUint8(0, 0x11);
      byteData.setUint8(1, 86);
      byteData.setUint32(2, 24, Endian.big);
      byteData.setUint8(6, 0x03);

      final model = ActivityDetectionModel.fromBytes(byteData.buffer.asUint8List());

      expect(model.stateCode, equals(0x11));
      expect(model.eventType, equals('fall_backward'));
      expect(model.timestampEpochSec, equals(24));
      expect(model.isFall, isTrue);

      final beforeMs = DateTime.now().toUtc().subtract(const Duration(seconds: 2)).millisecondsSinceEpoch;
      final mqtt = model.toMqttPayload('HK-2');
      final afterMs = DateTime.now().toUtc().add(const Duration(seconds: 2)).millisecondsSinceEpoch;

      expect(mqtt['device_id'], equals('HK-2'));
      expect(mqtt['event_type'], equals('fall_backward'));
      expect(mqtt['confidence'], closeTo(0.86, 0.001));
      expect(mqtt['is_fall'], isTrue);
      expect(mqtt['haptic_triggered'], isTrue);

      expect(mqtt['timestamp'], isA<int>());
      final timestampVal = mqtt['timestamp'] as int;
      expect(timestampVal, greaterThanOrEqualTo(beforeMs));
      expect(timestampVal, lessThanOrEqualTo(afterMs));
    });

    test('Throws a FormatException if payload contains less than 7 bytes', () {
      expect(
        () => ActivityDetectionModel.fromBytes([0x01, 0x50, 0x00]),
        throwsFormatException,
      );
    });
  });
}
