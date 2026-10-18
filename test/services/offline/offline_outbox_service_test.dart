import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:healthkicks_mobile/services/offline/offline_outbox_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('OfflineOutboxService - Persistent Queue', () {
    late OfflineOutboxService outbox;

    setUp(() async {
      outbox = OfflineOutboxService(inMemoryDbName: inMemoryDatabasePath);
    });

    tearDown(() async {
      await outbox.close();
    });

    test('enqueue adds item to queue with FIFO ordering and default fields', () async {
      final id1 = await outbox.enqueue(
        endpoint: '/api/v1/telemetry/events',
        method: 'POST',
        payload: {'event': 'walk', 'steps': 100},
      );
      final id2 = await outbox.enqueue(
        endpoint: '/api/v1/haptic/logs',
        method: 'POST',
        payload: {'intensity': 200},
        headers: {'X-Custom': 'Value'},
      );

      expect(id1, isPositive);
      expect(id2, isPositive);

      final count = await outbox.getPendingCount();
      expect(count, equals(2));

      final items = await outbox.getPendingItems();
      expect(items.length, equals(2));
      expect(items[0].id, equals(id1));
      expect(items[0].endpoint, equals('/api/v1/telemetry/events'));
      expect(items[0].payload['event'], equals('walk'));
      expect(items[0].retryCount, equals(0));

      expect(items[1].id, equals(id2));
      expect(items[1].headers?['X-Custom'], equals('Value'));
    });

    test('markCompleted removes item from queue', () async {
      final id = await outbox.enqueue(
        endpoint: '/api/v1/steps',
        method: 'POST',
        payload: {'steps': 50},
      );

      expect(await outbox.getPendingCount(), equals(1));
      await outbox.markCompleted(id);
      expect(await outbox.getPendingCount(), equals(0));
    });

    test('markFailed increments retry count and stores error', () async {
      final id = await outbox.enqueue(
        endpoint: '/api/v1/steps',
        method: 'POST',
        payload: {'steps': 50},
      );

      await outbox.markFailed(id, 'Network timeout');
      final item = await outbox.getItem(id);
      expect(item, isNotNull);
      expect(item!.retryCount, equals(1));
      expect(item.lastError, equals('Network timeout'));
      expect(item.nextRetryAt, isNotNull);

      // Exceed threshold
      for (int i = 0; i < 4; i++) {
        await outbox.markFailed(id, 'Fail');
      }
      expect(await outbox.getPendingCount(includeScheduled: true), equals(0)); // retry_count >= 5 excluded
    });

    test('calculateBackoffDelay scales exponentially and respects maxBackoff cap', () {
      expect(outbox.calculateBackoffDelay(0), equals(const Duration(seconds: 2)));
      expect(outbox.calculateBackoffDelay(1), equals(const Duration(seconds: 4)));
      expect(outbox.calculateBackoffDelay(2), equals(const Duration(seconds: 8)));
      expect(outbox.calculateBackoffDelay(3), equals(const Duration(seconds: 16)));
      expect(outbox.calculateBackoffDelay(4), equals(const Duration(seconds: 32)));
      expect(outbox.calculateBackoffDelay(10), equals(const Duration(minutes: 5)));
    });

    test('markFailed schedules next_retry_at and hides items until scheduled time', () async {
      final now = DateTime.utc(2026, 10, 18, 12, 0, 0);
      final id = await outbox.enqueue(
        endpoint: '/api/v1/telemetry/burst',
        method: 'POST',
        payload: {'burst_id': 42},
      );

      // Initially pending
      expect(await outbox.getPendingCount(now: now), equals(1));

      // Mark failed at 12:00:00 -> retry 1 scheduled for 12:00:02 (2s backoff)
      await outbox.markFailed(id, 'Connection reset', now: now);

      // 1 second later: item is in backoff cooldown, should NOT be returned
      final at1Sec = now.add(const Duration(seconds: 1));
      expect(await outbox.getPendingCount(now: at1Sec), equals(0));
      expect(await outbox.getPendingItems(now: at1Sec), isEmpty);

      // 2 seconds later: item is eligible for retry
      final at2Sec = now.add(const Duration(seconds: 2));
      expect(await outbox.getPendingCount(now: at2Sec), equals(1));
      final pending = await outbox.getPendingItems(now: at2Sec);
      expect(pending.length, equals(1));
      expect(pending.first.id, equals(id));
      expect(pending.first.retryCount, equals(1));
      expect(pending.first.nextRetryAt, equals(now.add(const Duration(seconds: 2))));
    });

    test('pruneExpired deletes expired and poisoned items', () async {
      final id1 = await outbox.enqueue(
        endpoint: '/api/v1/old',
        method: 'POST',
        payload: {'old': true},
      );
      // Mark as poisoned (5 retries)
      for (int i = 0; i < 5; i++) {
        await outbox.markFailed(id1, 'Permanent failure');
      }

      final pruned = await outbox.pruneExpired(maxAge: const Duration(days: 1));
      expect(pruned, equals(1));
    });

    test('processQueue delivers items and tracks success count', () async {
      await outbox.enqueue(
        endpoint: '/api/v1/event/1',
        method: 'POST',
        payload: {'num': 1},
      );
      await outbox.enqueue(
        endpoint: '/api/v1/event/2',
        method: 'POST',
        payload: {'num': 2},
      );

      final processed = await outbox.processQueue(
        sender: (item) async {
          if (item.endpoint.contains('/2')) {
            return false; // simulate failure on item 2
          }
          return true;
        },
      );

      expect(processed, equals(1));
      // At this exact moment, item 2 failed and was scheduled for retry in 2s
      // Without `now` advancing, it is in backoff so pending count is 0
      expect(await outbox.getPendingCount(), equals(0));
      // But 3 seconds later, item 2 is ready to retry
      final futureTime = DateTime.now().toUtc().add(const Duration(seconds: 3));
      expect(await outbox.getPendingCount(now: futureTime), equals(1));

      final remaining = await outbox.getPendingItems(now: futureTime);
      expect(remaining.first.endpoint, equals('/api/v1/event/2'));
      expect(remaining.first.retryCount, equals(1));
    });
  });
}

