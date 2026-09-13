import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/models/activity_detection_model.dart';

void main() {
  group('ActivityDetectionModel - Décodage Binaire 7 octets & Mapping MQTT', () {
    test('Décode correctement un événement walk sans chute', () {
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
      expect(mqtt['is_fall'], isFalse);
    });

    test('Décode correctement une alerte de chute avec flags activés', () {
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
      expect(mqtt['is_fall'], isTrue);
      expect(mqtt['haptic_triggered'], isTrue);
    });

    test('Lève une FormatException si le payload contient moins de 7 octets', () {
      expect(
        () => ActivityDetectionModel.fromBytes([0x01, 0x50, 0x00]),
        throwsFormatException,
      );
    });
  });
}
