import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/models/daily_step_record.dart';

void main() {
  group('DailyStepRecord', () {
    test('instantiates with explicit properties', () {
      const record = DailyStepRecord(
        date: '2026-11-09',
        totalSteps: 1200,
        walkSteps: 800,
        runSteps: 300,
        stairsSteps: 100,
        unclassifiedSteps: 0,
        isSynced: true,
      );

      expect(record.date, equals('2026-11-09'));
      expect(record.totalSteps, equals(1200));
      expect(record.walkSteps, equals(800));
      expect(record.runSteps, equals(300));
      expect(record.stairsSteps, equals(100));
      expect(record.unclassifiedSteps, equals(0));
      expect(record.isSynced, isTrue);
    });

    test('creates fromMap aggregating activity step counts correctly', () {
      final activities = {
        'walk': 450,
        'run': 150,
        'stairs': 50,
        'unclassified': 25,
      };

      final record = DailyStepRecord.fromMap('2026-11-08', activities, false);

      expect(record.date, equals('2026-11-08'));
      expect(record.walkSteps, equals(450));
      expect(record.runSteps, equals(150));
      expect(record.stairsSteps, equals(50));
      expect(record.unclassifiedSteps, equals(25));
      expect(record.totalSteps, equals(675));
      expect(record.isSynced, isFalse);
    });

    test('handles missing activity map keys in fromMap with default 0', () {
      final record = DailyStepRecord.fromMap('2026-11-07', {'walk': 100}, true);

      expect(record.totalSteps, equals(100));
      expect(record.walkSteps, equals(100));
      expect(record.runSteps, equals(0));
      expect(record.stairsSteps, equals(0));
      expect(record.unclassifiedSteps, equals(0));
    });

    test('converts toActivitiesMap properly', () {
      const record = DailyStepRecord(
        date: '2026-11-09',
        totalSteps: 550,
        walkSteps: 300,
        runSteps: 200,
        stairsSteps: 50,
        unclassifiedSteps: 0,
        isSynced: true,
      );

      final map = record.toActivitiesMap();
      expect(map['walk'], equals(300));
      expect(map['run'], equals(200));
      expect(map['stairs'], equals(50));
      expect(map['unclassified'], equals(0));
    });

    test('supports copyWith mutation', () {
      const record = DailyStepRecord(
        date: '2026-11-09',
        totalSteps: 500,
        walkSteps: 500,
        runSteps: 0,
        stairsSteps: 0,
        unclassifiedSteps: 0,
        isSynced: false,
      );

      final updated = record.copyWith(isSynced: true, totalSteps: 600);
      expect(updated.date, equals('2026-11-09'));
      expect(updated.totalSteps, equals(600));
      expect(updated.isSynced, isTrue);
      expect(record.isSynced, isFalse);
    });

    test('implements value equality and hashCode', () {
      const record1 = DailyStepRecord(
        date: '2026-11-09',
        totalSteps: 100,
        walkSteps: 100,
        runSteps: 0,
        stairsSteps: 0,
        unclassifiedSteps: 0,
        isSynced: true,
      );
      const record2 = DailyStepRecord(
        date: '2026-11-09',
        totalSteps: 100,
        walkSteps: 100,
        runSteps: 0,
        stairsSteps: 0,
        unclassifiedSteps: 0,
        isSynced: true,
      );
      const record3 = DailyStepRecord(
        date: '2026-11-09',
        totalSteps: 200,
        walkSteps: 200,
        runSteps: 0,
        stairsSteps: 0,
        unclassifiedSteps: 0,
        isSynced: true,
      );

      expect(record1, equals(record2));
      expect(record1.hashCode, equals(record2.hashCode));
      expect(record1, isNot(equals(record3)));
    });

    test('provides readable toString representation', () {
      const record = DailyStepRecord(
        date: '2026-11-09',
        totalSteps: 100,
        walkSteps: 100,
        runSteps: 0,
        stairsSteps: 0,
        unclassifiedSteps: 0,
        isSynced: true,
      );

      expect(record.toString(), contains('DailyStepRecord(date: 2026-11-09'));
    });
  });
}
