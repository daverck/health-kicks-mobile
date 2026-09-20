import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service managing secure encrypted persistence of authentication JWT tokens
/// via flutter_secure_storage (Android Keystore / iOS Keychain).
class TokenStorageService {
  static const String _keyAccessToken = 'hk_access_token';
  static const String _keyRefreshToken = 'hk_refresh_token';

  final FlutterSecureStorage _storage;

  TokenStorageService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                resetOnError: true,
              ),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  /// Saves access and refresh tokens in encrypted storage.
  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    await _storage.write(key: _keyAccessToken, value: accessToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _storage.write(key: _keyRefreshToken, value: refreshToken);
    }
  }

  /// Retrieves the current access token.
  Future<String?> getAccessToken() async {
    return _storage.read(key: _keyAccessToken);
  }

  /// Retrieves the current refresh token.
  Future<String?> getRefreshToken() async {
    return _storage.read(key: _keyRefreshToken);
  }

  /// Clears all stored tokens (logout).
  Future<void> clearTokens() async {
    await _storage.delete(key: _keyAccessToken);
    await _storage.delete(key: _keyRefreshToken);
  }

  /// Checks if a valid access token is present in encrypted storage.
  Future<bool> hasValidToken() async {
    final token = await getAccessToken();
    return token != null && token.trim().isNotEmpty;
  }

  /// Extracts user ID ('sub') directly from the stored access token JWT payload.
  Future<String?> getUserIdFromToken() async {
    final token = await getAccessToken();
    if (token == null || token.trim().isEmpty) return null;
    return parseUserId(token);
  }

  /// Decodes JWT payload without cryptographic validation to extract the 'sub' claim.
  static String? parseUserId(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return null;
      final normalized = base64.normalize(parts[1]);
      final payloadBytes = base64Url.decode(normalized);
      final jsonMap = jsonDecode(utf8.decode(payloadBytes)) as Map<String, dynamic>;
      final sub = jsonMap['sub'];
      return sub?.toString();
    } catch (_) {
      return null;
    }
  }
}
