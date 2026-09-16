import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'iot_credentials_model.dart';
import 'token_storage_service.dart';

typedef AuthLogCallback = void Function(String message, {bool isError});

/// Repository assurant la récupération et la mise en cache en mémoire des identifiants
/// AWS STS temporaires depuis l'API backend FastAPI HealthKicks.
class IotCredentialsRepository {
  final String backendBaseUrl;
  final http.Client _httpClient;
  final TokenStorageService? tokenStorage;
  final AuthService? authService;
  final FutureOr<String?> Function()? authTokenProvider;
  final AuthLogCallback? onLog;

  IoTCredentials? _cachedCredentials;
  String? _lastCachedDeviceId;

  IotCredentialsRepository({
    required this.backendBaseUrl,
    http.Client? httpClient,
    this.tokenStorage,
    this.authService,
    this.authTokenProvider,
    this.onLog,
  }) : _httpClient = httpClient ?? http.Client();

  /// Identifiants actuellement en mémoire (si valides).
  IoTCredentials? get currentCredentials =>
      (_cachedCredentials != null && !_cachedCredentials!.isExpired)
          ? _cachedCredentials
          : null;

  /// Résout le jeton d'authentification Bearer actuel.
  Future<String?> _resolveAccessToken() async {
    if (authTokenProvider != null) {
      return await authTokenProvider!();
    }
    if (tokenStorage != null) {
      return await tokenStorage!.getAccessToken();
    }
    return null;
  }

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

    // Récupération automatique du token d'accès chiffré
    final token = await _resolveAccessToken();
    if (token == null || token.trim().isEmpty) {
      const errMsg = 'Session expirée ou utilisateur non connecté : impossible d\'obtenir les identifiants STS IoT.';
      onLog?.call('[STS] $errMsg', isError: true);
      throw const HttpException(errMsg);
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
      'Authorization': 'Bearer $token',
    };

    final body = jsonEncode({
      if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
    });

    try {
      var response = await _httpClient.post(
        uri,
        headers: headers,
        body: body,
      );

      // Gestion du jeton expiré (HTTP 401)
      if (response.statusCode == 401) {
        onLog?.call(
          '[STS] Jeton d\'accès expiré (HTTP 401), tentative de rafraîchissement...',
          isError: false,
        );

        bool refreshed = false;
        if (authService != null) {
          try {
            refreshed = await authService!.refreshToken();
          } catch (_) {
            refreshed = false;
          }
        }

        if (refreshed) {
          final refreshedToken = await _resolveAccessToken();
          if (refreshedToken != null && refreshedToken.isNotEmpty) {
            headers['Authorization'] = 'Bearer $refreshedToken';
            response = await _httpClient.post(
              uri,
              headers: headers,
              body: body,
            );
          }
        }

        // Si le rafraîchissement a échoué ou que le serveur renvoie toujours 401
        if (response.statusCode == 401) {
          onLog?.call(
            '[STS] Session définitivement expirée (HTTP 401) : déconnexion automatique de l\'utilisateur vers le login SSO.',
            isError: true,
          );
          await authService?.logout();
          await tokenStorage?.clearTokens();
          const errorMsg =
              '[STS] Échec HTTP 401 (token expired) : utilisateur déconnecté pour ré-authentification SSO.';
          throw HttpException(errorMsg, uri: uri);
        }
      }

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
