import 'package:flutter/material.dart';

/// Modèle représentant une entrée du journal d'événements de la passerelle mobile.
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

  /// Timestamp formaté au format HH:mm:ss.SSS
  String get formattedTimestamp {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  /// Ligne de log textuelle pour export
  String toFormattedLine() {
    return '[$formattedTimestamp] [$tag] $message';
  }
}

