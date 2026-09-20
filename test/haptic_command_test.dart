import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/models/haptic_command_model.dart';

void main() {
  group('HapticCommandModel - JSON Parsing & 4-byte Big-Endian Serialization', () {
    test('Accurately serializes a standard haptic command', () {
      final json = {
        'command_id': 'cmd-uuid-999',
        'intensity': 200,
        'duration_ms': 500,
        'pattern': 'single_pulse',
      };

      final model = HapticCommandModel.fromJson(json);
      final bytes = model.toBleBytes();

      expect(bytes.length, equals(4));

      final byteData = ByteData.sublistView(bytes);
      expect(byteData.getUint8(0), equals(0)); // pattern single_pulse
      expect(byteData.getUint8(1), equals(200)); // intensity
      expect(byteData.getUint16(2, Endian.big), equals(500)); // duration 500ms
    });

    test('Applies clamping to boundary values', () {
      final json = {
        'command_id': 'cmd-overflow',
        'intensity': 999, // Must be clamped to 255
        'duration_ms': 50000, // Must be clamped to 10000
        'pattern': 'double_pulse',
      };

      final model = HapticCommandModel.fromJson(json);
      final bytes = model.toBleBytes();

      final byteData = ByteData.sublistView(bytes);
      expect(byteData.getUint8(0), equals(1)); // double_pulse
      expect(byteData.getUint8(1), equals(255));
      expect(byteData.getUint16(2, Endian.big), equals(10000));
    });

    test('Accurately serializes UI test command (pattern 0, intensity 200, duration 400ms)', () {
      const command = HapticCommandModel(
        commandId: 'manual-test-vib',
        patternId: 0,
        intensity: 200,
        durationMs: 400,
      );
      final bytes = command.toBleBytes();
      expect(bytes, equals([0x00, 0xC8, 0x01, 0x90])); // 200 = 0xC8, 400 = 0x0190
    });
  });
}
