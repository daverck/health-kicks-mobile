import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Single item pending in the offline queue.
class OutboxItem {
  final int id;
  final String endpoint;
  final String method; // POST, PUT, PATCH
  final String payloadJson;
  final Map<String, String>? headers;
  final DateTime createdAt;
  final int retryCount;
  final String? lastError;

  const OutboxItem({
    required this.id,
    required this.endpoint,
    required this.method,
    required this.payloadJson,
    this.headers,
    required this.createdAt,
    required this.retryCount,
    this.lastError,
  });

  Map<String, dynamic> get payload {
    try {
      return jsonDecode(payloadJson) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  factory OutboxItem.fromMap(Map<String, dynamic> map) {
    Map<String, String>? parsedHeaders;
    if (map['headers'] != null && map['headers'] is String && (map['headers'] as String).isNotEmpty) {
      try {
        final decoded = jsonDecode(map['headers'] as String) as Map<String, dynamic>;
        parsedHeaders = decoded.map((k, v) => MapEntry(k, v.toString()));
      } catch (_) {}
    }

    return OutboxItem(
      id: map['id'] as int,
      endpoint: map['endpoint'] as String,
      method: map['method'] as String,
      payloadJson: map['payload'] as String,
      headers: parsedHeaders,
      createdAt: DateTime.parse(map['created_at'] as String),
      retryCount: map['retry_count'] as int? ?? 0,
      lastError: map['last_error'] as String?,
    );
  }
}

/// Persistent SQLite FIFO queue for telemetry, events and API payloads queued while offline.
class OfflineOutboxService {
  static const String tableName = 'offline_outbox_queue';
  static const int maxRetryThreshold = 5;

  Database? _db;
  final String? _inMemoryDbName;

  OfflineOutboxService({String? inMemoryDbName, Database? database})
      : _inMemoryDbName = inMemoryDbName,
        _db = database;

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) {
      return _db!;
    }
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    if (_inMemoryDbName != null) {
      return await openDatabase(
        _inMemoryDbName,
        version: 1,
        onCreate: _onCreate,
      );
    }
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'healthkicks_outbox.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        endpoint TEXT NOT NULL,
        method TEXT NOT NULL,
        payload TEXT NOT NULL,
        headers TEXT,
        created_at TEXT NOT NULL,
        retry_count INTEGER DEFAULT 0,
        last_error TEXT
      );
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_outbox_created_at ON $tableName (created_at ASC);
    ''');
  }

  /// Enqueue an outgoing HTTP request to be replayed when connection is restored.
  Future<int> enqueue({
    required String endpoint,
    required String method,
    required Map<String, dynamic> payload,
    Map<String, String>? headers,
  }) async {
    final db = await database;
    final row = {
      'endpoint': endpoint,
      'method': method.toUpperCase(),
      'payload': jsonEncode(payload),
      'headers': headers != null ? jsonEncode(headers) : null,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'retry_count': 0,
      'last_error': null,
    };
    return await db.insert(tableName, row);
  }

  /// Get pending items up to the specified limit, ordered by insertion time (FIFO).
  Future<List<OutboxItem>> getPendingItems({int limit = 50}) async {
    final db = await database;
    final results = await db.query(
      tableName,
      where: 'retry_count < ?',
      whereArgs: [maxRetryThreshold],
      orderBy: 'id ASC',
      limit: limit,
    );
    return results.map((m) => OutboxItem.fromMap(m)).toList();
  }

  /// Count the total number of items waiting to be processed.
  Future<int> getPendingCount() async {
    final db = await database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM $tableName WHERE retry_count < ?', [maxRetryThreshold]),
    );
    return count ?? 0;
  }

  /// Remove successfully dispatched item from queue.
  Future<void> markCompleted(int id) async {
    final db = await database;
    await db.delete(tableName, where: 'id = ?', whereArgs: [id]);
  }

  /// Increment retry count and store error on dispatch failure.
  Future<void> markFailed(int id, String error) async {
    final db = await database;
    await db.rawUpdate('''
      UPDATE $tableName 
      SET retry_count = retry_count + 1, last_error = ? 
      WHERE id = ?
    ''', [error, id]);
  }

  /// Delete items older than maxAge or items that exceeded max retries.
  Future<int> pruneExpired({Duration maxAge = const Duration(days: 7)}) async {
    final db = await database;
    final cutoff = DateTime.now().toUtc().subtract(maxAge).toIso8601String();
    return await db.delete(
      tableName,
      where: 'created_at < ? OR retry_count >= ?',
      whereArgs: [cutoff, maxRetryThreshold],
    );
  }

  /// Process the pending queue using the provided sender callback.
  /// Returns the number of items successfully delivered.
  Future<int> processQueue({
    required Future<bool> Function(OutboxItem item) sender,
    int batchSize = 25,
  }) async {
    final items = await getPendingItems(limit: batchSize);
    int successCount = 0;

    for (final item in items) {
      try {
        final success = await sender(item);
        if (success) {
          await markCompleted(item.id);
          successCount++;
        } else {
          await markFailed(item.id, 'Sender returned false');
        }
      } catch (e) {
        await markFailed(item.id, e.toString());
      }
    }
    return successCount;
  }

  /// Close database connection.
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}

