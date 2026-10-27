import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:app_links/app_links.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/app_config.dart';
import '../api/api_headers.dart';
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
  final String? uuid;
  final String? pseudonym;
  final String email;
  final String? name;
  final String? avatarUrl;
  final String role;
  final bool isActive;

  const AuthUser({
    required this.id,
    this.uuid,
    this.pseudonym,
    required this.email,
    this.name,
    this.avatarUrl,
    required this.role,
    this.isActive = true,
  });

  String get effectiveUserUuid =>
      (uuid != null && uuid!.isNotEmpty) ? uuid! : id.toString();

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as int,
      uuid: json['uuid'] as String?,
      pseudonym: json['pseudonym'] as String?,
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
  String? get currentUserId => _currentUser?.effectiveUserUuid ?? _tokenUserId;

  bool get isAdmin => _currentUser?.role.toLowerCase() == 'admin';
  bool get isClinician => _currentUser?.role.toLowerCase() == 'clinician';
  bool get canUseHitl => isAdmin || isClinician;

  String? _lastError;
  String? get lastError => _lastError;

  String? _pendingCodeVerifier;
  String? get pendingCodeVerifier => _pendingCodeVerifier;

  static const String _pkceCharset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  /// Generates a 64-character URL-safe PKCE code_verifier, stores it in
  /// [_pendingCodeVerifier], and returns it.
  String generatePkceVerifier() {
    final random = Random.secure();
    final verifier = List.generate(
      64,
      (_) => _pkceCharset[random.nextInt(_pkceCharset.length)],
    ).join();
    _pendingCodeVerifier = verifier;
    return verifier;
  }

  /// Computes the S256 PKCE code_challenge from [verifier].
  static String computePkceChallenge(String verifier) {
    return base64UrlEncode(sha256.convert(utf8.encode(verifier)).bytes).replaceAll('=', '');
  }

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
  TokenStorageService get tokenStorage => _tokenStorage;

  /// Retrieves the current access token from secure storage.
  Future<String?> getValidAccessToken() async {
    return _tokenStorage.getAccessToken();
  }

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
        headers: buildApiHeaders(token),
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
          final refreshedAccessToken = await _tokenStorage.getAccessToken();
          if (refreshedAccessToken != null) {
            await _fetchUserProfile(refreshedAccessToken);
          }
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
  /// to the backend OAuth initiation endpoint with PKCE S256:
  /// `<backendUrl>/api/v1/auth/google/login?redirect=true&code_challenge=...&code_challenge_method=S256`.
  Future<bool> signInWithGoogle({String? backendUrl}) async {
    final verifier = generatePkceVerifier();
    final challenge = computePkceChallenge(verifier);
    final baseUrl = buildApiUrl(googleLoginPath, customBackendUrl: backendUrl);
    final fullUrl = '$baseUrl&code_challenge=$challenge&code_challenge_method=S256';
    return _openSsoBrowser(fullUrl);
  }

  /// Triggers Microsoft / Azure SSO flow by opening the external browser
  /// to the backend OAuth initiation endpoint with PKCE S256:
  /// `<backendUrl>/api/v1/auth/azure/login?redirect=true&code_challenge=...&code_challenge_method=S256`.
  Future<bool> signInWithAzure({String? backendUrl}) async {
    final verifier = generatePkceVerifier();
    final challenge = computePkceChallenge(verifier);
    final baseUrl = buildApiUrl(azureLoginPath, customBackendUrl: backendUrl);
    final fullUrl = '$baseUrl&code_challenge=$challenge&code_challenge_method=S256';
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

  /// Exchanges a one-time authorization [ticket] and PKCE [codeVerifier]
  /// for access and refresh tokens via `POST /api/v1/auth/token/exchange`.
  Future<bool> exchangeTicketForTokens({
    required String ticket,
    String? codeVerifier,
  }) async {
    final resolvedVerifier = codeVerifier ?? _pendingCodeVerifier;
    _pendingCodeVerifier = null;

    _state = AuthState.loading;
    _lastError = null;
    notifyListeners();

    final uri = Uri.parse('$_sanitizedBaseUrl/api/v1/auth/token/exchange');
    final payload = <String, dynamic>{
      'ticket': ticket,
      if (resolvedVerifier != null) 'code_verifier': resolvedVerifier,
    };

    try {
      final response = await _httpClient.post(
        uri,
        headers: buildApiHeaders(null),
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final accessToken = data['access_token'] as String?;
        final refreshToken = data['refresh_token'] as String?;

        if (accessToken == null || accessToken.isEmpty) {
          _lastError = 'Access token missing from token exchange response';
          _state = AuthState.unauthenticated;
          notifyListeners();
          return false;
        }

        await _tokenStorage.saveTokens(
          accessToken: accessToken,
          refreshToken: refreshToken,
        );
        _tokenUserId = TokenStorageService.parseUserId(accessToken);

        if (data['user'] is Map<String, dynamic>) {
          _currentUser = AuthUser.fromJson(data['user'] as Map<String, dynamic>);
        } else {
          await _fetchUserProfile(accessToken);
        }

        _state = AuthState.authenticated;
        notifyListeners();
        return true;
      } else {
        _lastError = 'Token exchange failed (${response.statusCode})';
        _state = AuthState.unauthenticated;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _lastError = 'Error exchanging authorization ticket: $e';
      _state = AuthState.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  Future<void> _fetchUserProfile(String accessToken) async {
    try {
      final meUri = Uri.parse('$_sanitizedBaseUrl/api/v1/auth/me');
      final res = await _httpClient.get(
        meUri,
        headers: buildApiHeaders(accessToken),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        _currentUser = AuthUser.fromJson(data);
      }
    } catch (_) {
      // Ignore transient network errors for profile loading
    }
  }

  /// Processes URI received via Deep Link (scheme: healthkicks, host: auth, path: /callback).
  /// Exchanges one-time `ticket` (with PKCE `code_verifier`) or falls back to
  /// extracting `access_token` and `refresh_token`, updates secure storage
  /// and loads the user profile `/api/v1/auth/me`.
  Future<bool> handleDeepLink(Uri uri) async {
    if (uri.scheme != 'healthkicks' || uri.host != 'auth') {
      return false;
    }

    if (uri.queryParameters.containsKey('error')) {
      _lastError = uri.queryParameters['error_description'] ?? uri.queryParameters['error'] ?? 'OAuth authentication failed';
      _state = AuthState.unauthenticated;
      notifyListeners();
      return false;
    }

    final ticket = uri.queryParameters['ticket'];
    if (ticket == null || ticket.isEmpty) {
      _lastError = 'Authorization ticket missing from SSO response';
      _state = AuthState.unauthenticated;
      notifyListeners();
      return false;
    }

    return await exchangeTicketForTokens(
      ticket: ticket,
      codeVerifier: _pendingCodeVerifier,
    );
  }

  /// Automatic session refresh via `/api/v1/auth/refresh`.
  Future<bool> refreshToken() async {
    final rToken = await _tokenStorage.getRefreshToken();
    if (rToken == null || rToken.isEmpty) return false;

    final uri = Uri.parse('$_sanitizedBaseUrl/api/v1/auth/refresh');

    try {
      final response = await _httpClient.post(
        uri,
        headers: buildApiHeaders(null),
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

  /// Reloads the authenticated user's profile, for example after connectivity
  /// is restored while the app is already open.
  Future<bool> refreshCurrentUser() async {
    var accessToken = await _tokenStorage.getAccessToken();
    if (accessToken == null || accessToken.isEmpty) return false;

    try {
      var response = await _httpClient.get(
        Uri.parse('$_sanitizedBaseUrl/api/v1/auth/me'),
        headers: buildApiHeaders(accessToken),
      );

      if (response.statusCode == 401 && await refreshToken()) {
        accessToken = await _tokenStorage.getAccessToken();
        if (accessToken == null || accessToken.isEmpty) return false;
        response = await _httpClient.get(
          Uri.parse('$_sanitizedBaseUrl/api/v1/auth/me'),
          headers: buildApiHeaders(accessToken),
        );
      }

      if (response.statusCode != 200) {
        debugPrint(
          '[AuthService] Could not refresh user profile '
          '(${response.statusCode}).',
        );
        return false;
      }

      _currentUser = AuthUser.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
      _tokenUserId = _currentUser!.effectiveUserUuid;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[AuthService] Could not refresh user profile: $e');
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
