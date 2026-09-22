import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:healthkicks_mobile/models/step_data_model.dart';
import 'package:healthkicks_mobile/services/local_storage/step_storage_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('StepStorageService - SQLite Local Storage', () {
    late StepStorageService storageService;

    setUp(() async {
      storageService = StepStorageService(inMemoryDbName: inMemoryDatabasePath);
    });

    tearDown(() async {
      await storageService.close();
    });

    test('recordStepSnapshot saves walk, run, stairs, unclassified and marks unsynced', () async {
      final now = DateTime(2026, 9, 22);
      final model = StepDataModel(
        totalSteps: 6325,
        walkSteps: 4120,
        runSteps: 1850,
        stairsSteps: 310,
        unclassifiedSteps: 45,
        cadenceSpm: 110,
        timestamp: now,
      );

      await storageService.recordStepSnapshot(now, model);

      final record = await storageService.getDailySteps(now);
      expect(record, isNotNull);
      expect(record!.totalSteps, equals(6325));
      expect(record.walkSteps, equals(4120));
      expect(record.runSteps, equals(1850));
      expect(record.stairsSteps, equals(310));
      expect(record.unclassifiedSteps, equals(45));
      expect(record.isSynced, isFalse);

      final unsynced = await storageService.getUnsyncedDays();
      expect(unsynced.length, equals(1));
      expect(unsynced.first['date'], equals('2026-09-22'));
      final acts = unsynced.first['activities'] as List<Map<String, dynamic>>;
      expect(acts.length, equals(4));
    });

    test('markDaysSynced updates sync status to true', () async {
      final now = DateTime(2026, 9, 22);
      final model = StepDataModel(
        totalSteps: 100,
        walkSteps: 70,
        runSteps: 30,
        stairsSteps: 0,
        unclassifiedSteps: 0,
        cadenceSpm: 90,
        timestamp: now,
      );

      await storageService.recordStepSnapshot(now, model);
      expect((await storageService.getUnsyncedDays()).length, equals(1));

      await storageService.markDaysSynced(['2026-09-22']);
      expect((await storageService.getUnsyncedDays()).isEmpty, isTrue);

      final daily = await storageService.getDailySteps(now);
      expect(daily!.isSynced, isTrue);
    });

    test('getHistory returns populated records for N days', () async {
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));

      await storageService.recordStepSnapshot(
        yesterday,
        StepDataModel(
          totalSteps: 5000,
          walkSteps: 4000,
          runSteps: 1000,
          stairsSteps: 0,
          unclassifiedSteps: 0,
          cadenceSpm: 100,
          timestamp: yesterday,
        ),
      );

      final history = await storageService.getHistory(7);
      expect(history.length, equals(7));
      expect(history.any((r) => r.totalSteps == 5000), isTrue);
    });
  });
}

