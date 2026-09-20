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

    test('Encode strictement selon RFC 3986 les jetons STS complexes et sanitise l\'endpoint', () {
      // Real STS token with special characters: +, /, =, *, ~
      const complexToken = 'IQoJb3JpZ2luX2VjEJr+test/value==*tilde~end';
      final creds = IoTCredentials(
        accessKeyId: 'ASIAIOSFODNN7EXAMPLE',
        secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        sessionToken: complexToken,
        expiration: DateTime.parse('2026-09-14T22:00:00Z'),
        // Endpoint with uppercase, https:// scheme and trailing slash to test sanitization
        iotEndpoint: 'HTTPS://A2K10W7EBF2TX9-ATS.IOT.EU-NORTH-1.AMAZONAWS.COM/',
        region: 'eu-north-1',
      );

      final fixedDate = DateTime.utc(2026, 9, 14, 19, 30, 0);
      final url = SigV4Signer.buildSignedWebSocketUrl(
        credentials: creds,
        requestDateTime: fixedDate,
      );

      // Verify absence of any '#' fragment
      expect(url.contains('#'), isFalse);

      // Verify schema is wss and endpoint is lowercase
      expect(url.startsWith('wss://a2k10w7ebf2tx9-ats.iot.eu-north-1.amazonaws.com/mqtt?'), isTrue);

      // Verify strict RFC 3986 encoding in raw URL
      expect(url, contains('%2B')); // '+' -> '%2B'
      expect(url, contains('%2F')); // '/' -> '%2F'
      expect(url, contains('%3D')); // '=' -> '%3D'
      expect(url, contains('%2A')); // '*' -> '%2A'
      expect(url, contains('~end')); // '~' is not encoded

      final uri = Uri.parse(url);
      expect(uri.scheme, equals('wss'));
      expect(uri.host, equals('a2k10w7ebf2tx9-ats.iot.eu-north-1.amazonaws.com'));
      expect(uri.fragment, isEmpty);
      expect(uri.queryParameters['X-Amz-Security-Token'], equals(complexToken));

      // Verify that Uri.replace(port: 443) preserves a clean URL without '#'
      final wsUri = uri.replace(port: 443);
      expect(wsUri.toString().contains('#'), isFalse);
    });

    test('Respecte la règle AWS IoT Core omitSessionToken (signature indépendante du sessionToken)', () {
      final creds1 = IoTCredentials(
        accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
        secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        sessionToken: 'TOKEN_ALPHA',
        expiration: DateTime.parse('2026-09-14T22:00:00Z'),
        iotEndpoint: 'a2k10w7ebf2tx9-ats.iot.eu-north-1.amazonaws.com',
        region: 'eu-north-1',
      );

      final creds2 = IoTCredentials(
        accessKeyId: 'AKIAIOSFODNN7EXAMPLE',
        secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        sessionToken: 'TOKEN_BETA',
        expiration: DateTime.parse('2026-09-14T22:00:00Z'),
        iotEndpoint: 'a2k10w7ebf2tx9-ats.iot.eu-north-1.amazonaws.com',
        region: 'eu-north-1',
      );

      final fixedDate = DateTime.utc(2026, 9, 14, 19, 30, 0);

      final url1 = SigV4Signer.buildSignedWebSocketUrl(credentials: creds1, requestDateTime: fixedDate);
      final url2 = SigV4Signer.buildSignedWebSocketUrl(credentials: creds2, requestDateTime: fixedDate);

      final uri1 = Uri.parse(url1);
      final uri2 = Uri.parse(url2);

      // Signature is calculated without X-Amz-Security-Token per AWS IoT Core WebSocket specification
      expect(uri1.queryParameters['X-Amz-Signature'], equals(uri2.queryParameters['X-Amz-Signature']));

      // But each URL contains its own X-Amz-Security-Token
      expect(uri1.queryParameters['X-Amz-Security-Token'], equals('TOKEN_ALPHA'));
      expect(uri2.queryParameters['X-Amz-Security-Token'], equals('TOKEN_BETA'));
    });
  });
}
