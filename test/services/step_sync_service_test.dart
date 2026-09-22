import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:healthkicks_mobile/models/step_data_model.dart';
import 'package:healthkicks_mobile/services/auth/token_storage_service.dart';
import 'package:healthkicks_mobile/services/local_storage/step_storage_service.dart';
import 'package:healthkicks_mobile/services/step_sync_service.dart';
import 'auth/token_storage_service_test.dart';

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
    });
  });
}

