import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/models/haptic_command_model.dart';

void main() {
  group('HapticCommandModel - Parsing JSON & Sérialisation 4 octets Big-Endian', () {
    test('Sérialise fidèlement une commande haptique standard', () {
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

    test('Applique le bornage des valeurs limites (clamping)', () {
      final json = {
        'command_id': 'cmd-overflow',
        'intensity': 999, // Doit être borné à 255
        'duration_ms': 50000, // Doit être borné à 10000
        'pattern': 'double_pulse',
      };

      final model = HapticCommandModel.fromJson(json);
      final bytes = model.toBleBytes();

      final byteData = ByteData.sublistView(bytes);
      expect(byteData.getUint8(0), equals(1)); // double_pulse
      expect(byteData.getUint8(1), equals(255));
      expect(byteData.getUint16(2, Endian.big), equals(10000));
    });
  });
}
