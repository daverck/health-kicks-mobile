import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'iot_credentials_model.dart';
import 'token_storage_service.dart';

typedef AuthLogCallback = void Function(String message, {bool isError});

/// Repository ensuring retrieval and in-memory caching of temporary
/// AWS STS credentials from the HealthKicks FastAPI backend API.
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

  /// Currently cached in-memory credentials (if valid).
  IoTCredentials? get currentCredentials =>
      (_cachedCredentials != null && !_cachedCredentials!.isExpired)
          ? _cachedCredentials
          : null;

  /// Resolves the current Bearer access token.
  Future<String?> _resolveAccessToken() async {
    if (authTokenProvider != null) {
      return await authTokenProvider!();
    }
    if (tokenStorage != null) {
      return await tokenStorage!.getAccessToken();
    }
    return null;
  }

  /// Retrieves valid AWS STS credentials.
  /// Reuses in-memory cache if available and not expired (5 min margin).
  /// If `deviceId` changes, cache is invalidated to obtain an appropriately scoped token.
  Future<IoTCredentials> fetchCredentials({
    String? deviceId,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _cachedCredentials != null &&
        !_cachedCredentials!.isExpired &&
        _lastCachedDeviceId == deviceId) {
      onLog?.call(
        '[STS] Reusing cached STS credentials (expires at ${_cachedCredentials!.expiration.toIso8601String()}).',
        isError: false,
      );
      return _cachedCredentials!;
    }

    // Automatic retrieval of encrypted access token
    final token = await _resolveAccessToken();
    if (token == null || token.trim().isEmpty) {
      const errMsg = 'Session expired or user not logged in: unable to obtain IoT STS credentials.';
      onLog?.call('[STS] $errMsg', isError: true);
      throw const HttpException(errMsg);
    }

    onLog?.call(
      '[STS] Requesting temporary STS credentials from backend (deviceId: ${deviceId ?? "auto"})...',
      isError: false,
    );

    // Backend URL normalization
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

      // Handle expired token (HTTP 401)
      if (response.statusCode == 401) {
        onLog?.call(
          '[STS] Access token expired (HTTP 401), attempting refresh...',
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

        // If refresh failed or server still returns 401
        if (response.statusCode == 401) {
          onLog?.call(
            '[STS] Session permanently expired (HTTP 401): logging out user to SSO login.',
            isError: true,
          );
          await authService?.logout();
          await tokenStorage?.clearTokens();
          const errorMsg =
              '[STS] HTTP 401 failure (token expired): user logged out for SSO re-authentication.';
          throw HttpException(errorMsg, uri: uri);
        }
      }

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final credentials = IoTCredentials.fromJson(data);
        _cachedCredentials = credentials;
        _lastCachedDeviceId = deviceId;

        onLog?.call(
          '[STS] New STS credentials obtained successfully (Expires at: ${credentials.expiration.toIso8601String()}, Region: ${credentials.region}).',
          isError: false,
        );
        return credentials;
      } else {
        final errorMsg =
            '[STS] HTTP ${response.statusCode} failure during token exchange: ${response.body}';
        onLog?.call(errorMsg, isError: true);
        throw HttpException(errorMsg, uri: uri);
      }
    } catch (e) {
      if (e is! HttpException) {
        onLog?.call('[STS] Network error during backend request: $e', isError: true);
      }
      rethrow;
    }
  }

  /// Manually clears the cache.
  void clearCache() {
    _cachedCredentials = null;
    _lastCachedDeviceId = null;
  }
}
