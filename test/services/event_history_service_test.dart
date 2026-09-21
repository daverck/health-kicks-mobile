import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/services/auth/token_storage_service.dart';
import 'package:healthkicks_mobile/services/event_history_notifier.dart';
import 'package:healthkicks_mobile/services/event_history_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFlutterSecureStorage fakeStorage;
  late TokenStorageService tokenStorage;

  setUp(() async {
    fakeStorage = FakeFlutterSecureStorage();
    tokenStorage = TokenStorageService(storage: fakeStorage);
    await tokenStorage.saveTokens(
      accessToken: 'valid_test_token_123',
      refreshToken: 'valid_refresh_token_456',
    );
  });

  group('EventHistoryService - REST Queries & Pagination', () {
    test('fetchEvents sends correct query params and Bearer token', () async {
      String? capturedAuthHeader;
      Uri? capturedUri;

      final mockClient = MockClient((request) async {
        capturedAuthHeader = request.headers['Authorization'];
        capturedUri = request.url;

        final responsePayload = {
          'items': [
            {
              'id': 'evt-1',
              'device_id': 'HK-2',
              'event_type': 'fall_detected',
              'severity': 'critical',
              'timestamp': '2026-09-20T12:00:00Z',
              'peak_impact_g': 2.8,
              'confidence': 0.95,
              'is_validated': true,
            }
          ],
          'total': 1,
          'has_more': false,
        };

        return http.Response(jsonEncode(responsePayload), 200, headers: {
          'content-type': 'application/json; charset=utf-8',
        });
      });

      final service = EventHistoryService(
        backendBaseUrl: 'https://test.healthkicks.org',
        httpClient: mockClient,
        tokenStorage: tokenStorage,
      );

      final response = await service.fetchEvents(page: 1, size: 20, category: 'falls', deviceId: 'HK-2');

      expect(capturedAuthHeader, 'Bearer valid_test_token_123');
      expect(capturedUri?.path, '/api/v1/events/history');
      expect(capturedUri?.queryParameters['page'], '1');
      expect(capturedUri?.queryParameters['size'], '20');
      expect(capturedUri?.queryParameters['category'], 'falls');
      expect(capturedUri?.queryParameters['device_id'], 'HK-2');
      expect(response.events.length, 1);
      expect(response.events.first.eventType, 'fall_detected');
    });

    test('fetchEvents handles 401 and refreshes token successfully', () async {
      int requestCount = 0;
      bool refreshCalled = false;

      final mockClient = MockClient((request) async {
        requestCount++;
        if (requestCount == 1) {
          return http.Response('{"detail": "Token expired"}', 401);
        }

        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'evt-retry',
                'event_type': 'walk',
                'timestamp': '2026-09-20T12:00:00Z',
              }
            ],
            'total': 1,
            'has_more': false,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = EventHistoryService(
        backendBaseUrl: 'https://test.healthkicks.org',
        httpClient: mockClient,
        tokenStorage: tokenStorage,
        refreshTokenFunction: () async {
          refreshCalled = true;
          await tokenStorage.saveTokens(
            accessToken: 'newly_refreshed_token_789',
            refreshToken: 'valid_refresh_token_456',
          );
          return true;
        },
      );

      final response = await service.fetchEvents(page: 1, size: 20);

      expect(refreshCalled, isTrue);
      expect(requestCount, 2);
      expect(response.events.length, 1);
      expect(response.events.first.id, 'evt-retry');
    });

    test('fetchEvents throws HttpException on HTTP 500 error', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final service = EventHistoryService(
        backendBaseUrl: 'https://test.healthkicks.org',
        httpClient: mockClient,
        tokenStorage: tokenStorage,
      );

      expect(
        () => service.fetchEvents(page: 1, size: 20),
        throwsA(isA<HttpException>()),
      );
    });
  });

  group('EventHistoryNotifier - State Management & Infinite Scroll', () {
    test('loadInitial and setCategory update events and filter correctly', () async {
      final mockClient = MockClient((request) async {
        final category = request.url.queryParameters['category'] ?? 'all';
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'evt-$category-1',
                'event_type': category == 'falls' ? 'fall_forward' : 'walk',
                'timestamp': '2026-09-20T12:00:00Z',
              }
            ],
            'total': 10,
            'has_more': true,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = EventHistoryService(
        backendBaseUrl: 'https://test.healthkicks.org',
        httpClient: mockClient,
        tokenStorage: tokenStorage,
      );

      final notifier = EventHistoryNotifier(service: service);

      expect(notifier.events, isEmpty);
      expect(notifier.isLoading, isFalse);

      await notifier.loadInitial();

      expect(notifier.events.length, 1);
      expect(notifier.events.first.id, 'evt-all-1');
      expect(notifier.hasMore, isTrue);

      // Switch category to falls
      await notifier.setCategory('falls');

      expect(notifier.selectedCategory, 'falls');
      expect(notifier.events.length, 1);
      expect(notifier.events.first.id, 'evt-falls-1');
    });

    test('loadMore appends next page items without duplicates', () async {
      final mockClient = MockClient((request) async {
        final page = request.url.queryParameters['page'] ?? '1';
        return http.Response(
          jsonEncode({
            'items': [
              {
                'id': 'evt-page-$page',
                'event_type': 'walk',
                'timestamp': '2026-09-20T12:00:00Z',
              }
            ],
            'total': 2,
            'has_more': page == '1',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = EventHistoryService(
        backendBaseUrl: 'https://test.healthkicks.org',
        httpClient: mockClient,
        tokenStorage: tokenStorage,
      );

      final notifier = EventHistoryNotifier(service: service);
      await notifier.loadInitial();

      expect(notifier.events.length, 1);
      expect(notifier.events.first.id, 'evt-page-1');
      expect(notifier.hasMore, isTrue);

      await notifier.loadMore();

      expect(notifier.events.length, 2);
      expect(notifier.events.last.id, 'evt-page-2');
      expect(notifier.hasMore, isFalse);
    });
  });
}
