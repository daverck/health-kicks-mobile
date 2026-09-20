import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../../services/auth/iot_credentials_model.dart';

/// AWS Signature Version 4 (SigV4) signer specialized for WebSocket connection URLs
/// to AWS IoT Core on port 443.
///
/// AWS IoT Core MQTT over WebSockets official specification:
/// https://docs.aws.amazon.com/iot/latest/developerguide/protocols.html
class SigV4Signer {
  static const String _service = 'iotdevicegateway';
  static const String _algorithm = 'AWS4-HMAC-SHA256';
  static const String _emptyPayloadHash =
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

  /// Forges the complete pre-signed WebSocket (WSS) URL from STS temporary credentials.
  static String buildSignedWebSocketUrl({
    required IoTCredentials credentials,
    DateTime? requestDateTime,
  }) {
    final now = (requestDateTime ?? DateTime.now()).toUtc();
    final dateStamp = _formatDateStamp(now);
    final amzDate = _formatAmzDate(now);

    final credentialScope =
        '$dateStamp/${credentials.region}/$_service/aws4_request';

    var endpoint = credentials.iotEndpoint.trim().toLowerCase();
    if (endpoint.startsWith('https://')) {
      endpoint = endpoint.substring(8);
    } else if (endpoint.startsWith('wss://')) {
      endpoint = endpoint.substring(6);
    }
    if (endpoint.endsWith('/')) {
      endpoint = endpoint.substring(0, endpoint.length - 1);
    }

    // 1. Canonical query parameters (sorted by parameter name in strict alphabetical order)
    // AWS IoT Core MQTT over WebSockets specific rule (omitSessionToken: true):
    // The X-Amz-Security-Token parameter MUST NOT be included in the signed canonical request,
    // but is appended directly to the final URL.
    final canonicalQueryParams = <String, String>{
      'X-Amz-Algorithm': _algorithm,
      'X-Amz-Credential':
          '${credentials.accessKeyId}/$credentialScope',
      'X-Amz-Date': amzDate,
      'X-Amz-SignedHeaders': 'host',
    };

    final sortedKeys = canonicalQueryParams.keys.toList()..sort();
    final canonicalQueryString = sortedKeys
        .map((k) =>
            '${_uriEncodeStrict(k)}=${_uriEncodeStrict(canonicalQueryParams[k]!)}')
        .join('&');

    // 2. Canonical request: GET /mqtt
    final canonicalHeaders = 'host:$endpoint\n';
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

    // 3. String to Sign
    final stringToSign = [
      _algorithm,
      amzDate,
      credentialScope,
      canonicalRequestHash,
    ].join('\n');

    // 4. Signing key derivation
    final signingKey = _getSignatureKey(
      key: credentials.secretAccessKey,
      dateStamp: dateStamp,
      regionName: credentials.region,
      serviceName: _service,
    );

    // 5. Compute HMAC-SHA256 signature
    final signature = Hmac(sha256, signingKey)
        .convert(utf8.encode(stringToSign))
        .toString();

    // 6. Final WSS URL (strictly without fragment or trailing #)
    // Assemble URL with canonical query params, signature, and session token (if present)
    var finalQueryString = '$canonicalQueryString&X-Amz-Signature=$signature';
    if (credentials.sessionToken.isNotEmpty) {
      finalQueryString +=
          '&X-Amz-Security-Token=${_uriEncodeStrict(credentials.sessionToken)}';
    }

    return 'wss://$endpoint/mqtt?$finalQueryString';
  }

  /// Cryptographic derivation of AWS SigV4 signing key:
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

  /// Simple date format: YYYYMMDD (e.g. 20260914)
  static String _formatDateStamp(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  /// ISO 8601 basic timestamp format: YYYYMMDDTHHMMSSZ (e.g. 20260914T193000Z)
  static String _formatAmzDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y$m${d}T$h$min${s}Z';
  }

  /// RFC 3986 strict URI encoder as required by AWS SigV4.
  /// Unreserved characters RFC 3986: [A-Z], [a-z], [0-9], '-', '_', '.', '~'.
  /// All other characters must be percent-encoded with uppercase hex (%XY).
  static String _uriEncodeStrict(String input) {
    return Uri.encodeComponent(input)
        .replaceAll('*', '%2A')
        .replaceAll('%7E', '~')
        .replaceAll('!', '%21')
        .replaceAll("'", '%27')
        .replaceAll('(', '%28')
        .replaceAll(')', '%29');
  }
}
