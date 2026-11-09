import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/services/local_storage/step_history_aggregator.dart';

void main() {
  group('StepHistoryAggregator', () {
    test('aggregateSingleDay returns null on empty rows', () {
      final record = StepHistoryAggregator.aggregateSingleDay('2026-11-09', []);
      expect(record, isNull);
    });

    test('aggregateSingleDay aggregates activities and sync status correctly', () {
      final rows = [
        {'activity_type': 'walk', 'step_count': 1200, 'sync_status': 1},
        {'activity_type': 'run', 'step_count': 600, 'sync_status': 1},
        {'activity_type': 'stairs', 'step_count': 150, 'sync_status': 0},
      ];

      final record = StepHistoryAggregator.aggregateSingleDay('2026-11-09', rows);
      expect(record, isNotNull);
      expect(record!.date, equals('2026-11-09'));
      expect(record.walkSteps, equals(1200));
      expect(record.runSteps, equals(600));
      expect(record.stairsSteps, equals(150));
      expect(record.unclassifiedSteps, equals(0));
      expect(record.totalSteps, equals(1950));
      expect(record.isSynced, isFalse);
    });

    test('aggregateDailyHistory fills missing days with 0 counts', () {
      final rows = [
        {'date': '2026-11-09', 'activity_type': 'walk', 'step_count': 500, 'sync_status': 1},
        {'date': '2026-11-07', 'activity_type': 'run', 'step_count': 300, 'sync_status': 1},
      ];

      final now = DateTime(2026, 11, 9);
      final history = StepHistoryAggregator.aggregateDailyHistory(
        rows,
        now: now,
        days: 3,
        formatDate: (d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
      );

      expect(history.length, equals(3));
      // Day 0: 2026-11-09
      expect(history[0].date, equals('2026-11-09'));
      expect(history[0].walkSteps, equals(500));
      expect(history[0].totalSteps, equals(500));

      // Day 1: 2026-11-08 (missing in rows, zero-filled)
      expect(history[1].date, equals('2026-11-08'));
      expect(history[1].totalSteps, equals(0));
      expect(history[1].isSynced, isTrue);

      // Day 2: 2026-11-07
      expect(history[2].date, equals('2026-11-07'));
      expect(history[2].runSteps, equals(300));
      expect(history[2].totalSteps, equals(300));
    });

    test('groupHourlyStepsByDate groups hourly rows into dates payload maps', () {
      final hourlyRows = [
        {'date': '2026-11-09', 'hour': 8, 'activity_type': 'walk', 'step_count': 200},
        {'date': '2026-11-09', 'hour': 9, 'activity_type': 'run', 'step_count': 350},
        {'date': '2026-11-08', 'hour': 12, 'activity_type': 'walk', 'step_count': 100},
      ];

      final result = StepHistoryAggregator.groupHourlyStepsByDate(
        ['2026-11-08', '2026-11-09'],
        hourlyRows,
      );

      expect(result.length, equals(2));
      expect(result[0]['date'], equals('2026-11-08'));
      expect((result[0]['hourly_steps'] as List).length, equals(1));

      expect(result[1]['date'], equals('2026-11-09'));
      expect((result[1]['hourly_steps'] as List).length, equals(2));
    });
  });
}
