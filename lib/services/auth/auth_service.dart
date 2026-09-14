import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'token_storage_service.dart';

enum AuthState {
  initial,
  loading,
  authenticated,
  unauthenticated,
}

/// Modèle utilisateur authentifié côté application mobile.
class AuthUser {
  final int id;
  final String email;
  final String? name;
  final String? avatarUrl;
  final String role;
  final bool isActive;

  const AuthUser({
    required this.id,
    required this.email,
    this.name,
    this.avatarUrl,
    required this.role,
    this.isActive = true,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as int,
      email: json['email'] as String,
      name: json['name'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      role: json['role'] as String? ?? 'user',
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

/// Service d'authentification utilisateur avec gestion d'état, persistance chiffrée
/// et interactions avec l'API backend HealthKicks.
class AuthService extends ChangeNotifier {
  final TokenStorageService _tokenStorage;
  final http.Client _httpClient;
  String _backendBaseUrl;

  AuthState _state = AuthState.initial;
  AuthState get state => _state;

  AuthUser? _currentUser;
  AuthUser? get currentUser => _currentUser;

  String? _lastError;
  String? get lastError => _lastError;

  AuthService({
    required String backendBaseUrl,
    TokenStorageService? tokenStorage,
    http.Client? httpClient,
  })  : _backendBaseUrl = backendBaseUrl,
        _tokenStorage = tokenStorage ?? TokenStorageService(),
        _httpClient = httpClient ?? http.Client();

  String get backendBaseUrl => _backendBaseUrl;

  void updateBackendBaseUrl(String newUrl) {
    _backendBaseUrl = newUrl.trim();
    notifyListeners();
  }

  /// Initialisation silencieuse : vérifie si un token chiffré existe au démarrage.
  Future<bool> initialize() async {
    _state = AuthState.loading;
    notifyListeners();

    try {
      final hasToken = await _tokenStorage.hasValidToken();
      if (!hasToken) {
        _state = AuthState.unauthenticated;
        notifyListeners();
        return false;
      }

      // Valider le token auprès du backend (/me)
      final token = await _tokenStorage.getAccessToken();
      if (token == null) {
        _state = AuthState.unauthenticated;
        notifyListeners();
        return false;
      }

      final uri = Uri.parse('$_sanitizedBaseUrl/api/v1/auth/me');
      final response = await _httpClient.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _currentUser = AuthUser.fromJson(data);
        _state = AuthState.authenticated;
        notifyListeners();
        return true;
      } else if (response.statusCode == 401) {
        // Tenter un rafraîchissement si possible
        final refreshed = await refreshToken();
        if (refreshed) {
          _state = AuthState.authenticated;
          notifyListeners();
          return true;
        }
      }

      await _tokenStorage.clearTokens();
      _state = AuthState.unauthenticated;
      notifyListeners();
      return false;
    } catch (_) {
      // En mode hors-ligne : si un token existe, maintenir l'authentification locale
      final hasToken = await _tokenStorage.hasValidToken();
      if (hasToken) {
        _state = AuthState.authenticated;
        notifyListeners();
        return true;
      }
      _state = AuthState.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  /// Connexion via identifiants (Email / Mot de passe ou dev mock / login backend).
  Future<bool> loginWithCredentials({
    required String email,
    required String password,
  }) async {
    _state = AuthState.loading;
    _lastError = null;
    notifyListeners();

    final uri = Uri.parse('$_sanitizedBaseUrl/api/v1/auth/login');

    try {
      final response = await _httpClient.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'email': email.trim(),
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final accessToken = data['access_token'] as String;
        final refreshToken = data['refresh_token'] as String?;

        if (data.containsKey('user') && data['user'] is Map<String, dynamic>) {
          _currentUser = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
        }

        await _tokenStorage.saveTokens(
          accessToken: accessToken,
          refreshToken: refreshToken,
        );

        _state = AuthState.authenticated;
        notifyListeners();
        return true;
      } else {
        String msg = 'Identifiants invalides (${response.statusCode})';
        try {
          final errBody = jsonDecode(response.body) as Map<String, dynamic>;
          if (errBody.containsKey('detail')) {
            msg = errBody['detail'].toString();
          }
        } catch (_) {}
        _lastError = msg;
        _state = AuthState.unauthenticated;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _lastError = 'Erreur réseau de connexion : $e';
      _state = AuthState.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  /// Rafraîchissement automatique de la session via `/api/v1/auth/refresh`.
  Future<bool> refreshToken() async {
    final rToken = await _tokenStorage.getRefreshToken();
    if (rToken == null || rToken.isEmpty) return false;

    final uri = Uri.parse('$_sanitizedBaseUrl/api/v1/auth/refresh');

    try {
      final response = await _httpClient.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'refresh_token': rToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final newAccessToken = data['access_token'] as String;
        final newRefreshToken = data['refresh_token'] as String?;

        await _tokenStorage.saveTokens(
          accessToken: newAccessToken,
          refreshToken: newRefreshToken ?? rToken,
        );
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Déconnexion utilisateur.
  Future<void> logout() async {
    await _tokenStorage.clearTokens();
    _currentUser = null;
    _state = AuthState.unauthenticated;
    notifyListeners();
  }

  String get _sanitizedBaseUrl {
    return _backendBaseUrl.endsWith('/')
        ? _backendBaseUrl.substring(0, _backendBaseUrl.length - 1)
        : _backendBaseUrl;
  }
}
