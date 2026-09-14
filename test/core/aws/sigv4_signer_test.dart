import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/core/aws/sigv4_signer.dart';
import 'package:healthkicks_mobile/services/auth/iot_credentials_model.dart';

void main() {
  group('SigV4Signer - AWS IoT Core WebSockets SigV4', () {
    test('Forge une URL WebSocket WSS valide avec paramètres canoniques et signature hex', () {
      final creds = IoTCredentials(
        accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
        secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        sessionToken: 'AQoDYXdzEJr111111111111111111111111',
        expiration: DateTime.parse('2026-09-14T22:00:00Z'),
        iotEndpoint: 'a2k10w7ebf2tx9-ats.iot.eu-north-1.amazonaws.com',
        region: 'eu-north-1',
      );

      final fixedDate = DateTime.utc(2026, 9, 14, 19, 30, 0);

      final url = SigV4Signer.buildSignedWebSocketUrl(
        credentials: creds,
        requestDateTime: fixedDate,
      );

      expect(url.startsWith('wss://a2k10w7ebf2tx9-ats.iot.eu-north-1.amazonaws.com/mqtt?'), isTrue);

      final uri = Uri.parse(url);
      expect(uri.scheme, equals('wss'));
      expect(uri.host, equals('a2k10w7ebf2tx9-ats.iot.eu-north-1.amazonaws.com'));
      expect(uri.path, equals('/mqtt'));

      final query = uri.queryParameters;
      expect(query['X-Amz-Algorithm'], equals('AWS4-HMAC-SHA256'));
      expect(
        query['X-Amz-Credential'],
        equals('AKIAIOSFODNN7EXAMPLE/20260914/eu-north-1/iotdevicegateway/aws4_request'),
      );
      expect(query['X-Amz-Date'], equals('20260914T193000Z'));
      expect(query['X-Amz-SignedHeaders'], equals('host'));
      expect(query['X-Amz-Security-Token'], equals('AQoDYXdzEJr111111111111111111111111'));
      expect(query.containsKey('X-Amz-Signature'), isTrue);
      expect(query['X-Amz-Signature']!.length, equals(64)); // SHA256 hex string
    });

    test('Fonctionne également sans sessionToken (ex: IAM User classique)', () {
      final creds = IoTCredentials(
        accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
        secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        sessionToken: '',
        expiration: DateTime.parse('2026-09-14T22:00:00Z'),
        iotEndpoint: 'a2k10w7ebf2tx9-ats.iot.eu-west-3.amazonaws.com',
        region: 'eu-west-3',
      );

      final fixedDate = DateTime.utc(2026, 9, 14, 12, 0, 0);
      final url = SigV4Signer.buildSignedWebSocketUrl(
        credentials: creds,
        requestDateTime: fixedDate,
      );

      final uri = Uri.parse(url);
      expect(uri.queryParameters.containsKey('X-Amz-Security-Token'), isFalse);
      expect(uri.queryParameters['X-Amz-Credential'], contains('/eu-west-3/iotdevicegateway/aws4_request'));
      expect(uri.queryParameters['X-Amz-Signature']!.length, equals(64));
    });
  });
}
