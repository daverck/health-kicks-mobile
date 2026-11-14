import 'dart:async';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../models/daily_step_record.dart';
import '../../models/step_data_model.dart';
import 'step_history_aggregator.dart';

export '../../models/daily_step_record.dart';

/// Service managing offline persistent SQLite storage for daily step counts.
class StepStorageService {
  static const String tableName = 'local_daily_steps';
  static const String tableNameHourly = 'local_hourly_steps';
  static const String columnDate = 'date';
  static const String columnHour = 'hour';
  static const String columnActivityType = 'activity_type';
  static const String columnStepCount = 'step_count';
  static const String columnSyncStatus = 'sync_status';

  Database? _db;
  final String? _inMemoryDbName;

  StepStorageService({this._inMemoryDbName, Database? database})
      : _db = database;

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

    // Ensure local_hourly_steps exists
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableNameHourly (
        $columnDate TEXT NOT NULL,
        $columnHour INTEGER NOT NULL,
        $columnActivityType TEXT NOT NULL,
        $columnStepCount INTEGER NOT NULL,
        $columnSyncStatus INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY ($columnDate, $columnHour, $columnActivityType)
      );
    ''');

    await _ensureIndexes(db);

    return db;
  }

  Future<void> _ensureIndexes(Database db) async {
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_local_daily_steps_sync_date
      ON $tableName ($columnSyncStatus, $columnDate);
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_local_hourly_steps_sync_date
      ON $tableNameHourly ($columnSyncStatus, $columnDate);
    ''');
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
      CREATE TABLE IF NOT EXISTS $tableNameHourly (
        $columnDate TEXT NOT NULL,
        $columnHour INTEGER NOT NULL,
        $columnActivityType TEXT NOT NULL,
        $columnStepCount INTEGER NOT NULL,
        $columnSyncStatus INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY ($columnDate, $columnHour, $columnActivityType)
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

      // Apply deltas to local_daily_steps and local_hourly_steps in a single SQLite batch
      final hour = date.hour;
      final batch = txn.batch();
      var hasBatchOps = false;
      for (final entry in deltas.entries) {
        final delta = entry.value;
        if (delta > 0) {
          hasBatchOps = true;
          batch.rawInsert(
            '''
            INSERT INTO $tableName ($columnDate, $columnActivityType, $columnStepCount, $columnSyncStatus)
            VALUES (?, ?, ?, 0)
            ON CONFLICT($columnDate, $columnActivityType)
            DO UPDATE SET $columnStepCount = $tableName.$columnStepCount + excluded.$columnStepCount,
                          $columnSyncStatus = 0
            ''',
            [dateStr, entry.key, delta],
          );
          batch.rawInsert(
            '''
            INSERT INTO $tableNameHourly ($columnDate, $columnHour, $columnActivityType, $columnStepCount, $columnSyncStatus)
            VALUES (?, ?, ?, ?, 0)
            ON CONFLICT($columnDate, $columnHour, $columnActivityType)
            DO UPDATE SET $columnStepCount = $tableNameHourly.$columnStepCount + excluded.$columnStepCount,
                          $columnSyncStatus = 0
            ''',
            [dateStr, hour, entry.key, delta],
          );
        }
      }
      if (hasBatchOps) {
        await batch.commit(noResult: true);
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
    final hour = date.hour;

    final activities = <String, int>{
      'walk': model.walkSteps,
      'run': model.runSteps,
      'stairs': model.stairsSteps,
      'unclassified': model.unclassifiedSteps,
    };

    final batch = db.batch();
    for (final entry in activities.entries) {
      batch.rawInsert(
        '''
        INSERT INTO $tableName ($columnDate, $columnActivityType, $columnStepCount, $columnSyncStatus)
        VALUES (?, ?, ?, 0)
        ON CONFLICT($columnDate, $columnActivityType) DO UPDATE SET
          $columnSyncStatus = CASE
            WHEN $tableName.$columnStepCount != excluded.$columnStepCount THEN 0
            ELSE $tableName.$columnSyncStatus
          END,
          $columnStepCount = excluded.$columnStepCount
        ''',
        [dateStr, entry.key, entry.value],
      );

      batch.rawInsert(
        '''
        INSERT INTO $tableNameHourly ($columnDate, $columnHour, $columnActivityType, $columnStepCount, $columnSyncStatus)
        VALUES (?, ?, ?, ?, 0)
        ON CONFLICT($columnDate, $columnHour, $columnActivityType) DO UPDATE SET
          $columnStepCount = excluded.$columnStepCount,
          $columnSyncStatus = 0
        ''',
        [dateStr, hour, entry.key, entry.value],
      );
    }
    await batch.commit(noResult: true);
  }

  /// Retrieves list of days with unsynced activities formatted for backend sync.
  Future<List<Map<String, dynamic>>> getUnsyncedDays() async {
    final db = await database;
    final rowsDaily = await db.query(
      tableName,
      columns: [columnDate],
      where: '$columnSyncStatus = 0',
      distinct: true,
    );
    final rowsHourly = await db.query(
      tableNameHourly,
      columns: [columnDate],
      where: '$columnSyncStatus = 0',
      distinct: true,
    );

    final Set<String> datesSet = {
      ...rowsDaily.map((r) => r[columnDate] as String),
      ...rowsHourly.map((r) => r[columnDate] as String),
    };

    if (datesSet.isEmpty) return [];

    final dates = datesSet.toList()..sort();
    final placeholders = List.filled(dates.length, '?').join(',');
    final hourlyRows = await db.query(
      tableNameHourly,
      where: '$columnDate IN ($placeholders)',
      whereArgs: dates,
      orderBy: '$columnDate ASC, $columnHour ASC, $columnActivityType ASC',
    );

    return StepHistoryAggregator.groupHourlyStepsByDate(dates, hourlyRows);
  }

  /// Marks the specified dates as synced (sync_status = 1) in both daily and hourly tables.
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
    await db.update(
      tableNameHourly,
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

    return StepHistoryAggregator.aggregateSingleDay(dateStr, rows);
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

    return StepHistoryAggregator.aggregateDailyHistory(
      rows,
      now: now,
      days: days,
      formatDate: _formatDate,
    );
  }

  /// Purges synced records older than [retentionDays] (default: 90 days).
  /// Unsynced records (sync_status = 0) are strictly preserved regardless of age.
  Future<int> purgeOldRecords({int retentionDays = 90}) async {
    final db = await database;
    final cutoffDate = DateTime.now().subtract(Duration(days: retentionDays));
    final cutoffDateStr = _formatDate(cutoffDate);

    await db.delete(
      tableNameHourly,
      where: '$columnDate < ? AND $columnSyncStatus = 1',
      whereArgs: [cutoffDateStr],
    );

    return await db.delete(
      tableName,
      where: '$columnDate < ? AND $columnSyncStatus = 1',
      whereArgs: [cutoffDateStr],
    );
  }

  /// Retrieves fine-grained hourly steps for a given date.
  Future<List<Map<String, dynamic>>> getHourlySteps(DateTime date) async {
    final db = await database;
    final dateStr = _formatDate(date);
    return await db.query(
      tableNameHourly,
      where: '$columnDate = ?',
      whereArgs: [dateStr],
      orderBy: '$columnHour ASC, $columnActivityType ASC',
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
