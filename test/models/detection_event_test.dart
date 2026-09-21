import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/models/detection_event.dart';

void main() {
  group('DetectionEvent Model - Deserialization & Helpers', () {
    test('Deserializes full critical fall event from JSON', () {
      final json = {
        'id': 'evt-12345',
        'device_id': 'HK-2',
        'event_type': 'fall_forward',
        'severity': 'critical',
        'timestamp': '2026-09-20T14:30:00Z',
        'peak_impact_g': 3.45,
        'confidence': 0.94,
        'is_validated': true,
        'metadata': {'location': 'hallway', 'sensor': 'mpu6050'},
      };

      final event = DetectionEvent.fromJson(json);

      expect(event.id, 'evt-12345');
      expect(event.deviceId, 'HK-2');
      expect(event.eventType, 'fall_forward');
      expect(event.severity, EventSeverity.critical);
      expect(event.peakImpactG, 3.45);
      expect(event.confidence, 0.94);
      expect(event.isValidated, isTrue);
      expect(event.metadata?['location'], 'hallway');
      expect(event.formattedTitle, 'Chute détectée');
    });

    test('Infers severity automatically from event_type if missing', () {
      final fallJson = {
        'id': '1',
        'event_type': 'free_fall',
        'timestamp': DateTime.now().toIso8601String(),
      };
      final impactJson = {
        'id': '2',
        'event_type': 'high_impact',
        'timestamp': DateTime.now().toIso8601String(),
      };
      final walkJson = {
        'id': '3',
        'event_type': 'walk',
        'timestamp': DateTime.now().toIso8601String(),
      };

      expect(DetectionEvent.fromJson(fallJson).severity, EventSeverity.critical);
      expect(DetectionEvent.fromJson(impactJson).severity, EventSeverity.warning);
      expect(DetectionEvent.fromJson(walkJson).severity, EventSeverity.info);
    });

    test('Parses timestamp in integer epoch milliseconds or seconds', () {
      final epochMs = 1726840000000; // ms
      final jsonMs = {
        'id': 'e1',
        'event_type': 'walk',
        'timestamp': epochMs,
      };

      final event = DetectionEvent.fromJson(jsonMs);
      expect(event.timestamp.millisecondsSinceEpoch, epochMs);
    });

    test('Formats relative time correctly', () {
      final now = DateTime.now();
      final recentEvent = DetectionEvent(
        id: 'r1',
        deviceId: 'HK-2',
        eventType: 'walk',
        timestamp: now.subtract(const Duration(seconds: 20)),
        severity: EventSeverity.info,
        isValidated: false,
      );

      expect(recentEvent.relativeTime, 'À l\'instant');

      final minutesAgoEvent = DetectionEvent(
        id: 'r2',
        deviceId: 'HK-2',
        eventType: 'walk',
        timestamp: now.subtract(const Duration(minutes: 15)),
        severity: EventSeverity.info,
        isValidated: false,
      );

      expect(minutesAgoEvent.relativeTime, 'Il y a 15 min');
    });

    test('EventHistoryResponse parses items list and calculates hasMore', () {
      final json = {
        'items': [
          {
            'id': '1',
            'event_type': 'fall_detected',
            'severity': 'critical',
            'timestamp': '2026-09-20T10:00:00Z',
          },
          {
            'id': '2',
            'event_type': 'walk',
            'severity': 'info',
            'timestamp': '2026-09-20T11:00:00Z',
          }
        ],
        'total': 50,
        'page': 1,
        'size': 2,
        'has_more': true,
      };

      final response = EventHistoryResponse.fromJson(json, page: 1, size: 2);

      expect(response.events.length, 2);
      expect(response.total, 50);
      expect(response.hasMore, isTrue);
      expect(response.events.first.id, '1');
    });
  });
}

