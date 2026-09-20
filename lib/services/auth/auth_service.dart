import 'dart:async';
import 'dart:convert';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/app_config.dart';
import 'token_storage_service.dart';

enum AuthState {
  initial,
  loading,
  authenticated,
  unauthenticated,
}

/// Authenticated user model on the mobile application side.
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

/// User authentication service via OAuth2/OIDC (Google, Azure SSO),
/// deep linking and encrypted JWT token persistence.
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

  String? _tokenUserId;
  String? get currentUserId => _currentUser?.id.toString() ?? _tokenUserId;

  String? _lastError;
  String? get lastError => _lastError;

  AuthService({
    String? backendBaseUrl,
    TokenStorageService? tokenStorage,
    http.Client? httpClient,
    AppLinks? appLinks,
    UrlLauncherFunction? urlLauncher,
  })  : _backendBaseUrl = (backendBaseUrl ?? AppConfig.backendBaseUrl).trim().replaceAll(RegExp(r'/+$'), ''),
        _tokenStorage = tokenStorage ?? TokenStorageService(),
        _httpClient = httpClient ?? http.Client(),
        _appLinks = appLinks ?? AppLinks(),
        _launchUrl = urlLauncher ?? launchUrl;

  String get backendBaseUrl => _backendBaseUrl;

  void updateBackendBaseUrl(String newUrl) {
    _backendBaseUrl = newUrl.trim().replaceAll(RegExp(r'/+$'), '');
    notifyListeners();
  }

  /// Initializes listening for deep links for OAuth SSO return.
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

  /// Silent initialization: checks if an encrypted token exists at startup
  /// and initializes the deep links listener.
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

      // Validate token with backend (/me)
      final token = await _tokenStorage.getAccessToken();
      if (token == null) {
        _tokenUserId = null;
        _state = AuthState.unauthenticated;
        notifyListeners();
        return false;
      }
      _tokenUserId = TokenStorageService.parseUserId(token);

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
        // Attempt refresh if possible
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
      // In offline mode: if token exists, preserve local authentication
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

  static const String googleLoginPath = '/api/v1/auth/google/login?redirect=true';
  static const String azureLoginPath = '/api/v1/auth/azure/login?redirect=true';

  /// Constructs the full URL of a backend endpoint by systematically normalizing
  /// trailing slashes on base URL and leading slash on path.
  String buildApiUrl(String endpointPath, {String? customBackendUrl}) {
    var base = (customBackendUrl ?? _backendBaseUrl).trim().replaceAll(RegExp(r'/+$'), '');
    var path = endpointPath.trim();
    if (!path.startsWith('/')) {
      path = '/$path';
    }
    return '$base$path';
  }

  /// Triggers Google SSO flow by opening the external browser
  /// to the backend OAuth initiation endpoint:
  /// `<backendUrl>/api/v1/auth/google/login?redirect=true`.
  Future<bool> signInWithGoogle({String? backendUrl}) async {
    final fullUrl = buildApiUrl(googleLoginPath, customBackendUrl: backendUrl);
    return _openSsoBrowser(fullUrl);
  }

  /// Triggers Microsoft / Azure SSO flow by opening the external browser
  /// to the backend OAuth initiation endpoint:
  /// `<backendUrl>/api/v1/auth/azure/login?redirect=true`.
  Future<bool> signInWithAzure({String? backendUrl}) async {
    final fullUrl = buildApiUrl(azureLoginPath, customBackendUrl: backendUrl);
    return _openSsoBrowser(fullUrl);
  }

  Future<bool> _openSsoBrowser(String fullUrl) async {
    _lastError = null;
    try {
      final uri = Uri.parse(fullUrl);
      final launched = await _launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        _lastError = 'Unable to open browser for SSO authentication';
        notifyListeners();
        return false;
      }
      return true;
    } catch (e) {
      _lastError = 'Error launching SSO authentication: $e';
      notifyListeners();
      return false;
    }
  }

  /// Processes URI received via Deep Link (scheme: healthkicks, host: auth, path: /callback).
  /// Extracts `access_token` and `refresh_token`, updates secure storage
  /// and loads the user profile `/api/v1/auth/me`.
  Future<bool> handleDeepLink(Uri uri) async {
    if (uri.scheme != 'healthkicks' || uri.host != 'auth') {
      return false;
    }

    if (uri.queryParameters.containsKey('error')) {
      _lastError = uri.queryParameters['error_description'] ??
          uri.queryParameters['error'] ??
          'OAuth authentication failed';
      _state = AuthState.unauthenticated;
      notifyListeners();
      return false;
    }

    final accessToken = uri.queryParameters['access_token'];
    final refreshToken = uri.queryParameters['refresh_token'];

    if (accessToken == null || accessToken.isEmpty) {
      _lastError = 'Access token missing from SSO response';
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
    _tokenUserId = TokenStorageService.parseUserId(accessToken);

    // Attempt to load user profile
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
      // Ignore transient network errors for profile loading
    }

    _state = AuthState.authenticated;
    notifyListeners();
    return true;
  }

  /// Automatic session refresh via `/api/v1/auth/refresh`.
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
        _tokenUserId = TokenStorageService.parseUserId(newAccessToken);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// User logout.
  Future<void> logout() async {
    await _tokenStorage.clearTokens();
    _currentUser = null;
    _tokenUserId = null;
    _state = AuthState.unauthenticated;
    notifyListeners();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  String get _sanitizedBaseUrl {
    return _backendBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  }
}


