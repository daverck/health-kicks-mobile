import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../core/config/app_config.dart';
import '../auth/auth_service.dart';
import '../auth/token_storage_service.dart';

typedef StudioLogCallback = void Function(String message, {bool isError});

/// Réponse retournée par l'API backend lors de l'initiation d'une commande Studio.
/// Conforme au schéma Pydantic `StudioStartResponse`.
class StudioStartResponse {
  final String status;
  final String deviceId;
  final String sessionId;
  final String label;
  final double durationSec;
  final String topic;

  const StudioStartResponse({
    required this.status,
    required this.deviceId,
    required this.sessionId,
    required this.label,
    required this.durationSec,
    required this.topic,
  });

  factory StudioStartResponse.fromJson(Map<String, dynamic> json) {
    return StudioStartResponse(
      status: json['status'] as String? ?? 'command_dispatched',
      deviceId: json['device_id'] as String,
      sessionId: json['session_id'] as String,
      label: json['label'] as String,
      durationSec: (json['duration_sec'] as num).toDouble(),
      topic: json['topic'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'device_id': deviceId,
      'session_id': sessionId,
      'label': label,
      'duration_sec': durationSec,
      'topic': topic,
    };
  }
}

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

  /// Déclenche et réserve une session Studio dans la table PostgreSQL
  /// `studio_sessions` via l'API REST du backend FastAPI :
  /// `POST /api/v1/devices/{device_id}/commands/studio/start`
  /// Retourne un [StudioStartResponse] contenant l'UUID officiel [sessionId].
  Future<StudioStartResponse> startStudioSession({
    required String deviceId,
    required String label,
    double durationSec = 5.0,
    int? pulseCount,
    int? pulseDurationMs,
    int? pulsePauseMs,
    int? pulseIntensity,
  }) async {
    String? token = await _tokenStorage.getAccessToken();

    if (token == null || token.trim().isEmpty) {
      const msg = '[Studio] Aucun jeton d\'accès disponible pour déclencher la session Studio.';
      onLog?.call(msg, isError: true);
      throw const HttpException(msg);
    }

    final uri = Uri.parse('$_backendBaseUrl/api/v1/devices/$deviceId/commands/studio/start');
    final payload = <String, dynamic>{
      'label': label,
      'duration_sec': durationSec,
      if (pulseCount != null) 'pulse_count': pulseCount,
      if (pulseDurationMs != null) 'pulse_duration_ms': pulseDurationMs,
      if (pulsePauseMs != null) 'pulse_pause_ms': pulsePauseMs,
      if (pulseIntensity != null) 'pulse_intensity': pulseIntensity,
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
          await _authService?.logout();
          await _tokenStorage.clearTokens();
          throw const HttpException(msg);
        }
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final startResponse = StudioStartResponse.fromJson(data);
        onLog?.call(
          '[Studio] Session réservée avec succès dans le backend (id: ${startResponse.sessionId})',
          isError: false,
        );
        return startResponse;
      } else {
        final errorMsg =
            '[Studio] Échec HTTP ${response.statusCode} lors de l\'initiation Studio : ${response.body}';
        onLog?.call(errorMsg, isError: true);
        throw HttpException(errorMsg, uri: uri);
      }
    } catch (e) {
      if (e is! HttpException) {
        onLog?.call('[Studio] Erreur réseau lors de l\'initiation Studio : $e', isError: true);
      }
      rethrow;
    }
  }

  /// Alias de rétrocompatibilité créant et réservant la session auprès du backend.
  Future<bool> createStudioSession({
    String? id,
    required String deviceId,
    required String label,
    required double durationSec,
    int? sampleCount,
  }) async {
    await startStudioSession(
      deviceId: deviceId,
      label: label,
      durationSec: durationSec,
    );
    return true;
  }
}
