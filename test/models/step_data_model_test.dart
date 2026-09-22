import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/models/step_data_model.dart';

void main() {
  group('StepDataModel binary decoding tests', () {
    test('Correctly decodes 13 bytes Big-Endian payload', () {
      final buffer = ByteData(13);
      buffer.setUint32(0, 15420, Endian.big); // total_steps
      buffer.setUint16(4, 10200, Endian.big); // walk_steps
      buffer.setUint16(6, 4500, Endian.big);  // run_steps
      buffer.setUint16(8, 600, Endian.big);   // stairs_steps
      buffer.setUint16(10, 120, Endian.big);  // unclassified_steps
      buffer.setUint8(12, 112);               // cadence_spm

      final bytes = buffer.buffer.asUint8List();
      final now = DateTime(2026, 9, 22, 10, 0, 0);
      final model = StepDataModel.fromBytes(bytes, now);

      expect(model.totalSteps, 15420);
      expect(model.walkSteps, 10200);
      expect(model.runSteps, 4500);
      expect(model.stairsSteps, 600);
      expect(model.unclassifiedSteps, 120);
      expect(model.cadenceSpm, 112);
      expect(model.timestamp, now);
    });

    test('Decodes boundary max values (uint32, uint16, uint8)', () {
      final buffer = ByteData(13);
      buffer.setUint32(0, 4294967295, Endian.big);
      buffer.setUint16(4, 65535, Endian.big);
      buffer.setUint16(6, 65535, Endian.big);
      buffer.setUint16(8, 65535, Endian.big);
      buffer.setUint16(10, 65535, Endian.big);
      buffer.setUint8(12, 255);

      final model = StepDataModel.fromBytes(buffer.buffer.asUint8List());

      expect(model.totalSteps, 4294967295);
      expect(model.walkSteps, 65535);
      expect(model.runSteps, 65535);
      expect(model.stairsSteps, 65535);
      expect(model.unclassifiedSteps, 65535);
      expect(model.cadenceSpm, 255);
    });

    test('Decodes zero values correctly', () {
      final bytes = Uint8List(13); // All 0s
      final model = StepDataModel.fromBytes(bytes);

      expect(model.totalSteps, 0);
      expect(model.walkSteps, 0);
      expect(model.runSteps, 0);
      expect(model.stairsSteps, 0);
      expect(model.unclassifiedSteps, 0);
      expect(model.cadenceSpm, 0);
    });

    test('Throws FormatException if payload length < 13 bytes', () {
      final invalidBytes = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]; // 12 bytes
      expect(
        () => StepDataModel.fromBytes(invalidBytes),
        throwsA(isA<FormatException>()),
      );
    });

    test('JSON and MQTT payload serializations include all fields', () {
      final model = StepDataModel(
        totalSteps: 1000,
        walkSteps: 800,
        runSteps: 150,
        stairsSteps: 50,
        unclassifiedSteps: 0,
        cadenceSpm: 95,
        timestamp: DateTime.utc(2026, 9, 22, 12, 0, 0),
      );

      final json = model.toJson();
      expect(json['total_steps'], 1000);
      expect(json['walk_steps'], 800);
      expect(json['run_steps'], 150);
      expect(json['stairs_steps'], 50);
      expect(json['unclassified_steps'], 0);
      expect(json['cadence_spm'], 95);

      final mqtt = model.toMqttPayload('HK-2');
      expect(mqtt['device_id'], 'HK-2');
      expect(mqtt['total_steps'], 1000);
      expect(mqtt['cadence_spm'], 95);
      expect(mqtt['timestamp'], 1790078400000);
    });
  });
}

