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

      final mqtt = model.toMqttPayload('HK-42');
      expect(mqtt['device_id'], equals('HK-42'));
      expect(mqtt['event_type'], equals('fall_forward'));
      expect(mqtt['confidence'], closeTo(0.92, 0.001));
      expect(mqtt['timestamp'], equals(1726224050000));
      expect(mqtt['is_fall'], isTrue);
      expect(mqtt['haptic_triggered'], isTrue);
    });

    test('Correctly decodes stairs activity (0x03)', () {
      final byteData = ByteData(7);
      byteData.setUint8(0, 0x03);
      byteData.setUint8(1, 88);
      byteData.setUint32(2, 1726224010, Endian.big);
      byteData.setUint8(6, 0x00);

      final model = ActivityDetectionModel.fromBytes(byteData.buffer.asUint8List());

      expect(model.stateCode, equals(0x03));
      expect(model.eventType, equals('stairs'));
      expect(model.confidencePercent, equals(88));
      expect(model.isFall, isFalse);

      final mqtt = model.toMqttPayload('HK-2');
      expect(mqtt['event_type'], equals('stairs'));
      expect(mqtt['confidence'], closeTo(0.88, 0.001));
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
        0x03: 'stairs',
        0x10: 'fall_forward',
        0x11: 'fall_backward',
        0x12: 'fall_lateral',
        0x1E: 'stumble_recover',
        0x1F: 'fall_generic',
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
      }
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
