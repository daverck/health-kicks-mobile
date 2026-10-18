import 'dart:math';

/// Generates a unique 32-character hexadecimal correlation identifier for distributed tracing.
String generateCorrelationId() {
  final rand = Random.secure();
  final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Builds standard HTTP request headers with Content-Type, optional Bearer token,
/// and distributed tracing X-Correlation-ID.
Map<String, String> buildApiHeaders(String? token, {Map<String, String>? extraHeaders}) {
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
  return headers;
}

