import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Severity classification of a biomechanical detection event.
enum EventSeverity {
  critical,
  warning,
  info,
}

/// Model representing a detected biomechanical event from the foot sensor or ML engine.
class DetectionEvent {
  final String id;
  final String deviceId;
  final String eventType;
  final DateTime timestamp;
  final EventSeverity severity;
  final double? peakImpactG;
  final double? confidence;
  final bool isValidated;
  final Map<String, dynamic>? metadata;

  DetectionEvent({
    required this.id,
    required this.deviceId,
    required this.eventType,
    required this.timestamp,
    required this.severity,
    this.peakImpactG,
    this.confidence,
    required this.isValidated,
    this.metadata,
  });

  factory DetectionEvent.fromJson(Map<String, dynamic> json) {
    // Parse severity
    final severityRaw = (json['severity'] as String? ?? '').toLowerCase();
    final EventSeverity severity;
    if (severityRaw == 'critical' || severityRaw == 'danger' || severityRaw == 'high') {
      severity = EventSeverity.critical;
    } else if (severityRaw == 'warning' || severityRaw == 'warn' || severityRaw == 'medium') {
      severity = EventSeverity.warning;
    } else {
      // If severity is not explicitly set, infer from eventType
      final type = (json['event_type'] as String? ?? json['eventType'] as String? ?? '').toLowerCase();
      if (type.contains('fall') || type == 'free_fall' || type == 'emergency') {
        severity = EventSeverity.critical;
      } else if (type.contains('impact') || type.contains('stumble') || type.contains('immobility')) {
        severity = EventSeverity.warning;
      } else {
        severity = EventSeverity.info;
      }
    }

    // Parse timestamp (ISO8601 string or epoch ms/sec)
    DateTime timestamp;
    final rawTs = json['timestamp'] ?? json['created_at'] ?? json['timestamp_utc'];
    if (rawTs is int) {
      timestamp = rawTs > 10000000000
          ? DateTime.fromMillisecondsSinceEpoch(rawTs, isUtc: true).toLocal()
          : DateTime.fromMillisecondsSinceEpoch(rawTs * 1000, isUtc: true).toLocal();
    } else if (rawTs is String) {
      timestamp = DateTime.tryParse(rawTs)?.toLocal() ?? DateTime.now();
    } else {
      timestamp = DateTime.now();
    }

    // Parse peak impact in g
    double? peakImpactG;
    final rawImpact = json['peak_impact_g'] ?? json['peakImpactG'] ?? json['impact_g'];
    if (rawImpact is num) {
      peakImpactG = rawImpact.toDouble();
    }

    // Parse confidence (0.0 to 1.0 or 0 to 100)
    double? confidence;
    final rawConf = json['confidence'] ?? json['confidence_percent'];
    if (rawConf is num) {
      confidence = rawConf > 1.0 ? rawConf.toDouble() / 100.0 : rawConf.toDouble();
    }

    return DetectionEvent(
      id: json['id'] as String? ?? json['event_id'] as String? ?? '',
      deviceId: json['device_id'] as String? ?? json['deviceId'] as String? ?? 'HK-2',
      eventType: json['event_type'] as String? ?? json['eventType'] as String? ?? 'activity_detected',
      timestamp: timestamp,
      severity: severity,
      peakImpactG: peakImpactG,
      confidence: confidence,
      isValidated: json['is_validated'] as bool? ?? json['isValidated'] as bool? ?? false,
      metadata: json['metadata'] is Map<String, dynamic> ? json['metadata'] as Map<String, dynamic> : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'device_id': deviceId,
      'event_type': eventType,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'severity': severity.name,
      if (peakImpactG != null) 'peak_impact_g': peakImpactG,
      if (confidence != null) 'confidence': confidence,
      'is_validated': isValidated,
      if (metadata != null) 'metadata': metadata,
    };
  }

  /// User-friendly localized label for the event type.
  String get formattedTitle {
    switch (eventType.toLowerCase()) {
      case 'fall_detected':
      case 'fall':
      case 'fall_forward':
      case 'fall_backward':
      case 'fall_lateral':
      case 'fall_generic':
        return 'Chute détectée';
      case 'free_fall':
        return 'Chute libre (Impact violent)';
      case 'high_impact':
        return 'Impact élevé';
      case 'stumble_recover':
        return 'Trébuchement rattrapé';
      case 'prolonged_immobility':
        return 'Immobilité prolongée';
      case 'walk':
      case 'walking':
        return 'Marche';
      case 'run':
      case 'running':
        return 'Course à pied';
      case 'stairs':
        return 'Montée/Descente d\'escaliers';
      case 'idle':
        return 'Repos / Station debout';
      case 'activity_transition':
        return 'Transition d\'activité';
      default:
        return eventType.replaceAll('_', ' ').toUpperCase();
    }
  }

  /// Icon corresponding to the event nature.
  IconData get icon {
    switch (severity) {
      case EventSeverity.critical:
        return Icons.warning_rounded;
      case EventSeverity.warning:
        return Icons.error_outline_rounded;
      case EventSeverity.info:
        if (eventType.contains('walk') || eventType.contains('run')) {
          return Icons.directions_walk_rounded;
        } else if (eventType.contains('stairs')) {
          return Icons.stairs_rounded;
        }
        return Icons.info_outline_rounded;
    }
  }

  /// Severity badge and indicator color.
  Color get color {
    switch (severity) {
      case EventSeverity.critical:
        return const Color(0xFFDC2626); // Bright Red
      case EventSeverity.warning:
        return const Color(0xFFD97706); // Amber
      case EventSeverity.info:
        return const Color(0xFF0F766E); // HealthKicks Teal
    }
  }

  /// Relative human-readable timestamp (e.g. "Il y a 10 min", "Hier à 14:30").
  String get relativeTime {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inSeconds < 60) {
      return 'À l\'instant';
    } else if (difference.inMinutes < 60) {
      return 'Il y a ${difference.inMinutes} min';
    } else if (difference.inHours < 24 && now.day == timestamp.day) {
      return 'Aujourd\'hui à ${DateFormat('HH:mm').format(timestamp)}';
    } else if (difference.inDays < 2 && (now.day - timestamp.day == 1 || difference.inHours < 48)) {
      return 'Hier à ${DateFormat('HH:mm').format(timestamp)}';
    } else {
      return DateFormat('dd/MM/yyyy HH:mm').format(timestamp);
    }
  }
}

/// Paginated API response container for event history.
class EventHistoryResponse {
  final List<DetectionEvent> events;
  final int total;
  final int page;
  final int size;
  final bool hasMore;

  const EventHistoryResponse({
    required this.events,
    required this.total,
    required this.page,
    required this.size,
    required this.hasMore,
  });

  factory EventHistoryResponse.fromJson(Map<String, dynamic> json, {int page = 1, int size = 20}) {
    final rawItems = json['items'] ?? json['events'] ?? json['data'] ?? [];
    final itemsList = (rawItems is List)
        ? rawItems.map((e) => DetectionEvent.fromJson(e as Map<String, dynamic>)).toList()
        : <DetectionEvent>[];

    final total = json['total'] as int? ?? json['total_count'] as int? ?? itemsList.length;
    final hasMore = json['has_more'] as bool? ?? (itemsList.length >= size && (page * size) < total);

    return EventHistoryResponse(
      events: itemsList,
      total: total,
      page: page,
      size: size,
      hasMore: hasMore,
    );
  }
}

