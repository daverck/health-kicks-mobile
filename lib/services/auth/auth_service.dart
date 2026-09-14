import 'dart:async';
import 'dart:convert';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
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

typedef UrlLauncherFunction = Future<bool> Function(Uri url, {LaunchMode mode});

/// Service d'authentification utilisateur via OAuth2/OIDC (Google, Azure SSO),
/// deep linking et persistance chiffrée des jetons JWT.
class AuthService extends ChangeNotifier {
  final TokenStorageService _tokenStorage;
  final http.Client _httpClient;
  final AppLinks _appLinks;
  final UrlLauncherFunction _launchUrl;
  String _backendBaseUrl;

  StreamSubscription<Uri>? _linkSubscription;

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
    AppLinks? appLinks,
    UrlLauncherFunction? urlLauncher,
  })  : _backendBaseUrl = backendBaseUrl,
        _tokenStorage = tokenStorage ?? TokenStorageService(),
        _httpClient = httpClient ?? http.Client(),
        _appLinks = appLinks ?? AppLinks(),
        _launchUrl = urlLauncher ?? launchUrl;

  String get backendBaseUrl => _backendBaseUrl;

  void updateBackendBaseUrl(String newUrl) {
    _backendBaseUrl = newUrl.trim();
    notifyListeners();
  }

  /// Initialisation de l'écoute des deep links pour le retour OAuth SSO.
  void initDeepLinks() {
    _linkSubscription?.cancel();
    try {
      _linkSubscription = _appLinks.uriLinkStream.listen(
        (uri) {
          handleDeepLink(uri);
        },
        onError: (err) {
          debugPrint('[AuthService] DeepLink error: $err');
        },
      );
    } catch (e) {
      debugPrint('[AuthService] Could not subscribe to deep link stream: $e');
    }
  }

  /// Initialisation silencieuse : vérifie si un token chiffré existe au démarrage
  /// et initialise le listener des deep links.
  Future<bool> initialize() async {
    initDeepLinks();

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

  /// Déclenche le flux SSO Google en ouvrant le navigateur externe
  /// vers l'endpoint backend d'initiation OAuth.
  Future<bool> signInWithGoogle() async {
    return _openSsoBrowser('/api/v1/auth/google/login?redirect=true');
  }

  /// Déclenche le flux SSO Microsoft / Azure en ouvrant le navigateur externe
  /// vers l'endpoint backend d'initiation OAuth.
  Future<bool> signInWithAzure() async {
    return _openSsoBrowser('/api/v1/auth/azure/login?redirect=true');
  }

  Future<bool> _openSsoBrowser(String path) async {
    _lastError = null;
    try {
      final uri = Uri.parse('$_sanitizedBaseUrl$path');
      final launched = await _launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        _lastError = 'Impossible d\'ouvrir le navigateur pour l\'authentification SSO';
        notifyListeners();
        return false;
      }
      return true;
    } catch (e) {
      _lastError = 'Erreur lors du lancement de l\'authentification SSO : $e';
      notifyListeners();
      return false;
    }
  }

  /// Traite l'URI reçue en Deep Link (scheme: healthkicks, host: auth, path: /callback).
  /// Extrait `access_token` et `refresh_token`, met à jour le stockage sécurisé
  /// et charge le profil utilisateur `/api/v1/auth/me`.
  Future<bool> handleDeepLink(Uri uri) async {
    if (uri.scheme != 'healthkicks' || uri.host != 'auth') {
      return false;
    }

    if (uri.queryParameters.containsKey('error')) {
      _lastError = uri.queryParameters['error_description'] ??
          uri.queryParameters['error'] ??
          'Échec d\'authentification OAuth';
      _state = AuthState.unauthenticated;
      notifyListeners();
      return false;
    }

    final accessToken = uri.queryParameters['access_token'];
    final refreshToken = uri.queryParameters['refresh_token'];

    if (accessToken == null || accessToken.isEmpty) {
      _lastError = 'Jeton d\'accès absent de la réponse SSO';
      _state = AuthState.unauthenticated;
      notifyListeners();
      return false;
    }

    _state = AuthState.loading;
    _lastError = null;
    notifyListeners();

    await _tokenStorage.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );

    // Tenter de charger le profil utilisateur
    try {
      final meUri = Uri.parse('$_sanitizedBaseUrl/api/v1/auth/me');
      final res = await _httpClient.get(
        meUri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Accept': 'application/json',
        },
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _currentUser = AuthUser.fromJson(data);
      }
    } catch (_) {
      // Ignorer l'erreur réseau ponctuelle pour la persistance du profil
    }

    _state = AuthState.authenticated;
    notifyListeners();
    return true;
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

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  String get _sanitizedBaseUrl {
    return _backendBaseUrl.endsWith('/')
        ? _backendBaseUrl.substring(0, _backendBaseUrl.length - 1)
        : _backendBaseUrl;
  }
}


