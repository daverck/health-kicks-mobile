/// Aggregated daily summary model representing step count per activity.
class DailyStepRecord {
  final String date; // yyyy-MM-dd
  final int totalSteps;
  final int walkSteps;
  final int runSteps;
  final int stairsSteps;
  final int unclassifiedSteps;
  final bool isSynced;

  const DailyStepRecord({
    required this.date,
    required this.totalSteps,
    required this.walkSteps,
    required this.runSteps,
    required this.stairsSteps,
    required this.unclassifiedSteps,
    required this.isSynced,
  });

  /// Factory creating an aggregated daily step record from a map of activity names to counts.
  factory DailyStepRecord.fromMap(
    String dateStr,
    Map<String, int> activities,
    bool isSynced,
  ) {
    final walk = activities['walk'] ?? 0;
    final run = activities['run'] ?? 0;
    final stairs = activities['stairs'] ?? 0;
    final unclassified = activities['unclassified'] ?? 0;
    final total = walk + run + stairs + unclassified;

    return DailyStepRecord(
      date: dateStr,
      totalSteps: total,
      walkSteps: walk,
      runSteps: run,
      stairsSteps: stairs,
      unclassifiedSteps: unclassified,
      isSynced: isSynced,
    );
  }

  /// Converts the record to a map of activity names to step counts.
  Map<String, int> toActivitiesMap() {
    return {
      'walk': walkSteps,
      'run': runSteps,
      'stairs': stairsSteps,
      'unclassified': unclassifiedSteps,
    };
  }

  /// Returns a copy of this record with updated fields.
  DailyStepRecord copyWith({
    String? date,
    int? totalSteps,
    int? walkSteps,
    int? runSteps,
    int? stairsSteps,
    int? unclassifiedSteps,
    bool? isSynced,
  }) {
    return DailyStepRecord(
      date: date ?? this.date,
      totalSteps: totalSteps ?? this.totalSteps,
      walkSteps: walkSteps ?? this.walkSteps,
      runSteps: runSteps ?? this.runSteps,
      stairsSteps: stairsSteps ?? this.stairsSteps,
      unclassifiedSteps: unclassifiedSteps ?? this.unclassifiedSteps,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DailyStepRecord &&
          runtimeType == other.runtimeType &&
          date == other.date &&
          totalSteps == other.totalSteps &&
          walkSteps == other.walkSteps &&
          runSteps == other.runSteps &&
          stairsSteps == other.stairsSteps &&
          unclassifiedSteps == other.unclassifiedSteps &&
          isSynced == other.isSynced;

  @override
  int get hashCode =>
      date.hashCode ^
      totalSteps.hashCode ^
      walkSteps.hashCode ^
      runSteps.hashCode ^
      stairsSteps.hashCode ^
      unclassifiedSteps.hashCode ^
      isSynced.hashCode;

  @override
  String toString() {
    return 'DailyStepRecord(date: $date, total: $totalSteps, walk: $walkSteps, run: $runSteps, stairs: $stairsSteps, unclassified: $unclassifiedSteps, isSynced: $isSynced)';
  }
}
