import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:healthkicks_mobile/models/step_data_model.dart';
import 'package:healthkicks_mobile/services/auth/auth_service.dart';
import 'package:healthkicks_mobile/services/auth/token_storage_service.dart';
import 'package:healthkicks_mobile/services/local_storage/step_storage_service.dart';
import 'package:healthkicks_mobile/services/step_sync_service.dart';
import 'auth/token_storage_service_test.dart';

class FakeAuthService extends Fake implements AuthService {
  bool refreshCalled = false;
  final bool refreshResult;

  FakeAuthService({this.refreshResult = true});

  @override
  Future<bool> refreshToken() async {
    refreshCalled = true;
    return refreshResult;
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('StepSyncService - Cloud Synchronization', () {
    late StepStorageService storageService;
    late FakeFlutterSecureStorage fakeStorage;
    late TokenStorageService tokenStorage;

    setUp(() async {
      storageService = StepStorageService(inMemoryDbName: inMemoryDatabasePath);
      fakeStorage = FakeFlutterSecureStorage();
      await fakeStorage.write(key: 'hk_access_token', value: 'valid_token_123');
      tokenStorage = TokenStorageService(storage: fakeStorage);
    });

    tearDown(() async {
      await storageService.close();
    });

    test('syncPendingSteps sends POST /api/v1/steps/sync and marks days synced', () async {
      final now = DateTime(2026, 9, 22);
      await storageService.recordStepSnapshot(
        now,
        StepDataModel(
          totalSteps: 6325,
          walkSteps: 4120,
          runSteps: 1850,
          stairsSteps: 310,
          unclassifiedSteps: 45,
          cadenceSpm: 120,
          timestamp: now,
        ),
      );

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/steps/sync' && request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['device_id'], equals('HK-2'));
          expect(body['date'], equals('2026-09-22'));
          expect((body['activities'] as List).length, equals(4));

          return http.Response(jsonEncode({'status': 'success', 'synced': 1}), 200);
        }
        return http.Response('Not Found', 404);
      });

      final syncService = StepSyncService(
        storageService: storageService,
        tokenStorage: tokenStorage,
        backendBaseUrl: 'http://127.0.0.1:8000',
        httpClient: mockClient,
      );

      final success = await syncService.syncPendingSteps(deviceId: 'HK-2');
      expect(success, isTrue);

      final unsynced = await storageService.getUnsyncedDays();
      expect(unsynced.isEmpty, isTrue);

      syncService.dispose();
    });

    test('fetchTodaySteps successfully fetches and parses today step count', () async {
      final now = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(now);

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/steps/history' &&
            request.url.queryParameters['device_id'] == 'HK-2' &&
            request.url.queryParameters['days'] == '1' &&
            request.method == 'GET') {
          expect(request.headers['Authorization'], equals('Bearer valid_token_123'));
          return http.Response(
            jsonEncode({
              'device_id': 'HK-2',
              'from_date': todayStr,
              'to_date': todayStr,
              'history': [
                {
                  'date': todayStr,
                  'total_steps': 6325,
                  'by_activity': {
                    'walk': 4120,
                    'run': 1850,
                    'stairs': 310,
                    'unclassified': 45,
                  },
                },
              ],
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final syncService = StepSyncService(
        storageService: storageService,
        tokenStorage: tokenStorage,
        backendBaseUrl: 'http://127.0.0.1:8000',
        httpClient: mockClient,
      );

      final result = await syncService.fetchTodaySteps(deviceId: 'HK-2');
      expect(result, isNotNull);
      expect(result!.totalSteps, equals(6325));
      expect(result.walkSteps, equals(4120));
      expect(result.runSteps, equals(1850));
      expect(result.stairsSteps, equals(310));
      expect(result.unclassifiedSteps, equals(45));
      expect(result.cadenceSpm, equals(0));

      syncService.dispose();
    });

    test('fetchTodaySteps returns null when history is empty or date does not match today', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/steps/history') {
          return http.Response(
            jsonEncode({
              'device_id': 'HK-2',
              'from_date': '2020-01-01',
              'to_date': '2020-01-01',
              'history': [
                {
                  'date': '2020-01-01',
                  'total_steps': 100,
                  'by_activity': {'walk': 100},
                },
              ],
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final syncService = StepSyncService(
        storageService: storageService,
        tokenStorage: tokenStorage,
        backendBaseUrl: 'http://127.0.0.1:8000',
        httpClient: mockClient,
      );

      final result = await syncService.fetchTodaySteps(deviceId: 'HK-2');
      expect(result, isNull);

      syncService.dispose();
    });

    test('fetchTodaySteps returns null on HTTP error or network exception', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final syncService = StepSyncService(
        storageService: storageService,
        tokenStorage: tokenStorage,
        backendBaseUrl: 'http://127.0.0.1:8000',
        httpClient: mockClient,
      );

      final result = await syncService.fetchTodaySteps(deviceId: 'HK-2');
      expect(result, isNull);

      syncService.dispose();
    });

    test('fetchTodaySteps refreshes token on 401 and retries', () async {
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      int callCount = 0;
      final fakeAuth = FakeAuthService(refreshResult: true);

      final mockClient = MockClient((request) async {
        callCount++;
        if (callCount == 1) {
          return http.Response('Unauthorized', 401);
        }
        return http.Response(
          jsonEncode({
            'device_id': 'HK-2',
            'from_date': todayStr,
            'to_date': todayStr,
            'history': [
              {
                'date': todayStr,
                'total_steps': 500,
                'by_activity': {'walk': 500},
              },
            ],
          }),
          200,
        );
      });

      final syncService = StepSyncService(
        storageService: storageService,
        tokenStorage: tokenStorage,
        authService: fakeAuth,
        backendBaseUrl: 'http://127.0.0.1:8000',
        httpClient: mockClient,
      );

      final result = await syncService.fetchTodaySteps(deviceId: 'HK-2');
      expect(result, isNotNull);
      expect(result!.totalSteps, equals(500));
      expect(fakeAuth.refreshCalled, isTrue);
      expect(callCount, equals(2));

      syncService.dispose();
    });

    test('startPeriodicSync sets active device, default intervals and starts timer', () {
      final syncService = StepSyncService(
        storageService: storageService,
        tokenStorage: tokenStorage,
      );

      expect(syncService.isPeriodicRunning, isFalse);
      syncService.startPeriodicSync(deviceId: 'HK-TEST');

      expect(syncService.activeDeviceId, equals('HK-TEST'));
      expect(syncService.isForeground, isTrue);
      expect(syncService.foregroundInterval, equals(const Duration(minutes: 5)));
      expect(syncService.backgroundInterval, equals(const Duration(minutes: 30)));
      expect(syncService.isPeriodicRunning, isTrue);

      syncService.stopPeriodicSync();
      expect(syncService.isPeriodicRunning, isFalse);
      syncService.dispose();
    });

    test('setForegroundState updates state and reschedules timer', () {
      final syncService = StepSyncService(
        storageService: storageService,
        tokenStorage: tokenStorage,
      );

      syncService.startPeriodicSync(
        deviceId: 'HK-TEST',
        foregroundInterval: const Duration(minutes: 2),
        backgroundInterval: const Duration(minutes: 15),
      );

      expect(syncService.isForeground, isTrue);
      expect(syncService.foregroundInterval, equals(const Duration(minutes: 2)));

      syncService.setForegroundState(false);
      expect(syncService.isForeground, isFalse);
      expect(syncService.backgroundInterval, equals(const Duration(minutes: 15)));
      expect(syncService.isPeriodicRunning, isTrue);

      syncService.setForegroundState(true);
      expect(syncService.isForeground, isTrue);
      expect(syncService.isPeriodicRunning, isTrue);

      syncService.dispose();
      expect(syncService.isPeriodicRunning, isFalse);
    });

    test('flushImmediateSync uses activeDeviceId fallback', () async {
      final now = DateTime(2026, 9, 22);
      await storageService.recordStepSnapshot(
        now,
        StepDataModel(
          totalSteps: 100,
          walkSteps: 100,
          runSteps: 0,
          stairsSteps: 0,
          unclassifiedSteps: 0,
          cadenceSpm: 80,
          timestamp: now,
        ),
      );

      String? capturedDeviceId;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/steps/sync' && request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          capturedDeviceId = body['device_id'];
          return http.Response(jsonEncode({'status': 'success', 'synced': 1}), 200);
        }
        return http.Response('Not Found', 404);
      });

      final syncService = StepSyncService(
        storageService: storageService,
        tokenStorage: tokenStorage,
        backendBaseUrl: 'http://127.0.0.1:8000',
        httpClient: mockClient,
      );

      syncService.startPeriodicSync(deviceId: 'HK-ACTIVE-99');
      final result = await syncService.flushImmediateSync();

      expect(result, isTrue);
      expect(capturedDeviceId, equals('HK-ACTIVE-99'));

      syncService.dispose();
    });
  });
}
