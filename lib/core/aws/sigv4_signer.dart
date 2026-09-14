import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../services/auth/iot_credentials_model.dart';

/// Signataire AWS Signature Version 4 (SigV4) spécialisé pour l'URL de connexion
/// WebSocket à AWS IoT Core sur le port 443.
///
/// Spécification officielle AWS IoT Core MQTT over WebSockets :
/// https://docs.aws.amazon.com/iot/latest/developerguide/protocols.html
class SigV4Signer {
  static const String _service = 'iotdevicegateway';
  static const String _algorithm = 'AWS4-HMAC-SHA256';
  static const String _emptyPayloadHash =
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

  /// Forge l'URL WebSocket complète pré-signée (WSS) à partir des identifiants temporaires STS.
  static String buildSignedWebSocketUrl({
    required IoTCredentials credentials,
    DateTime? requestDateTime,
  }) {
    final now = (requestDateTime ?? DateTime.now()).toUtc();
    final dateStamp = _formatDateStamp(now);
    final amzDate = _formatAmzDate(now);

    final credentialScope =
        '$dateStamp/${credentials.region}/$_service/aws4_request';

    // 1. Paramètres de requête canoniques (triés par nom en ordre alphabétique strict)
    final canonicalQueryParams = <String, String>{
      'X-Amz-Algorithm': _algorithm,
      'X-Amz-Credential':
          '${credentials.accessKeyId}/$credentialScope',
      'X-Amz-Date': amzDate,
      'X-Amz-SignedHeaders': 'host',
    };

    if (credentials.sessionToken.isNotEmpty) {
      canonicalQueryParams['X-Amz-Security-Token'] = credentials.sessionToken;
    }

    final sortedKeys = canonicalQueryParams.keys.toList()..sort();
    final canonicalQueryString = sortedKeys
        .map((k) =>
            '${_uriEncode(k)}=${_uriEncode(canonicalQueryParams[k]!)}')
        .join('&');

    // 2. Requête canonique : GET /mqtt
    final canonicalHeaders = 'host:${credentials.iotEndpoint.toLowerCase()}\n';
    const signedHeaders = 'host';

    final canonicalRequest = [
      'GET',
      '/mqtt',
      canonicalQueryString,
      canonicalHeaders,
      signedHeaders,
      _emptyPayloadHash,
    ].join('\n');

    final canonicalRequestHash =
        sha256.convert(utf8.encode(canonicalRequest)).toString();

    // 3. Chaîne à signer (String to Sign)
    final stringToSign = [
      _algorithm,
      amzDate,
      credentialScope,
      canonicalRequestHash,
    ].join('\n');

    // 4. Dérivation de la clé de signature
    final signingKey = _getSignatureKey(
      key: credentials.secretAccessKey,
      dateStamp: dateStamp,
      regionName: credentials.region,
      serviceName: _service,
    );

    // 5. Calcul de la signature HMAC-SHA256
    final signature = Hmac(sha256, signingKey)
        .convert(utf8.encode(stringToSign))
        .toString();

    // 6. URL finale WSS
    return 'wss://${credentials.iotEndpoint}/mqtt?$canonicalQueryString&X-Amz-Signature=$signature';
  }

  /// Dérivation cryptographique de la clé de signature AWS SigV4 :
  /// kSecret -> kDate -> kRegion -> kService -> kSigning
  static List<int> _getSignatureKey({
    required String key,
    required String dateStamp,
    required String regionName,
    required String serviceName,
  }) {
    final kSecret = utf8.encode('AWS4$key');
    final kDate = Hmac(sha256, kSecret).convert(utf8.encode(dateStamp)).bytes;
    final kRegion = Hmac(sha256, kDate).convert(utf8.encode(regionName)).bytes;
    final kService =
        Hmac(sha256, kRegion).convert(utf8.encode(serviceName)).bytes;
    final kSigning =
        Hmac(sha256, kService).convert(utf8.encode('aws4_request')).bytes;
    return kSigning;
  }

  /// Format date simple : YYYYMMDD (ex: 20260914)
  static String _formatDateStamp(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  /// Format horodatage basique ISO 8601 : YYYYMMDDTHHMMSSZ (ex: 20260914T193000Z)
  static String _formatAmzDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y$m${d}T$h$min${s}Z';
  }

  /// Encodage conforme URI selon AWS SigV4 RFC 3986 (sans encodage des caractères non réservés).
  static String _uriEncode(String input) {
    return Uri.encodeQueryComponent(input)
        .replaceAll('+', '%20')
        .replaceAll('*', '%2A')
        .replaceAll('%7E', '~');
  }
}
