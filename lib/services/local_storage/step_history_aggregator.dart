import '../../models/daily_step_record.dart';

/// Aggregates and reshapes raw SQLite step rows into domain models and nested payload maps.
class StepHistoryAggregator {
  /// Aggregates database rows for a single date into a [DailyStepRecord].
  /// Returns null if [rows] is empty.
  static DailyStepRecord? aggregateSingleDay(
    String dateStr,
    List<Map<String, dynamic>> rows, {
    String activityColumn = 'activity_type',
    String countColumn = 'step_count',
    String syncColumn = 'sync_status',
  }) {
    if (rows.isEmpty) return null;

    final activities = <String, int>{};
    bool allSynced = true;

    for (final row in rows) {
      final activity = row[activityColumn] as String;
      final count = row[countColumn] as int;
      final syncStatus = row[syncColumn] as int;

      activities[activity] = count;
      if (syncStatus == 0) {
        allSynced = false;
      }
    }

    return DailyStepRecord.fromMap(dateStr, activities, allSynced);
  }

  /// Aggregates database rows for a range of [days] up to [now], filling missing days with zeroes.
  static List<DailyStepRecord> aggregateDailyHistory(
    List<Map<String, dynamic>> rows, {
    required DateTime now,
    required int days,
    required String Function(DateTime) formatDate,
    String dateColumn = 'date',
    String activityColumn = 'activity_type',
    String countColumn = 'step_count',
    String syncColumn = 'sync_status',
  }) {
    final Map<String, Map<String, int>> activitiesByDate = {};
    final Map<String, bool> syncStatusByDate = {};

    for (final row in rows) {
      final date = row[dateColumn] as String;
      final activity = row[activityColumn] as String;
      final count = row[countColumn] as int;
      final syncStatus = row[syncColumn] as int;

      activitiesByDate.putIfAbsent(date, () => {})[activity] = count;
      if (syncStatus == 0) {
        syncStatusByDate[date] = false;
      } else {
        syncStatusByDate.putIfAbsent(date, () => true);
      }
    }

    final List<DailyStepRecord> history = [];
    for (int i = 0; i < days; i++) {
      final d = now.subtract(Duration(days: i));
      final dateStr = formatDate(d);
      final acts = activitiesByDate[dateStr] ??
          {'walk': 0, 'run': 0, 'stairs': 0, 'unclassified': 0};
      final isSynced = syncStatusByDate[dateStr] ?? true;

      history.add(DailyStepRecord.fromMap(dateStr, acts, isSynced));
    }

    return history;
  }

  /// Groups hourly step rows by date into structured payload maps.
  static List<Map<String, dynamic>> groupHourlyStepsByDate(
    List<String> dates,
    List<Map<String, dynamic>> hourlyRows, {
    String dateColumn = 'date',
    String hourColumn = 'hour',
    String activityColumn = 'activity_type',
    String countColumn = 'step_count',
  }) {
    final Map<String, List<Map<String, dynamic>>> hourlyByDate = {};
    for (final row in hourlyRows) {
      final date = row[dateColumn] as String;
      hourlyByDate.putIfAbsent(date, () => []).add({
        'hour': row[hourColumn] as int,
        'activity_type': row[activityColumn] as String,
        'step_count': row[countColumn] as int,
      });
    }

    return dates.map((d) {
      return <String, dynamic>{
        'date': d,
        'hourly_steps': hourlyByDate[d] ?? <Map<String, dynamic>>[],
      };
    }).toList();
  }
}
