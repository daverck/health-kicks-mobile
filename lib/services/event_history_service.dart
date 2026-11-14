import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';
import '../models/detection_event.dart';
import 'api/api_headers.dart';
import 'api/auth_retry_executor.dart';
import 'auth/auth_service.dart';
import 'auth/token_storage_service.dart';

typedef EventHistoryLogCallback = void Function(String message, {bool isError});

/// Service responsible for fetching paginated detection events from the FastAPI backend API.
class EventHistoryService {
  final String _backendBaseUrl;
  final http.Client _httpClient;
  final TokenStorageService _tokenStorage;
  final AuthService? _authService;
  final Future<bool> Function()? _refreshTokenFunction;
  final EventHistoryLogCallback? onLog;

  EventHistoryService({
    String? backendBaseUrl,
    http.Client? httpClient,
    TokenStorageService? tokenStorage,
    this._authService,
    this._refreshTokenFunction,
    this.onLog,
  })  : _backendBaseUrl = (backendBaseUrl ?? AppConfig.backendBaseUrl).trim().replaceAll(RegExp(r'/+$'), ''),
        _httpClient = httpClient ?? http.Client(),
        _tokenStorage = tokenStorage ?? TokenStorageService();

  String get backendBaseUrl => _backendBaseUrl;

  /// Fetches paginated detection events from `GET /api/v1/events/history`.
  Future<EventHistoryResponse> fetchEvents({
    int page = 1,
    int size = 20,
    String category = 'all',
    String? deviceId,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'size': size.toString(),
      if (category != 'all') 'category': category,
      if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
    };

    final uri = Uri.parse('$_backendBaseUrl/api/v1/events/history').replace(
      queryParameters: queryParams,
    );

    Map<String, String> buildHeaders(String? currentToken) => buildApiHeaders(
          currentToken,
          extraHeaders: const {'Accept': 'application/json'},
        );

    try {
      final executor = AuthRetryExecutor(
        tokenStorage: _tokenStorage,
        authService: _authService,
        refreshTokenFunction: _refreshTokenFunction,
        onLog: (msg, {isError = false}) => onLog?.call('[Events] $msg', isError: isError),
      );

      final response = await executor.execute(
        clearTokensOnFailure: false,
        requestFn: (currentToken) => _httpClient
            .get(
              uri,
              headers: buildHeaders(currentToken),
            )
            .timeout(const Duration(seconds: 10)),
      );

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return _parseEventHistoryResponse(response, page: page, size: size);
      } else if (response.statusCode == 404) {
        // Endpoint or empty collection
        return EventHistoryResponse.empty(page: page, size: size);
      } else {
        final errorMsg = 'Erreur serveur (${response.statusCode}): ${response.body}';
        onLog?.call(errorMsg, isError: true);
        throw HttpException(errorMsg, uri: uri);
      }
    } on SocketException catch (e) {
      final msg = 'Impossible de contacter le serveur backend ($e)';
      onLog?.call(msg, isError: true);
      throw HttpException(msg, uri: uri);
    } on TimeoutException {
      const msg = 'Délai d\'attente dépassé lors de la récupération des événements';
      onLog?.call(msg, isError: true);
      throw TimeoutException(msg);
    } catch (e) {
      if (e is HttpException || e is TimeoutException) rethrow;
      final msg = 'Erreur inattendue : $e';
      onLog?.call(msg, isError: true);
      throw HttpException(msg, uri: uri);
    }
  }

  /// Parses JSON payloads (paginated object or array) into an [EventHistoryResponse].
  EventHistoryResponse _parseEventHistoryResponse(
    http.Response response, {
    required int page,
    required int size,
  }) {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map<String, dynamic>) {
      return EventHistoryResponse.fromJson(decoded, page: page, size: size);
    } else if (decoded is List) {
      final items = decoded
          .whereType<Map<String, dynamic>>()
          .map((e) => DetectionEvent.fromJson(e))
          .toList();
      return EventHistoryResponse(
        events: items,
        total: items.length,
        page: page,
        size: size,
        hasMore: items.length >= size,
      );
    }
    return EventHistoryResponse.empty(page: page, size: size);
  }
}

