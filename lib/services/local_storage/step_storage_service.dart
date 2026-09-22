import 'dart:async';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../models/step_data_model.dart';

/// Aggregated daily summary model.
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

  factory DailyStepRecord.fromMap(String dateStr, Map<String, int> activities, bool isSynced) {
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
}

/// Service managing offline persistent SQLite storage for daily step counts.
class StepStorageService {
  static const String tableName = 'local_daily_steps';
  static const String columnDate = 'date';
  static const String columnActivityType = 'activity_type';
  static const String columnStepCount = 'step_count';
  static const String columnSyncStatus = 'sync_status';

  Database? _db;
  final String? _inMemoryDbName;

  StepStorageService({String? inMemoryDbName, Database? database})
      : _inMemoryDbName = inMemoryDbName,
        _db = database;

  /// Lazy database initializer.
  Future<Database> get database async {
    if (_db != null && _db!.isOpen) {
      return _db!;
    }
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final inMem = _inMemoryDbName;
    if (inMem != null) {
      return await openDatabase(
        inMem,
        version: 1,
        onCreate: _onCreate,
      );
    }

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'healthkicks_steps.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableName (
        $columnDate TEXT NOT NULL,
        $columnActivityType TEXT NOT NULL,
        $columnStepCount INTEGER NOT NULL,
        $columnSyncStatus INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY ($columnDate, $columnActivityType)
      );
    ''');
  }

  String _formatDate(DateTime dt) {
    return DateFormat('yyyy-MM-dd').format(dt);
  }

  /// Records a snapshot of steps broken down by activity type.
  /// If values changed, resets sync_status to 0.
  Future<void> recordStepSnapshot(DateTime date, StepDataModel model) async {
    final db = await database;
    final dateStr = _formatDate(date);

    final activities = <String, int>{
      'walk': model.walkSteps,
      'run': model.runSteps,
      'stairs': model.stairsSteps,
      'unclassified': model.unclassifiedSteps,
    };

    await db.transaction((txn) async {
      for (final entry in activities.entries) {
        final existing = await txn.query(
          tableName,
          columns: [columnStepCount, columnSyncStatus],
          where: '$columnDate = ? AND $columnActivityType = ?',
          whereArgs: [dateStr, entry.key],
        );

        if (existing.isEmpty) {
          await txn.insert(
            tableName,
            {
              columnDate: dateStr,
              columnActivityType: entry.key,
              columnStepCount: entry.value,
              columnSyncStatus: 0,
            },
          );
        } else {
          final currentCount = existing.first[columnStepCount] as int;
          final currentSyncStatus = existing.first[columnSyncStatus] as int;

          if (currentCount != entry.value) {
            await txn.update(
              tableName,
              {
                columnStepCount: entry.value,
                columnSyncStatus: 0, // Reset to unsynced
              },
              where: '$columnDate = ? AND $columnActivityType = ?',
              whereArgs: [dateStr, entry.key],
            );
          } else if (currentSyncStatus == 0) {
            // Unchanged but still unsynced: keep 0
          }
        }
      }
    });
  }

  /// Retrieves list of days with unsynced activities formatted for backend sync.
  Future<List<Map<String, dynamic>>> getUnsyncedDays() async {
    final db = await database;
    final rows = await db.query(
      tableName,
      where: '$columnSyncStatus = 0',
      orderBy: '$columnDate ASC, $columnActivityType ASC',
    );

    if (rows.isEmpty) return [];

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final row in rows) {
      final date = row[columnDate] as String;
      final activity = row[columnActivityType] as String;
      final count = row[columnStepCount] as int;

      grouped.putIfAbsent(date, () => []).add({
        'activity_type': activity,
        'step_count': count,
      });
    }

    return grouped.entries.map((e) {
      return {
        'date': e.key,
        'activities': e.value,
      };
    }).toList();
  }

  /// Marks the specified dates as synced (sync_status = 1).
  Future<void> markDaysSynced(List<String> dates) async {
    if (dates.isEmpty) return;
    final db = await database;

    final placeholders = List.filled(dates.length, '?').join(',');
    await db.update(
      tableName,
      {columnSyncStatus: 1},
      where: '$columnDate IN ($placeholders)',
      whereArgs: dates,
    );
  }

  /// Retrieves totals and breakdown for a specific date.
  Future<DailyStepRecord?> getDailySteps(DateTime date) async {
    final db = await database;
    final dateStr = _formatDate(date);

    final rows = await db.query(
      tableName,
      where: '$columnDate = ?',
      whereArgs: [dateStr],
    );

    if (rows.isEmpty) return null;

    final activities = <String, int>{};
    bool allSynced = true;

    for (final row in rows) {
      final activity = row[columnActivityType] as String;
      final count = row[columnStepCount] as int;
      final syncStatus = row[columnSyncStatus] as int;

      activities[activity] = count;
      if (syncStatus == 0) {
        allSynced = false;
      }
    }

    return DailyStepRecord.fromMap(dateStr, activities, allSynced);
  }

  /// Retrieves step history for the last [days] days.
  Future<List<DailyStepRecord>> getHistory(int days) async {
    final db = await database;
    final now = DateTime.now();
    final startDate = now.subtract(Duration(days: days - 1));
    final startDateStr = _formatDate(startDate);

    final rows = await db.query(
      tableName,
      where: '$columnDate >= ?',
      whereArgs: [startDateStr],
      orderBy: '$columnDate DESC',
    );

    final Map<String, Map<String, int>> activitiesByDate = {};
    final Map<String, bool> syncStatusByDate = {};

    for (final row in rows) {
      final date = row[columnDate] as String;
      final activity = row[columnActivityType] as String;
      final count = row[columnStepCount] as int;
      final syncStatus = row[columnSyncStatus] as int;

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
      final dateStr = _formatDate(d);
      final acts = activitiesByDate[dateStr] ?? {'walk': 0, 'run': 0, 'stairs': 0, 'unclassified': 0};
      final isSynced = syncStatusByDate[dateStr] ?? true;

      history.add(DailyStepRecord.fromMap(dateStr, acts, isSynced));
    }

    return history;
  }

  /// Closes database connection.
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}
