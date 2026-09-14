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
      // Jeton STS réel avec caractères spéciaux : +, /, =, *, ~
      const complexToken = 'IQoJb3JpZ2luX2VjEJr+test/value==*tilde~end';
      final creds = IoTCredentials(
        accessKeyId: 'ASIAIOSFODNN7EXAMPLE',
        secretAccessKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
        sessionToken: complexToken,
        expiration: DateTime.parse('2026-09-14T22:00:00Z'),
        // Endpoint avec majuscules, schéma https:// et trailing slash pour tester la sanitisation
        iotEndpoint: 'HTTPS://A2K10W7EBF2TX9-ATS.IOT.EU-NORTH-1.AMAZONAWS.COM/',
        region: 'eu-north-1',
      );

      final fixedDate = DateTime.utc(2026, 9, 14, 19, 30, 0);
      final url = SigV4Signer.buildSignedWebSocketUrl(
        credentials: creds,
        requestDateTime: fixedDate,
      );

      // Vérifie l'absence de tout fragment '#'
      expect(url.contains('#'), isFalse);

      // Vérifie que le schéma est wss et l'endpoint en minuscules
      expect(url.startsWith('wss://a2k10w7ebf2tx9-ats.iot.eu-north-1.amazonaws.com/mqtt?'), isTrue);

      // Vérifie l'encodage RFC 3986 strict dans l'URL brute
      expect(url, contains('%2B')); // '+' -> '%2B'
      expect(url, contains('%2F')); // '/' -> '%2F'
      expect(url, contains('%3D')); // '=' -> '%3D'
      expect(url, contains('%2A')); // '*' -> '%2A'
      expect(url, contains('~end')); // '~' n'est pas encodé

      final uri = Uri.parse(url);
      expect(uri.scheme, equals('wss'));
      expect(uri.host, equals('a2k10w7ebf2tx9-ats.iot.eu-north-1.amazonaws.com'));
      expect(uri.fragment, isEmpty);
      expect(uri.queryParameters['X-Amz-Security-Token'], equals(complexToken));

      // Vérifie que Uri.replace(port: 443) comme le fait mqtt_client préserve une URL propre sans '#'
      final wsUri = uri.replace(port: 443);
      expect(wsUri.toString().contains('#'), isFalse);
    });
  });
}
