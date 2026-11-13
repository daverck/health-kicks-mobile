import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Single item pending in the persistent offline queue.
///
/// Encapsulates the HTTP target, method, serialized payload, optional headers,
/// retry counters, backoff timestamps, and the last failure message for telemetry or REST payloads
/// buffered while the mobile device is offline or unreachable.
class OutboxItem {
  /// Unique auto-increment primary key in the SQLite outbox table.
  final int id;

  /// Target REST endpoint or route (e.g. `/api/v1/steps/snapshot`).
  final String endpoint;

  /// HTTP verb (e.g. `POST`, `PUT`, `PATCH`).
  final String method;

  /// Serialized JSON string of the request body.
  final String payloadJson;

  /// Optional HTTP headers attached to the payload (e.g. idempotency keys, auth headers).
  final Map<String, String>? headers;

  /// Timestamp in UTC when the outbox record was enqueued.
  final DateTime createdAt;

  /// Number of unsuccessful dispatch attempts made so far.
  final int retryCount;

  /// Timestamp in UTC before which this item must NOT be retried (exponential backoff).
  final DateTime? nextRetryAt;

  /// Error message or exception string from the most recent failed dispatch attempt.
  final String? lastError;

  const OutboxItem({
    required this.id,
    required this.endpoint,
    required this.method,
    required this.payloadJson,
    this.headers,
    required this.createdAt,
    required this.retryCount,
    this.nextRetryAt,
    this.lastError,
  });

  /// Decodes and returns [payloadJson] as a dynamic map.
  /// Returns an empty map if JSON parsing fails.
  Map<String, dynamic> get payload {
    try {
      return jsonDecode(payloadJson) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// Deserializes an [OutboxItem] instance from an SQLite row map.
  factory OutboxItem.fromMap(Map<String, dynamic> map) {
    return OutboxItem(
      id: map['id'] as int,
      endpoint: map['endpoint'] as String,
      method: map['method'] as String,
      payloadJson: map['payload'] as String,
      headers: _parseHeaders(map['headers']),
      createdAt: _parseDateTime(map['created_at']) ?? DateTime.now().toUtc(),
      retryCount: map['retry_count'] as int? ?? 0,
      nextRetryAt: _parseDateTime(map['next_retry_at']),
      lastError: map['last_error'] as String?,
    );
  }

  static Map<String, String>? _parseHeaders(dynamic raw) {
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        return decoded.map((k, v) => MapEntry(k, v.toString()));
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static DateTime? _parseDateTime(dynamic raw) {
    if (raw is String && raw.isNotEmpty) {
      try {
        return DateTime.parse(raw);
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

/// Persistent SQLite FIFO queue for telemetry, events, and API payloads queued while offline.
///
/// ### Architecture & Guarantees
/// - **At-Least-Once Delivery**: Items remain in SQLite until explicitly confirmed as dispatched
///   via [markCompleted] or [processQueue].
/// - **Poison Pill Mitigation**: Items exceeding [maxRetryThreshold] (5 attempts) are automatically
///   excluded from pending batch queries to prevent head-of-line blocking.
/// - **Automated Expiry Pruning**: [pruneExpired] removes stale records older than the specified
///   retention period (default 7 days) and poisoned records.
/// - **Thread-Safe & Testable**: Supports both persistent disk SQLite files (`healthkicks_outbox.db`)
///   and in-memory databases (`inMemoryDbName`) for hermetic unit testing.
class OfflineOutboxService {
  /// Name of the SQLite table storing outbox messages.
  static const String tableName = 'offline_outbox_queue';

  /// Maximum retry attempts before an item is marked poisoned and excluded from active queries.
  static const int maxRetryThreshold = 5;

  Database? _db;
  Future<Database>? _dbInitFuture;
  Future<int>? _activeProcessFuture;
  final String? _inMemoryDbName;

  /// Base backoff duration before the first retry (default: 2 seconds).
  final Duration baseBackoff;

  /// Maximum backoff delay cap between retries (default: 5 minutes).
  final Duration maxBackoff;

  OfflineOutboxService({
    String? inMemoryDbName,
    Database? database,
    this.baseBackoff = const Duration(seconds: 2),
    this.maxBackoff = const Duration(minutes: 5),
  })  : _inMemoryDbName = inMemoryDbName,
        _db = database;

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) {
      return _db!;
    }
    _dbInitFuture ??= _initDatabase();
    try {
      _db = await _dbInitFuture!;
      return _db!;
    } finally {
      _dbInitFuture = null;
    }
  }

  Future<Database> _initDatabase() async {
    Database db;
    if (_inMemoryDbName != null) {
      db = await openDatabase(
        _inMemoryDbName,
        version: 1,
        onCreate: _onCreate,
      );
    } else {
      final dbPath = await getDatabasesPath();
      final path = p.join(dbPath, 'healthkicks_outbox.db');
      db = await openDatabase(
        path,
        version: 1,
        onCreate: _onCreate,
      );
    }

    // Migration safety: Ensure next_retry_at column exists in case db existed
    try {
      await db.execute('ALTER TABLE $tableName ADD COLUMN next_retry_at TEXT;');
    } catch (_) {
      // Column already exists or table freshly created
    }

    return db;
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
        next_retry_at TEXT,
        last_error TEXT
      );
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_outbox_created_at ON $tableName (created_at ASC);
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_outbox_retry_lookup ON $tableName (retry_count, next_retry_at);
    ''');
  }

  /// Calculates the exponential backoff delay based on the current retry count:
  /// delay = min(maxBackoff, baseBackoff * 2^(retryCount))
  Duration calculateBackoffDelay(int retryCount) {
    final multiplier = math.pow(2, math.min(retryCount, 30)).toInt();
    final delayInSeconds = baseBackoff.inSeconds * multiplier;
    if (delayInSeconds >= maxBackoff.inSeconds || delayInSeconds < 0) {
      return maxBackoff;
    }
    return Duration(seconds: delayInSeconds);
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
      'next_retry_at': null,
      'last_error': null,
    };
    return await db.insert(tableName, row);
  }

  /// Builds the parameterized SQL WHERE clause and arguments for pending outbox items.
  ({String clause, List<Object?> args}) _buildPendingFilter({
    DateTime? now,
    bool includeScheduled = false,
  }) {
    if (includeScheduled) {
      return (
        clause: 'retry_count < ?',
        args: [maxRetryThreshold],
      );
    }
    final nowIso = (now?.toUtc() ?? DateTime.now().toUtc()).toIso8601String();
    return (
      clause: 'retry_count < ? AND (next_retry_at IS NULL OR next_retry_at <= ?)',
      args: [maxRetryThreshold, nowIso],
    );
  }

  /// Get pending items up to the specified limit, ordered by insertion time (FIFO).
  /// By default, filters out items whose [nextRetryAt] is scheduled in the future unless [includeScheduled] is true.
  Future<List<OutboxItem>> getPendingItems({
    int limit = 50,
    DateTime? now,
    bool includeScheduled = false,
  }) async {
    final db = await database;
    final filter = _buildPendingFilter(now: now, includeScheduled: includeScheduled);

    final results = await db.query(
      tableName,
      where: filter.clause,
      whereArgs: filter.args,
      orderBy: 'id ASC',
      limit: limit,
    );
    return results.map((m) => OutboxItem.fromMap(m)).toList();
  }

  /// Count the total number of items waiting to be processed.
  /// If [includeScheduled] is true, includes items currently in backoff delay.
  Future<int> getPendingCount({DateTime? now, bool includeScheduled = false}) async {
    final db = await database;
    final filter = _buildPendingFilter(now: now, includeScheduled: includeScheduled);

    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM $tableName WHERE ${filter.clause}', filter.args),
    );
    return count ?? 0;
  }

  /// Retrieve a specific item by its [id], or null if not found.
  Future<OutboxItem?> getItem(int id) async {
    final db = await database;
    final results = await db.query(tableName, where: 'id = ?', whereArgs: [id], limit: 1);
    if (results.isEmpty) return null;
    return OutboxItem.fromMap(results.first);
  }

  /// Remove successfully dispatched item from queue.
  Future<void> markCompleted(int id) async {
    final db = await database;
    await db.delete(tableName, where: 'id = ?', whereArgs: [id]);
  }

  /// Increment retry count, compute next exponential backoff timestamp, and store error.
  Future<void> markFailed(int id, String error, {DateTime? now}) async {
    final db = await database;
    final currentTime = now?.toUtc() ?? DateTime.now().toUtc();

    final rows = await db.query(tableName, columns: ['retry_count'], where: 'id = ?', whereArgs: [id]);
    final currentRetries = rows.isNotEmpty ? (rows.first['retry_count'] as int? ?? 0) : 0;
    final delay = calculateBackoffDelay(currentRetries);
    final nextRetryAt = currentTime.add(delay).toIso8601String();
    final nextRetries = currentRetries + 1;

    await db.rawUpdate('''
      UPDATE $tableName 
      SET retry_count = ?, next_retry_at = ?, last_error = ? 
      WHERE id = ?
    ''', [nextRetries, nextRetryAt, error, id]);
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
  /// Concurrent invocations are serialized/coalesced to prevent duplicate item dispatch.
  Future<int> processQueue({
    required Future<bool> Function(OutboxItem item) sender,
    int batchSize = 25,
    DateTime? now,
  }) async {
    if (_activeProcessFuture != null) {
      return _activeProcessFuture!;
    }
    final future = _processQueueInternal(
      sender: sender,
      batchSize: batchSize,
      now: now,
    );
    _activeProcessFuture = future;
    try {
      return await future;
    } finally {
      _activeProcessFuture = null;
    }
  }

  Future<int> _processQueueInternal({
    required Future<bool> Function(OutboxItem item) sender,
    required int batchSize,
    DateTime? now,
  }) async {
    final items = await getPendingItems(limit: batchSize, now: now);
    int successCount = 0;

    for (final item in items) {
      try {
        final success = await sender(item);
        if (success) {
          await markCompleted(item.id);
          successCount++;
        } else {
          await markFailed(item.id, 'Sender returned false', now: now);
        }
      } catch (e) {
        await markFailed(item.id, e.toString(), now: now);
      }
    }
    return successCount;
  }

  /// Close database connection.
  Future<void> close() async {
    _dbInitFuture = null;
    _activeProcessFuture = null;
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}

