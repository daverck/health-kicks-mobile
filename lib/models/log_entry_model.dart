import 'package:flutter/material.dart';

/// Model representing a mobile gateway event log entry.
class LogEntry {
  final DateTime timestamp;
  final String tag;
  final String message;
  final Color color;

  const LogEntry({
    required this.timestamp,
    required this.tag,
    required this.message,
    this.color = Colors.grey,
  });

  /// Formatted timestamp in HH:mm:ss.SSS format
  String get formattedTimestamp {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  /// Text log line for export
  String toFormattedLine() {
    return '[$formattedTimestamp] [$tag] $message';
  }
}

