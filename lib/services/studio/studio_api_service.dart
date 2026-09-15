import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../core/config/app_config.dart';
import '../auth/auth_service.dart';
import '../auth/token_storage_service.dart';

typedef StudioLogCallback = void Function(String message, {bool isError});

/// Service client REST pour la gestion et la persistance des sessions Studio
/// auprès de l'API backend FastAPI HealthKicks.
class StudioApiService {
  final String _backendBaseUrl;
  final http.Client _httpClient;
  final TokenStorageService _tokenStorage;
  final AuthService? _authService;
  final Future<bool> Function()? _refreshTokenFunction;
  final StudioLogCallback? onLog;

  StudioApiService({
    String? backendBaseUrl,
    http.Client? httpClient,
    TokenStorageService? tokenStorage,
    AuthService? authService,
    Future<bool> Function()? refreshTokenFunction,
    this.onLog,
  })  : _backendBaseUrl = (backendBaseUrl ?? AppConfig.backendBaseUrl).trim().replaceAll(RegExp(r'/+$'), ''),
        _httpClient = httpClient ?? http.Client(),
        _tokenStorage = tokenStorage ?? TokenStorageService(),
        _authService = authService,
        _refreshTokenFunction = refreshTokenFunction;

  String get backendBaseUrl => _backendBaseUrl;

  /// Déclare et persiste une session Studio autonome dans la table PostgreSQL
  /// `studio_sessions` via l'API REST du backend FastAPI.
  Future<bool> createStudioSession({
    required String id,
    required String deviceId,
    required String label,
    required double durationSec,
    required int sampleCount,
  }) async {
    String? token = await _tokenStorage.getAccessToken();

    if (token == null || token.trim().isEmpty) {
      const msg = '[Studio] Aucun jeton d\'accès disponible pour persister la session Studio.';
      onLog?.call(msg, isError: true);
      throw const HttpException(msg);
    }

    final uri = Uri.parse('$_backendBaseUrl/api/v1/studio/sessions');
    final payload = {
      'id': id,
      'device_id': deviceId,
      'label': label,
      'duration_sec': durationSec,
      'sample_count': sampleCount,
    };
    final body = jsonEncode(payload);

    Map<String, String> buildHeaders(String currentToken) => {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $currentToken',
        };

    try {
      var response = await _httpClient.post(
        uri,
        headers: buildHeaders(token),
        body: body,
      );

      // Gestion du renouvellement de token en cas de 401
      if (response.statusCode == 401) {
        onLog?.call(
          '[Studio] Jeton d\'accès expiré (HTTP 401), tentative de rafraîchissement...',
          isError: false,
        );

        bool refreshed = false;
        if (_refreshTokenFunction != null) {
          refreshed = await _refreshTokenFunction();
        } else if (_authService != null) {
          refreshed = await _authService.refreshToken();
        }

        if (refreshed) {
          token = await _tokenStorage.getAccessToken();
          if (token != null && token.isNotEmpty) {
            response = await _httpClient.post(
              uri,
              headers: buildHeaders(token),
              body: body,
            );
          }
        } else {
          const msg = '[Studio] Échec du rafraîchissement du jeton d\'authentification : reconnexion requise.';
          onLog?.call(msg, isError: true);
          throw const HttpException(msg);
        }
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        onLog?.call(
          '[Studio] Session persistée avec succès dans le backend (id: $id)',
          isError: false,
        );
        return true;
      } else {
        final errorMsg =
            '[Studio] Échec HTTP ${response.statusCode} lors de la persistance Studio : ${response.body}';
        onLog?.call(errorMsg, isError: true);
        throw HttpException(errorMsg, uri: uri);
      }
    } catch (e) {
      if (e is! HttpException) {
        onLog?.call('[Studio] Erreur réseau lors de la persistance Studio : $e', isError: true);
      }
      rethrow;
    }
  }
}
