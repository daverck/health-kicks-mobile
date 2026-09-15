import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/models/studio_command_model.dart';

void main() {
  group('StudioCommandModel - Parsing et Sérialisation JSON', () {
    test('Désérialise correctement un payload JSON complet de commande studio/start', () {
      final json = {
        'session_id': '11112222-3333-4444-5555-666677778888',
        'label': 'course_fractionne',
        'duration_sec': 10.0,
        'pulse_count': 4,
        'pulse_duration_ms': 250,
        'pulse_pause_ms': 400,
        'pulse_intensity': 220,
      };

      final model = StudioCommandModel.fromJson(json);

      expect(model.sessionId, equals('11112222-3333-4444-5555-666677778888'));
      expect(model.label, equals('course_fractionne'));
      expect(model.durationSec, equals(10.0));
      expect(model.pulseCount, equals(4));
      expect(model.pulseDurationMs, equals(250));
      expect(model.pulsePauseMs, equals(400));
      expect(model.pulseIntensity, equals(220));
    });

    test('Applique les valeurs par défaut si les champs optionnels sont absents', () {
      final json = {
        'session_id': '22223333-4444-5555-6666-777788889999',
      };

      final model = StudioCommandModel.fromJson(json);

      expect(model.sessionId, equals('22223333-4444-5555-6666-777788889999'));
      expect(model.label, equals('unlabeled'));
      expect(model.durationSec, equals(5.0));
      expect(model.pulseCount, isNull);
    });

    test('Sérialise fidèlement en JSON', () {
      const model = StudioCommandModel(
        sessionId: '33334444-5555-6666-7777-888899990000',
        label: 'test_gait',
        durationSec: 7.5,
        pulseCount: 3,
      );

      final json = model.toJson();

      expect(json['session_id'], equals('33334444-5555-6666-7777-888899990000'));
      expect(json['label'], equals('test_gait'));
      expect(json['duration_sec'], equals(7.5));
      expect(json['pulse_count'], equals(3));
      expect(json.containsKey('pulse_duration_ms'), isFalse);
    });
  });
}
