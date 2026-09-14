import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'iot_credentials_model.dart';

typedef AuthLogCallback = void Function(String message, {bool isError});

/// Repository assurant la récupération et la mise en cache en mémoire des identifiants
/// AWS STS temporaires depuis l'API backend FastAPI HealthKicks.
class IotCredentialsRepository {
  final String backendBaseUrl;
  final http.Client _httpClient;
  final String? Function()? authTokenProvider;
  final AuthLogCallback? onLog;

  IoTCredentials? _cachedCredentials;
  String? _lastCachedDeviceId;

  IotCredentialsRepository({
    required this.backendBaseUrl,
    http.Client? httpClient,
    this.authTokenProvider,
    this.onLog,
  }) : _httpClient = httpClient ?? http.Client();

  /// Identifiants actuellement en mémoire (si valides).
  IoTCredentials? get currentCredentials =>
      (_cachedCredentials != null && !_cachedCredentials!.isExpired)
          ? _cachedCredentials
          : null;

  /// Récupère des identifiants AWS STS valides.
  /// Réutilise le cache en mémoire si disponible et non expiré (marge de 5 min).
  /// En cas de changement de `deviceId`, le cache est invalidé pour obtenir un scope adapté.
  Future<IoTCredentials> fetchCredentials({
    String? deviceId,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _cachedCredentials != null &&
        !_cachedCredentials!.isExpired &&
        _lastCachedDeviceId == deviceId) {
      onLog?.call(
        '[STS] Réutilisation des identifiants STS en cache (expire à ${_cachedCredentials!.expiration.toIso8601String()}).',
        isError: false,
      );
      return _cachedCredentials!;
    }

    onLog?.call(
      '[STS] Requête au backend pour obtenir des identifiants STS temporaires (deviceId: ${deviceId ?? "auto"})...',
      isError: false,
    );

    // Normalisation de l'URL du backend
    final sanitizedBase = backendBaseUrl.endsWith('/')
        ? backendBaseUrl.substring(0, backendBaseUrl.length - 1)
        : backendBaseUrl;
    final uri = Uri.parse('$sanitizedBase/api/v1/auth/iot-credentials');

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    final token = authTokenProvider?.call();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final body = jsonEncode({
      if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
    });

    try {
      final response = await _httpClient.post(
        uri,
        headers: headers,
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final credentials = IoTCredentials.fromJson(data);
        _cachedCredentials = credentials;
        _lastCachedDeviceId = deviceId;

        onLog?.call(
          '[STS] Nouveaux identifiants STS obtenus avec succès (Expire à : ${credentials.expiration.toIso8601String()}, Région : ${credentials.region}).',
          isError: false,
        );
        return credentials;
      } else {
        final errorMsg =
            '[STS] Échec HTTP ${response.statusCode} lors de l\'échange de jeton : ${response.body}';
        onLog?.call(errorMsg, isError: true);
        throw HttpException(errorMsg, uri: uri);
      }
    } catch (e) {
      if (e is! HttpException) {
        onLog?.call('[STS] Erreur réseau lors de l\'appel backend : $e', isError: true);
      }
      rethrow;
    }
  }

  /// Invalide manuellement le cache.
  void clearCache() {
    _cachedCredentials = null;
    _lastCachedDeviceId = null;
  }
}
