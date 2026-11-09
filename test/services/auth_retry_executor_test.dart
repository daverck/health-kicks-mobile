import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/services/api/auth_retry_executor.dart';
import 'package:healthkicks_mobile/services/auth/token_storage_service.dart';
import 'package:http/http.dart' as http;

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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthRetryExecutor', () {
    late TokenStorageService tokenStorage;

    setUp(() async {
      tokenStorage = TokenStorageService(storage: FakeFlutterSecureStorage());
      await tokenStorage.saveTokens(
        accessToken: 'initial-token',
        refreshToken: 'valid-refresh-token',
      );
    });

    test('executes successfully on first attempt when token is valid', () async {
      final executor = AuthRetryExecutor(tokenStorage: tokenStorage);
      final response = await executor.execute(
        requestFn: (token) async => http.Response('{"ok": true}', 200),
      );
      expect(response.statusCode, 200);
      expect(response.body, '{"ok": true}');
    });

    test('throws HttpException immediately if no token is stored', () async {
      await tokenStorage.clearTokens();
      final executor = AuthRetryExecutor(tokenStorage: tokenStorage);

      expect(
        () => executor.execute(
          requestFn: (token) async => http.Response('ok', 200),
          missingTokenMessage: 'Custom missing token',
        ),
        throwsA(isA<HttpException>().having(
          (e) => e.message,
          'message',
          'Custom missing token',
        )),
      );
    });

    test('refreshes token on 401 and replays request successfully', () async {
      int attempts = 0;
      final tokensUsed = <String>[];

      final executor = AuthRetryExecutor(
        tokenStorage: tokenStorage,
        refreshTokenFunction: () async {
          await tokenStorage.saveTokens(
            accessToken: 'refreshed-token',
            refreshToken: 'new-refresh-token',
          );
          return true;
        },
      );

      final response = await executor.execute(
        requestFn: (token) async {
          attempts++;
          tokensUsed.add(token);
          if (attempts == 1) {
            return http.Response('Unauthorized', 401);
          }
          return http.Response('Success', 200);
        },
      );

      expect(attempts, 2);
      expect(tokensUsed, ['initial-token', 'refreshed-token']);
      expect(response.statusCode, 200);
      expect(response.body, 'Success');
    });

    test('throws HttpException on failed refresh after 401', () async {
      final executor = AuthRetryExecutor(
        tokenStorage: tokenStorage,
        refreshTokenFunction: () async => false,
      );

      expect(
        () => executor.execute(
          requestFn: (token) async => http.Response('Unauthorized', 401),
        ),
        throwsA(isA<HttpException>().having(
          (e) => e.message,
          'message',
          contains('Failed to refresh authentication token'),
        )),
      );
    });
  });
}
