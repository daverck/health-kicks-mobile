import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/services/api/api_headers.dart';

void main() {
  group('ApiHeaders & Distributed Tracing', () {
    test('generateCorrelationId produces 32-char hex string', () {
      final id1 = generateCorrelationId();
      final id2 = generateCorrelationId();
      expect(id1.length, equals(32));
      expect(id2.length, equals(32));
      expect(id1, isNot(equals(id2)));
      expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(id1), isTrue);
    });

    test('buildApiHeaders attaches X-Correlation-ID and Content-Type', () {
      final headers = buildApiHeaders(null);
      expect(headers['Content-Type'], equals('application/json'));
      expect(headers['X-Correlation-ID'], isNotNull);
      expect(headers.containsKey('Authorization'), isFalse);
    });

    test('buildApiHeaders attaches Bearer token and custom extra headers', () {
      final headers = buildApiHeaders('my-access-token', extraHeaders: {'Accept': 'application/json'});
      expect(headers['Content-Type'], equals('application/json'));
      expect(headers['Accept'], equals('application/json'));
      expect(headers['Authorization'], equals('Bearer my-access-token'));
      expect(headers['X-Correlation-ID'], isNotNull);
    });
  });
}
