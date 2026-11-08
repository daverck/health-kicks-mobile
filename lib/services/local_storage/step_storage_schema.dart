import 'package:sqflite/sqflite.dart';

/// SQLite Schema and Table definitions for Step and Odometer Storage.
class StepStorageSchema {
  static const String tableDailySteps = 'local_daily_steps';
  static const String tableHourlySteps = 'local_hourly_steps';
  static const String tableOdometerState = 'device_odometer_state';

  static const String columnDate = 'date';
  static const String columnHour = 'hour';
  static const String columnActivityType = 'activity_type';
  static const String columnStepCount = 'step_count';
  static const String columnSyncStatus = 'sync_status';

  /// Creates default database tables and indexes.
  static Future<void> createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableDailySteps (
        $columnDate TEXT NOT NULL,
        $columnActivityType TEXT NOT NULL,
        $columnStepCount INTEGER NOT NULL,
        $columnSyncStatus INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY ($columnDate, $columnActivityType)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableHourlySteps (
        $columnDate TEXT NOT NULL,
        $columnHour INTEGER NOT NULL,
        $columnActivityType TEXT NOT NULL,
        $columnStepCount INTEGER NOT NULL,
        PRIMARY KEY ($columnDate, $columnHour, $columnActivityType)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableOdometerState (
        device_id TEXT PRIMARY KEY,
        last_date TEXT NOT NULL,
        raw_walk INTEGER NOT NULL,
        raw_run INTEGER NOT NULL,
        raw_stairs INTEGER NOT NULL,
        raw_unclassified INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_status 
      ON $tableDailySteps($columnSyncStatus)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_hourly_date 
      ON $tableHourlySteps($columnDate)
    ''');
  }

  /// Ensures legacy databases have the odometer state table.
  static Future<void> ensureOdometerTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableOdometerState (
        device_id TEXT PRIMARY KEY,
        last_date TEXT NOT NULL,
        raw_walk INTEGER NOT NULL,
        raw_run INTEGER NOT NULL,
        raw_stairs INTEGER NOT NULL,
        raw_unclassified INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }
}
