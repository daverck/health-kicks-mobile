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

    test('purgeOldRecords deletes synced records older than retention period but keeps unsynced ones', () async {
      final now = DateTime.now();
      final oldDate = now.subtract(const Duration(days: 100));
      final recentDate = now.subtract(const Duration(days: 10));

      final oldModel = StepDataModel(
        totalSteps: 3000,
        walkSteps: 3000,
        runSteps: 0,
        stairsSteps: 0,
        unclassifiedSteps: 0,
        cadenceSpm: 90,
        timestamp: oldDate,
      );

      final recentModel = StepDataModel(
        totalSteps: 4000,
        walkSteps: 4000,
        runSteps: 0,
        stairsSteps: 0,
        unclassifiedSteps: 0,
        cadenceSpm: 95,
        timestamp: recentDate,
      );

      // Record both
      await storageService.recordStepSnapshot(oldDate, oldModel);
      await storageService.recordStepSnapshot(recentDate, recentModel);

      // 1. Without syncing, purge should delete 0 records (preserves unsynced)
      final purgedUnsynced = await storageService.purgeOldRecords(retentionDays: 90);
      expect(purgedUnsynced, equals(0));

      // 2. Mark oldDate as synced
      final oldDateStr = "${oldDate.year}-${oldDate.month.toString().padLeft(2, '0')}-${oldDate.day.toString().padLeft(2, '0')}";
      await storageService.markDaysSynced([oldDateStr]);

      // 3. Purge should now delete oldDate records (4 activity entries: walk, run, stairs, unclassified)
      final purgedSynced = await storageService.purgeOldRecords(retentionDays: 90);
      expect(purgedSynced, equals(4));

      // Old date is gone
      final oldRecord = await storageService.getDailySteps(oldDate);
      expect(oldRecord, isNull);

      // Recent date is still present
      final recentRecord = await storageService.getDailySteps(recentDate);
      expect(recentRecord, isNotNull);
      expect(recentRecord!.totalSteps, equals(4000));
    });

    test('recordOdometerSnapshot continuous increments on the same day', () async {
      final now = DateTime(2026, 10, 11, 10, 0);

      // Snapshot 1: initial 15 steps
      final record1 = await storageService.recordOdometerSnapshot(
        deviceId: 'HK-2',
        date: now,
        rawModel: StepDataModel(
          totalSteps: 15,
          walkSteps: 10,
          runSteps: 5,
          stairsSteps: 0,
          unclassifiedSteps: 0,
          cadenceSpm: 80,
          timestamp: now,
        ),
      );
      expect(record1.totalSteps, equals(15));
      expect(record1.walkSteps, equals(10));
      expect(record1.runSteps, equals(5));

      // Snapshot 2: odometer grows to 37 steps (walk: +15, run: +5, stairs: +2)
      final record2 = await storageService.recordOdometerSnapshot(
        deviceId: 'HK-2',
        date: now.add(const Duration(minutes: 30)),
        rawModel: StepDataModel(
          totalSteps: 37,
          walkSteps: 25,
          runSteps: 10,
          stairsSteps: 2,
          unclassifiedSteps: 0,
          cadenceSpm: 95,
          timestamp: now.add(const Duration(minutes: 30)),
        ),
      );
      expect(record2.totalSteps, equals(37));
      expect(record2.walkSteps, equals(25));
      expect(record2.runSteps, equals(10));
      expect(record2.stairsSteps, equals(2));
      expect(record2.unclassifiedSteps, equals(0));

      // Verify database stored state
      final stored = await storageService.getDailySteps(now);
      expect(stored, isNotNull);
      expect(stored!.totalSteps, equals(37));
      expect(stored.isSynced, isFalse);
    });

    test('recordOdometerSnapshot midnight transition prevents step bleeding', () async {
      final day1 = DateTime(2026, 10, 11, 23, 50);
      final day2 = DateTime(2026, 10, 12, 0, 15);

      // Day 1: Odometer accumulates 100 steps
      final recDay1 = await storageService.recordOdometerSnapshot(
        deviceId: 'HK-2',
        date: day1,
        rawModel: StepDataModel(
          totalSteps: 100,
          walkSteps: 70,
          runSteps: 30,
          stairsSteps: 0,
          unclassifiedSteps: 0,
          cadenceSpm: 100,
          timestamp: day1,
        ),
      );
      expect(recDay1.totalSteps, equals(100));

      // Day 2 (after midnight): Odometer keeps growing monotonically to 130
      final recDay2 = await storageService.recordOdometerSnapshot(
        deviceId: 'HK-2',
        date: day2,
        rawModel: StepDataModel(
          totalSteps: 130,
          walkSteps: 90,
          runSteps: 40,
          stairsSteps: 0,
          unclassifiedSteps: 0,
          cadenceSpm: 105,
          timestamp: day2,
        ),
      );

      // Day 2 must only have net delta of 30 steps (20 walk, 10 run)
      expect(recDay2.totalSteps, equals(30));
      expect(recDay2.walkSteps, equals(20));
      expect(recDay2.runSteps, equals(10));

      // Day 1 must strictly remain at 100 steps
      final day1Stored = await storageService.getDailySteps(day1);
      expect(day1Stored, isNotNull);
      expect(day1Stored!.totalSteps, equals(100));
      expect(day1Stored.walkSteps, equals(70));
      expect(day1Stored.runSteps, equals(30));
    });

    test('recordOdometerSnapshot handles device reboot and reset', () async {
      final now = DateTime(2026, 10, 11, 14, 0);

      // Before reboot: Odometer at 200 steps
      await storageService.recordOdometerSnapshot(
        deviceId: 'HK-2',
        date: now,
        rawModel: StepDataModel(
          totalSteps: 200,
          walkSteps: 150,
          runSteps: 50,
          stairsSteps: 0,
          unclassifiedSteps: 0,
          cadenceSpm: 110,
          timestamp: now,
        ),
      );

      // Device reboots: monotonic odometer resets to 15 (walk: 10, run: 5)
      final recordAfterReboot = await storageService.recordOdometerSnapshot(
        deviceId: 'HK-2',
        date: now.add(const Duration(minutes: 10)),
        rawModel: StepDataModel(
          totalSteps: 15,
          walkSteps: 10,
          runSteps: 5,
          stairsSteps: 0,
          unclassifiedSteps: 0,
          cadenceSpm: 90,
          timestamp: now.add(const Duration(minutes: 10)),
        ),
      );

      // Total steps for today should be 200 + 15 = 215 steps
      expect(recordAfterReboot.totalSteps, equals(215));
      expect(recordAfterReboot.walkSteps, equals(160));
      expect(recordAfterReboot.runSteps, equals(55));
    });

    test('recordOdometerSnapshot initializes baseline from yesterday if odometer state missing', () async {
      final yesterday = DateTime(2026, 10, 10);
      final today = DateTime(2026, 10, 11);

      // Yesterday recorded 100 steps
      await storageService.recordStepSnapshot(
        yesterday,
        StepDataModel(
          totalSteps: 100,
          walkSteps: 60,
          runSteps: 30,
          stairsSteps: 10,
          unclassifiedSteps: 0,
          cadenceSpm: 90,
          timestamp: yesterday,
        ),
      );

      // First snapshot on today with fresh odometer state, hardware odometer is 125
      final todayRecord = await storageService.recordOdometerSnapshot(
        deviceId: 'HK-2',
        date: today,
        rawModel: StepDataModel(
          totalSteps: 125,
          walkSteps: 75,
          runSteps: 35,
          stairsSteps: 15,
          unclassifiedSteps: 0,
          cadenceSpm: 95,
          timestamp: today,
        ),
      );

      // Net delta today should be 125 - 100 = 25 (walk: 15, run: 5, stairs: 5)
      expect(todayRecord.totalSteps, equals(25));
      expect(todayRecord.walkSteps, equals(15));
      expect(todayRecord.runSteps, equals(5));
      expect(todayRecord.stairsSteps, equals(5));
    });

    test('recordOdometerSnapshot accumulates hourly steps and provides them in getUnsyncedDays', () async {
      final hour14 = DateTime(2026, 10, 19, 14, 30);
      final hour15 = DateTime(2026, 10, 19, 15, 15);

      // Snapshot at 14:30
      await storageService.recordOdometerSnapshot(
        deviceId: 'HK-HOURLY',
        date: hour14,
        rawModel: StepDataModel(
          totalSteps: 100,
          walkSteps: 70,
          runSteps: 30,
          stairsSteps: 0,
          unclassifiedSteps: 0,
          cadenceSpm: 100,
          timestamp: hour14,
        ),
      );

      // Snapshot at 15:15
      await storageService.recordOdometerSnapshot(
        deviceId: 'HK-HOURLY',
        date: hour15,
        rawModel: StepDataModel(
          totalSteps: 150,
          walkSteps: 110,
          runSteps: 40,
          stairsSteps: 0,
          unclassifiedSteps: 0,
          cadenceSpm: 105,
          timestamp: hour15,
        ),
      );

      // Check getHourlySteps
      final hourly = await storageService.getHourlySteps(hour14);
      expect(hourly.length, equals(4)); // 2 for hour 14 (walk 70, run 30), 2 for hour 15 (walk 40, run 10)

      final h14Walk = hourly.firstWhere((r) => r['hour'] == 14 && r['activity_type'] == 'walk');
      expect(h14Walk['step_count'], equals(70));
      final h14Run = hourly.firstWhere((r) => r['hour'] == 14 && r['activity_type'] == 'run');
      expect(h14Run['step_count'], equals(30));

      final h15Walk = hourly.firstWhere((r) => r['hour'] == 15 && r['activity_type'] == 'walk');
      expect(h15Walk['step_count'], equals(40));
      final h15Run = hourly.firstWhere((r) => r['hour'] == 15 && r['activity_type'] == 'run');
      expect(h15Run['step_count'], equals(10));

      // Check getUnsyncedDays includes hourly_steps
      final unsynced = await storageService.getUnsyncedDays();
      expect(unsynced.length, equals(1));
      final hourlyList = unsynced.first['hourly_steps'] as List<Map<String, dynamic>>;
      expect(hourlyList.length, equals(4));
    });
  });
}
