import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';
import '../models/detection_event.dart';
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
    AuthService? authService,
    Future<bool> Function()? refreshTokenFunction,
    this.onLog,
  })  : _backendBaseUrl = (backendBaseUrl ?? AppConfig.backendBaseUrl).trim().replaceAll(RegExp(r'/+$'), ''),
        _httpClient = httpClient ?? http.Client(),
        _tokenStorage = tokenStorage ?? TokenStorageService(),
        _authService = authService,
        _refreshTokenFunction = refreshTokenFunction;

  String get backendBaseUrl => _backendBaseUrl;

  /// Fetches paginated detection events from `GET /api/v1/events/history`.
  Future<EventHistoryResponse> fetchEvents({
    int page = 1,
    int size = 20,
    String category = 'all',
    String? deviceId,
  }) async {
    String? token = await _tokenStorage.getAccessToken();

    final queryParams = <String, String>{
      'page': page.toString(),
      'size': size.toString(),
      if (category != 'all') 'category': category,
      if (deviceId != null && deviceId.isNotEmpty) 'device_id': deviceId,
    };

    final uri = Uri.parse('$_backendBaseUrl/api/v1/events/history').replace(
      queryParameters: queryParams,
    );

    Map<String, String> buildHeaders(String? currentToken) => {
          'Accept': 'application/json',
          if (currentToken != null && currentToken.isNotEmpty) 'Authorization': 'Bearer $currentToken',
        };

    try {
      var response = await _httpClient
          .get(
            uri,
            headers: buildHeaders(token),
          )
          .timeout(const Duration(seconds: 10));

      // Handle token renewal on HTTP 401
      if (response.statusCode == 401) {
        onLog?.call(
          '[Events] Access token expired (HTTP 401), attempting refresh...',
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
            response = await _httpClient
                .get(
                  uri,
                  headers: buildHeaders(token),
                )
                .timeout(const Duration(seconds: 10));
          }
        }
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map<String, dynamic>) {
          return EventHistoryResponse.fromJson(decoded, page: page, size: size);
        } else if (decoded is List) {
          final items = decoded.map((e) => DetectionEvent.fromJson(e as Map<String, dynamic>)).toList();
          return EventHistoryResponse(
            events: items,
            total: items.length,
            page: page,
            size: size,
            hasMore: items.length >= size,
          );
        }
        return EventHistoryResponse(events: [], total: 0, page: page, size: size, hasMore: false);
      } else if (response.statusCode == 404) {
        // Endpoint or empty collection
        return EventHistoryResponse(events: [], total: 0, page: page, size: size, hasMore: false);
      } else {
        final errorMsg = 'Erreur serveur (${response.statusCode}): ${response.body}';
        onLog?.call('[Events] $errorMsg', isError: true);
        throw HttpException(errorMsg, uri: uri);
      }
    } on SocketException catch (e) {
      final msg = 'Impossible de contacter le serveur backend ($e)';
      onLog?.call('[Events] $msg', isError: true);
      throw HttpException(msg, uri: uri);
    } on TimeoutException {
      const msg = 'Délai d\'attente dépassé lors de la récupération des événements';
      onLog?.call('[Events] $msg', isError: true);
      throw TimeoutException(msg);
    } catch (e) {
      if (e is HttpException || e is TimeoutException) rethrow;
      final msg = 'Erreur inattendue : $e';
      onLog?.call('[Events] $msg', isError: true);
      throw HttpException(msg, uri: uri);
    }
  }
}
