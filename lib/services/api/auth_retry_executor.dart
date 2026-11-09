import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../auth/auth_service.dart';
import '../auth/token_storage_service.dart';

typedef ApiLogCallback = void Function(String message, {bool isError});

/// Reusable executor that performs authenticated HTTP requests,
/// automatically handling token retrieval, 401 token refresh, and retry.
class AuthRetryExecutor {
  final TokenStorageService tokenStorage;
  final AuthService? authService;
  final Future<bool> Function()? refreshTokenFunction;
  final ApiLogCallback? onLog;

  const AuthRetryExecutor({
    required this.tokenStorage,
    this.authService,
    this.refreshTokenFunction,
    this.onLog,
  });

  /// Executes [requestFn] using an access token, automatically refreshing the token
  /// and retrying once if an HTTP 401 Unauthorized response is returned.
  Future<http.Response> execute({
    required Future<http.Response> Function(String token) requestFn,
    String? missingTokenMessage,
    bool clearTokensOnFailure = true,
  }) async {
    String? token = await tokenStorage.getAccessToken();

    if (token == null || token.trim().isEmpty) {
      final msg = missingTokenMessage ?? 'No access token available.';
      onLog?.call(msg, isError: true);
      throw HttpException(msg);
    }

    var response = await requestFn(token);

    if (response.statusCode == 401) {
      onLog?.call(
        'Access token expired (HTTP 401), attempting refresh...',
        isError: false,
      );

      bool refreshed = false;
      final refreshFn = refreshTokenFunction;
      final authSvc = authService;
      if (refreshFn != null) {
        refreshed = await refreshFn();
      } else if (authSvc != null) {
        refreshed = await authSvc.refreshToken();
      }

      if (refreshed) {
        token = await tokenStorage.getAccessToken();
        if (token != null && token.isNotEmpty) {
          response = await requestFn(token);
        }
      } else if (clearTokensOnFailure) {
        const msg = 'Failed to refresh authentication token: login required.';
        onLog?.call(msg, isError: true);
        await authService?.logout();
        await tokenStorage.clearTokens();
        throw const HttpException(msg);
      }
    }

    return response;
  }
}
