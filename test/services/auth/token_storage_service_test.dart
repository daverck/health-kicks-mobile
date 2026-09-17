import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/services/auth/token_storage_service.dart';

class FakeFlutterSecureStorage implements FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value != null) {
      _data[key] = value;
    } else {
      _data.remove(key);
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _data[key];
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.clear();
  }

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return Map.from(_data);
  }

  @override
  Future<bool> containsKey({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _data.containsKey(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('TokenStorageService - Stockage chiffré des jetons', () {
    late FakeFlutterSecureStorage fakeStorage;
    late TokenStorageService service;

    setUp(() {
      fakeStorage = FakeFlutterSecureStorage();
      service = TokenStorageService(storage: fakeStorage);
    });

    test('hasValidToken renvoie false initialement', () async {
      expect(await service.hasValidToken(), isFalse);
      expect(await service.getAccessToken(), isNull);
      expect(await service.getRefreshToken(), isNull);
    });

    test('saveTokens persiste les jetons et hasValidToken devient true', () async {
      await service.saveTokens(
        accessToken: 'access_123',
        refreshToken: 'refresh_456',
      );

      expect(await service.hasValidToken(), isTrue);
      expect(await service.getAccessToken(), equals('access_123'));
      expect(await service.getRefreshToken(), equals('refresh_456'));
    });

    test('clearTokens supprime les jetons stockés', () async {
      await service.saveTokens(
        accessToken: 'access_123',
        refreshToken: 'refresh_456',
      );

      await service.clearTokens();

      expect(await service.hasValidToken(), isFalse);
      expect(await service.getAccessToken(), isNull);
      expect(await service.getRefreshToken(), isNull);
    });

    test('parseUserId extrait correctement le claim sub d\'un JWT', () {
      // {"sub":"42","email":"test@example.com"}
      const mockJwt = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI0MiIsImVtYWlsIjoidGVzdEBleGFtcGxlLmNvbSJ9.mockSignature';
      final userId = TokenStorageService.parseUserId(mockJwt);
      expect(userId, equals('42'));
    });

    test('parseUserId renvoie null pour un token invalide ou corrompu', () {
      expect(TokenStorageService.parseUserId('invalid_token'), isNull);
      expect(TokenStorageService.parseUserId('header.invalid-base64.sig'), isNull);
      expect(TokenStorageService.parseUserId(''), isNull);
    });

    test('getUserIdFromToken lit le token persistant et renvoie le userId', () async {
      const mockJwt = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMDgiLCJyb2xlIjoidXNlciJ9.mockSignature';
      await service.saveTokens(accessToken: mockJwt);

      final userId = await service.getUserIdFromToken();
      expect(userId, equals('108'));
    });
  });
}
