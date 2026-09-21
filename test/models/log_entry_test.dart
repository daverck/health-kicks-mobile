import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/models/log_entry_model.dart';

void main() {
  group('LogEntry Model', () {
    test('Formats line without duplicate tag when message has no tag prefix', () {
      final now = DateTime(2026, 9, 21, 21, 28, 51, 280);
      final entry = LogEntry(
        timestamp: now,
        tag: 'MQTT',
        message: 'Automatic MQTT reconnection in progress...',
        color: Colors.teal,
      );

      expect(entry.tag, equals('MQTT'));
      expect(entry.message, equals('Automatic MQTT reconnection in progress...'));
      expect(entry.formattedTimestamp, equals('21:28:51.280'));
      expect(entry.toFormattedLine(), equals('[21:28:51.280] [MQTT] Automatic MQTT reconnection in progress...'));
    });

    test('Strips redundant leading [TAG] prefix from message', () {
      final now = DateTime(2026, 9, 21, 21, 28, 51, 280);
      final entry = LogEntry(
        timestamp: now,
        tag: 'MQTT',
        message: '[MQTT] Automatic MQTT reconnection in progress...',
        color: Colors.teal,
      );

      expect(entry.tag, equals('MQTT'));
      expect(entry.message, equals('Automatic MQTT reconnection in progress...'));
      expect(entry.toFormattedLine(), equals('[21:28:51.280] [MQTT] Automatic MQTT reconnection in progress...'));
    });

    test('Strips different leading [TAG] prefix if mismatched', () {
      final now = DateTime(2026, 9, 21, 21, 28, 51, 280);
      final entry = LogEntry(
        timestamp: now,
        tag: 'GATEWAY',
        message: '[BLE] Device ready',
      );

      expect(entry.tag, equals('GATEWAY'));
      expect(entry.message, equals('Device ready'));
      expect(entry.toFormattedLine(), equals('[21:28:51.280] [GATEWAY] Device ready'));
    });
  });
}
