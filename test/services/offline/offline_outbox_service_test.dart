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
      final items = await outbox.getPendingItems();
      expect(items.length, equals(1));
      expect(items[0].retryCount, equals(1));
      expect(items[0].lastError, equals('Network timeout'));

      // Exceed threshold
      for (int i = 0; i < 4; i++) {
        await outbox.markFailed(id, 'Fail');
      }
      expect(await outbox.getPendingCount(), equals(0)); // retry_count >= 5 excluded
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
      expect(await outbox.getPendingCount(), equals(1));

      final remaining = await outbox.getPendingItems();
      expect(remaining.first.endpoint, equals('/api/v1/event/2'));
      expect(remaining.first.retryCount, equals(1));
    });
  });
}

