import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/services/api/api_headers.dart';

void main() {
  group('buildApiHeaders & Idempotency-Key support', () {
    test('does not include Idempotency-Key by default for read requests', () {
      final headers = buildApiHeaders('jwt-token');
      expect(headers['Authorization'], 'Bearer jwt-token');
      expect(headers.containsKey('X-Correlation-ID'), isTrue);
      expect(headers.containsKey('Idempotency-Key'), isFalse);
    });

    test('attaches generated UUID v4 Idempotency-Key for mutating target paths', () {
      final smsHeaders = buildApiHeaders(
        'jwt-token',
        method: 'POST',
        path: '/api/v1/fall-alerts/sms-status',
      );
      expect(smsHeaders['Idempotency-Key'], isNotNull);
      expect(smsHeaders['Idempotency-Key']!.length, greaterThanOrEqualTo(32));

      final stepsHeaders = buildApiHeaders(
        'jwt-token',
        method: 'POST',
        path: '/api/v1/steps/sync',
      );
      expect(stepsHeaders['Idempotency-Key'], isNotNull);

      final studioHeaders = buildApiHeaders(
        'jwt-token',
        method: 'POST',
        path: '/api/v1/devices/HK-1/commands/studio/start',
      );
      expect(studioHeaders['Idempotency-Key'], isNotNull);
    });

    test('preserves caller-supplied idempotencyKey across retries', () {
      final headers1 = buildApiHeaders(
        'token-v1',
        idempotencyKey: 'retry-key-abc-123',
      );
      final headers2 = buildApiHeaders(
        'token-v2',
        idempotencyKey: 'retry-key-abc-123',
      );
      expect(headers1['Idempotency-Key'], 'retry-key-abc-123');
      expect(headers2['Idempotency-Key'], 'retry-key-abc-123');
    });

    test('requiresIdempotencyKey returns false for GET and DELETE', () {
      expect(
        requiresIdempotencyKey(method: 'GET', path: '/api/v1/fall-alerts/sms-status'),
        isFalse,
      );
      expect(
        requiresIdempotencyKey(method: 'DELETE', path: '/api/v1/studio/sessions/123'),
        isFalse,
      );
      expect(
        requiresIdempotencyKey(method: 'PATCH', path: '/api/v1/studio/sessions/123/confirm'),
        isTrue,
      );
    });
  });
}
