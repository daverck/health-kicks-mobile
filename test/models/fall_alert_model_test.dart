import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/models/fall_alert_model.dart';

void main() {
  group('FallAlertUplinkPayload serialization & deserialization', () {
    test('serializes and deserializes DETECTED payload with location', () {
      const location = FallAlertLocation(
        lat: 50.8466,
        lon: 4.3528,
        accuracyM: 12.5,
        capturedAt: 1792745941000,
      );

      final payload = FallAlertUplinkPayload.detected(
        eventId: '0b6f4b1e-6a51-4c1f-9a3e-2d7f1c9b8e10',
        deviceId: 'HK-1',
        eventType: 'fall_forward',
        confidence: 0.91,
        detectedAt: 1792745943123,
        delivery: 'live',
        location: location,
        sentAt: 1792745943410,
      );

      final json = payload.toJson();
      expect(json['event_id'], equals('0b6f4b1e-6a51-4c1f-9a3e-2d7f1c9b8e10'));
      expect(json['action'], equals('DETECTED'));
      expect(json['device_id'], equals('HK-1'));
      expect(json['event_type'], equals('fall_forward'));
      expect(json['confidence'], closeTo(0.91, 0.0001));
      expect(json['detected_at'], equals(1792745943123));
      expect(json['delivery'], equals('live'));
      expect(json['sent_at'], equals(1792745943410));
      expect(json['location'], isA<Map<String, dynamic>>());
      expect(json['location']['lat'], closeTo(50.8466, 0.0001));
      expect(json['location']['lon'], closeTo(4.3528, 0.0001));
      expect(json['location']['accuracy_m'], closeTo(12.5, 0.01));
      expect(json['location']['captured_at'], equals(1792745941000));

      final restored = FallAlertUplinkPayload.fromJson(json);
      expect(restored.eventId, equals(payload.eventId));
      expect(restored.action, equals('DETECTED'));
      expect(restored.deviceId, equals('HK-1'));
      expect(restored.eventType, equals('fall_forward'));
      expect(restored.confidence, closeTo(0.91, 0.0001));
      expect(restored.detectedAt, equals(1792745943123));
      expect(restored.delivery, equals('live'));
      expect(restored.location?.lat, closeTo(50.8466, 0.0001));
      expect(restored.sentAt, equals(1792745943410));
    });

    test('serializes and deserializes CONFIRM and CANCEL payloads', () {
      final confirmPayload = FallAlertUplinkPayload.confirm(
        eventId: '0b6f4b1e-6a51-4c1f-9a3e-2d7f1c9b8e10',
        sentAt: 1792745955100,
      );
      final confirmJson = confirmPayload.toJson();
      expect(confirmJson['event_id'], equals('0b6f4b1e-6a51-4c1f-9a3e-2d7f1c9b8e10'));
      expect(confirmJson['action'], equals('CONFIRM'));
      expect(confirmJson['sent_at'], equals(1792745955100));

      final cancelPayload = FallAlertUplinkPayload.cancel(
        eventId: '0b6f4b1e-6a51-4c1f-9a3e-2d7f1c9b8e10',
        cancelReason: 'fall_recovery',
        sentAt: 1792745951000,
      );
      final cancelJson = cancelPayload.toJson();
      expect(cancelJson['event_id'], equals('0b6f4b1e-6a51-4c1f-9a3e-2d7f1c9b8e10'));
      expect(cancelJson['action'], equals('CANCEL'));
      expect(cancelJson['cancel_reason'], equals('fall_recovery'));
      expect(cancelJson['sent_at'], equals(1792745951000));

      final restoredCancel = FallAlertUplinkPayload.fromJson(cancelJson);
      expect(restoredCancel.action, equals('CANCEL'));
      expect(restoredCancel.cancelReason, equals('fall_recovery'));
    });
  });

  group('FallAlertStatusModel serialization & deserialization', () {
    test('deserializes ESCALATING and ACKNOWLEDGED downlink statuses', () {
      final escalatingJson = {
        'event_id': '0b6f4b1e-6a51-4c1f-9a3e-2d7f1c9b8e10',
        'alert_id': 42,
        'state': 'ESCALATING',
        'current_contact_rank': 1,
        'contacts_total': 3,
        'acknowledged_by': null,
        'cancel_reason': null,
        'next_action_at': '2026-10-23T08:43:03Z',
        'updated_at': '2026-10-23T08:40:03Z',
      };

      final escalating = FallAlertStatusModel.fromJson(escalatingJson);
      expect(escalating.eventId, equals('0b6f4b1e-6a51-4c1f-9a3e-2d7f1c9b8e10'));
      expect(escalating.alertId, equals(42));
      expect(escalating.state, equals('ESCALATING'));
      expect(escalating.isEscalating, isTrue);
      expect(escalating.currentContactRank, equals(1));
      expect(escalating.contactsTotal, equals(3));
      expect(escalating.acknowledgedBy, isNull);
      expect(escalating.nextActionAt, equals(DateTime.utc(2026, 10, 23, 8, 43, 3)));

      final ackJson = {
        'event_id': '0b6f4b1e-6a51-4c1f-9a3e-2d7f1c9b8e10',
        'alert_id': 42,
        'state': 'ACKNOWLEDGED',
        'current_contact_rank': 2,
        'contacts_total': 3,
        'acknowledged_by': {
          'first_name': 'Paul',
          'last_name': 'Martin',
        },
        'cancel_reason': null,
        'next_action_at': null,
        'updated_at': '2026-10-23T08:44:51Z',
      };

      final ack = FallAlertStatusModel.fromJson(ackJson);
      expect(ack.isAcknowledged, isTrue);
      expect(ack.acknowledgedBy, isNotNull);
      expect(ack.acknowledgedBy!.firstName, equals('Paul'));
      expect(ack.acknowledgedBy!.lastName, equals('Martin'));

      final roundTrip = FallAlertStatusModel.fromJson(ack.toJson());
      expect(roundTrip.state, equals('ACKNOWLEDGED'));
      expect(roundTrip.acknowledgedBy!.firstName, equals('Paul'));
    });
  });
}
