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
    final Database db;
    if (inMem != null) {
      db = await openDatabase(
        inMem,
        version: 1,
        onCreate: _onCreate,
      );
    } else {
      final dbPath = await getDatabasesPath();
      final path = p.join(dbPath, 'healthkicks_steps.db');
      db = await openDatabase(
        path,
        version: 1,
        onCreate: _onCreate,
      );
    }

    // Ensure device_odometer_state exists for databases created before this migration
    await db.execute('''
      CREATE TABLE IF NOT EXISTS device_odometer_state (
        device_id TEXT PRIMARY KEY,
        last_date TEXT NOT NULL,
        raw_walk INTEGER NOT NULL,
        raw_run INTEGER NOT NULL,
        raw_stairs INTEGER NOT NULL,
        raw_unclassified INTEGER NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    return db;
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

    await db.execute('''
      CREATE TABLE IF NOT EXISTS device_odometer_state (
        device_id TEXT PRIMARY KEY,
        last_date TEXT NOT NULL,
        raw_walk INTEGER NOT NULL,
        raw_run INTEGER NOT NULL,
        raw_stairs INTEGER NOT NULL,
        raw_unclassified INTEGER NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
  }

  String _formatDate(DateTime dt) {
    return DateFormat('yyyy-MM-dd').format(dt);
  }

  /// Records a raw monotonic hardware odometer snapshot and calculates/accumulates net daily steps.
  /// Prevents monotonic hardware counters from bleeding across midnight or after device reboots.
  Future<DailyStepRecord> recordOdometerSnapshot({
    required String deviceId,
    required DateTime date,
    required StepDataModel rawModel,
  }) async {
    final db = await database;
    final dateStr = _formatDate(date);

    final rawActivities = <String, int>{
      'walk': rawModel.walkSteps,
      'run': rawModel.runSteps,
      'stairs': rawModel.stairsSteps,
      'unclassified': rawModel.unclassifiedSteps,
    };

    await db.transaction((txn) async {
      final existingStateRows = await txn.query(
        'device_odometer_state',
        where: 'device_id = ?',
        whereArgs: [deviceId],
      );

      final Map<String, int> deltas = {};

      if (existingStateRows.isEmpty) {
        // No prior odometer state stored for this device
        final todayRows = await txn.query(
          tableName,
          columns: [columnActivityType, columnStepCount],
          where: '$columnDate = ?',
          whereArgs: [dateStr],
        );

        final prevRows = await txn.query(
          tableName,
          columns: [columnDate, columnActivityType, columnStepCount],
          where: '$columnDate < ?',
          whereArgs: [dateStr],
          orderBy: '$columnDate DESC',
        );

        if (todayRows.isNotEmpty) {
          // Today already has recorded steps (e.g. restored from cloud),
          // establish baseline without adding duplicate delta.
          for (final entry in rawActivities.entries) {
            deltas[entry.key] = 0;
          }
        } else if (prevRows.isNotEmpty) {
          // Previous day exists. Use the most recent day's step counts as baseline.
          final mostRecentDate = prevRows.first[columnDate] as String;
          final prevDayRows = prevRows.where((r) => r[columnDate] == mostRecentDate).toList();
          final prevDayTotals = <String, int>{};
          for (final row in prevDayRows) {
            prevDayTotals[row[columnActivityType] as String] = row[columnStepCount] as int;
          }

          for (final entry in rawActivities.entries) {
            final prevVal = prevDayTotals[entry.key] ?? 0;
            final diff = entry.value - prevVal;
            deltas[entry.key] = diff > 0 ? diff : 0;
          }
        } else {
          // Fresh device / first use on day 1: delta is full raw count
          for (final entry in rawActivities.entries) {
            deltas[entry.key] = entry.value;
          }
        }
      } else {
        // Existing odometer state found
        final row = existingStateRows.first;
        final existingRaw = <String, int>{
          'walk': row['raw_walk'] as int,
          'run': row['raw_run'] as int,
          'stairs': row['raw_stairs'] as int,
          'unclassified': row['raw_unclassified'] as int,
        };

        for (final entry in rawActivities.entries) {
          final prev = existingRaw[entry.key] ?? 0;
          final current = entry.value;
          if (current < prev) {
            // Hardware device was rebooted or counter reset
            deltas[entry.key] = current;
          } else {
            deltas[entry.key] = current - prev;
          }
        }
      }

      // Apply deltas to local_daily_steps
      for (final entry in deltas.entries) {
        final delta = entry.value;
        if (delta > 0) {
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
                columnStepCount: delta,
                columnSyncStatus: 0,
              },
            );
          } else {
            final currentCount = existing.first[columnStepCount] as int;
            await txn.update(
              tableName,
              {
                columnStepCount: currentCount + delta,
                columnSyncStatus: 0, // Reset to unsynced
              },
              where: '$columnDate = ? AND $columnActivityType = ?',
              whereArgs: [dateStr, entry.key],
            );
          }
        }
      }

      // Upsert device_odometer_state
      final nowIso = DateTime.now().toUtc().toIso8601String();
      if (existingStateRows.isEmpty) {
        await txn.insert(
          'device_odometer_state',
          {
            'device_id': deviceId,
            'last_date': dateStr,
            'raw_walk': rawModel.walkSteps,
            'raw_run': rawModel.runSteps,
            'raw_stairs': rawModel.stairsSteps,
            'raw_unclassified': rawModel.unclassifiedSteps,
            'updated_at': nowIso,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } else {
        await txn.update(
          'device_odometer_state',
          {
            'last_date': dateStr,
            'raw_walk': rawModel.walkSteps,
            'raw_run': rawModel.runSteps,
            'raw_stairs': rawModel.stairsSteps,
            'raw_unclassified': rawModel.unclassifiedSteps,
            'updated_at': nowIso,
          },
          where: 'device_id = ?',
          whereArgs: [deviceId],
        );
      }
    });

    final record = await getDailySteps(date);
    return record ??
        DailyStepRecord(
          date: dateStr,
          totalSteps: 0,
          walkSteps: 0,
          runSteps: 0,
          stairsSteps: 0,
          unclassifiedSteps: 0,
          isSynced: true,
        );
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

  /// Purges synced records older than [retentionDays] (default: 90 days).
  /// Unsynced records (sync_status = 0) are strictly preserved regardless of age.
  Future<int> purgeOldRecords({int retentionDays = 90}) async {
    final db = await database;
    final cutoffDate = DateTime.now().subtract(Duration(days: retentionDays));
    final cutoffDateStr = _formatDate(cutoffDate);

    return await db.delete(
      tableName,
      where: '$columnDate < ? AND $columnSyncStatus = 1',
      whereArgs: [cutoffDateStr],
    );
  }

  /// Closes database connection.
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}
