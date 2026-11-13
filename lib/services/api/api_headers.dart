import 'dart:math';
import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();

const Set<String> _mutatingHttpMethods = {'POST', 'PUT', 'PATCH'};

final List<RegExp> _idempotentPathPatterns = <RegExp>[
  RegExp(r'/api/v1/fall-alerts/(sms-status|ack)(/|$)'),
  RegExp(r'/api/v1/users/me/alert-contacts(/|$)'),
  RegExp(r'/api/v1/steps/sync(/|$)'),
  RegExp(r'/api/v1/studio/sessions(/|$)'),
  RegExp(r'/commands/studio/start(/|$)'),
];

/// Generates a unique 32-character hexadecimal correlation identifier for distributed tracing.
String generateCorrelationId() {
  final rand = Random.secure();
  final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Generates a UUID v4 idempotency key for mutating API requests.
String generateIdempotencyKey() => _uuid.v4();

/// Returns true when the given HTTP [method] and endpoint [path] require an `Idempotency-Key` header.
bool requiresIdempotencyKey({String? method, String? path}) {
  final normalizedMethod = (method ?? 'POST').trim().toUpperCase();
  if (!_mutatingHttpMethods.contains(normalizedMethod)) {
    return false;
  }
  if (path == null || path.trim().isEmpty) {
    return true;
  }
  final normalizedPath = path.trim();
  return _idempotentPathPatterns.any((pattern) => pattern.hasMatch(normalizedPath));
}

/// Builds standard HTTP request headers with Content-Type, optional Bearer token,
/// distributed tracing X-Correlation-ID, and optional Idempotency-Key for mutating requests.
///
/// Any caller-supplied `Idempotency-Key` (via [idempotencyKey] or [extraHeaders]) is preserved
/// so retries of the same logical operation reuse the exact same key.
Map<String, String> buildApiHeaders(
  String? token, {
  Map<String, String>? extraHeaders,
  String? idempotencyKey,
  bool includeIdempotencyKey = false,
  String? method,
  String? path,
}) {
  final headers = <String, String>{
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'X-Correlation-ID': generateCorrelationId(),
  };
  if (token != null && token.isNotEmpty) {
    headers['Authorization'] = 'Bearer $token';
  }
  if (extraHeaders != null) {
    headers.addAll(extraHeaders);
  }

  final hasExistingHeader = headers.keys.any(
    (k) => k.toLowerCase() == 'idempotency-key' && headers[k]!.trim().isNotEmpty,
  );

  if (!hasExistingHeader) {
    final trimmedKey = idempotencyKey?.trim();
    final shouldAttach = (trimmedKey != null && trimmedKey.isNotEmpty) ||
        includeIdempotencyKey ||
        ((method != null || path != null) &&
            requiresIdempotencyKey(method: method, path: path));

    if (shouldAttach) {
      headers['Idempotency-Key'] =
          (trimmedKey != null && trimmedKey.isNotEmpty)
              ? trimmedKey
              : generateIdempotencyKey();
    }
  }

  return headers;
}
