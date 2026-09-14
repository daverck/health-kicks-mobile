import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service gérant la persistance chiffrée et sécurisée des jetons JWT d'authentification
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

  /// Sauvegarde les jetons d'accès et de rafraîchissement de façon chiffrée.
  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
  }) async {
    await _storage.write(key: _keyAccessToken, value: accessToken);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _storage.write(key: _keyRefreshToken, value: refreshToken);
    }
  }

  /// Récupère le jeton d'accès actuel.
  Future<String?> getAccessToken() async {
    return _storage.read(key: _keyAccessToken);
  }

  /// Récupère le jeton de rafraîchissement actuel.
  Future<String?> getRefreshToken() async {
    return _storage.read(key: _keyRefreshToken);
  }

  /// Supprime tous les jetons stockés (déconnexion).
  Future<void> clearTokens() async {
    await _storage.delete(key: _keyAccessToken);
    await _storage.delete(key: _keyRefreshToken);
  }

  /// Vérifie si un jeton d'accès est présent en mémoire chiffrée.
  Future<bool> hasValidToken() async {
    final token = await getAccessToken();
    return token != null && token.trim().isNotEmpty;
  }
}
