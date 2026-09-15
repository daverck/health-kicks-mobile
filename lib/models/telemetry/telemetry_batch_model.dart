import 'package:uuid/uuid.dart';
import '../studio_session_model.dart';

const _uuid = Uuid();

/// En-tête standard conforme au schéma Pydantic Header de l'écosystème.
/// Référence contractuelle : health-kicks-edge-script/src/healthkicks_edge/schemas.py (Header)
class TelemetryHeader {
  final String deviceId;
  final String schemaVersion;
  final String timestamp;
  final String msgId;

  TelemetryHeader({
    required this.deviceId,
    this.schemaVersion = '1.0',
    String? timestamp,
    String? msgId,
  })  : timestamp = timestamp ?? DateTime.now().toUtc().toIso8601String(),
        msgId = msgId ?? _uuid.v4();

  factory TelemetryHeader.fromJson(Map<String, dynamic> json) {
    return TelemetryHeader(
      deviceId: json['device_id'] as String,
      schemaVersion: json['schema_version'] as String? ?? '1.0',
      timestamp: json['timestamp'] as String,
      msgId: json['msg_id'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'device_id': deviceId,
      'schema_version': schemaVersion,
      'timestamp': timestamp,
      'msg_id': msgId,
    };
  }
}

/// Charge utile inertielle 6-axes conforme à ImuPayload.
class ImuPayload {
  final double ax;
  final double ay;
  final double az;
  final double gx;
  final double gy;
  final double gz;

  const ImuPayload({
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
  });

  factory ImuPayload.fromJson(Map<String, dynamic> json) {
    return ImuPayload(
      ax: (json['ax'] as num).toDouble(),
      ay: (json['ay'] as num).toDouble(),
      az: (json['az'] as num).toDouble(),
      gx: (json['gx'] as num).toDouble(),
      gy: (json['gy'] as num).toDouble(),
      gz: (json['gz'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ax': ax,
      'ay': ay,
      'az': az,
      'gx': gx,
      'gy': gy,
      'gz': gz,
    };
  }
}

/// Mesure unitaire IMU conforme à Telemetry (StrictModel).
class TelemetryItem {
  final TelemetryHeader header;
  final ImuPayload payload;

  const TelemetryItem({
    required this.header,
    required this.payload,
  });

  factory TelemetryItem.fromJson(Map<String, dynamic> json) {
    return TelemetryItem(
      header: TelemetryHeader.fromJson(json['header'] as Map<String, dynamic>),
      payload: ImuPayload.fromJson(json['payload'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'header': header.toJson(),
      'payload': payload.toJson(),
    };
  }
}

/// Métadonnées d'un lot de télémétrie conforme à BatchMetadata.
class BatchMetadata {
  final int sampleCount;
  final String windowStart;
  final String windowEnd;
  final String flushTrigger;
  final String? sessionId;
  final String? label;

  const BatchMetadata({
    required this.sampleCount,
    required this.windowStart,
    required this.windowEnd,
    this.flushTrigger = 'studio',
    this.sessionId,
    this.label,
  });

  factory BatchMetadata.fromJson(Map<String, dynamic> json) {
    return BatchMetadata(
      sampleCount: json['sample_count'] as int,
      windowStart: json['window_start'] as String,
      windowEnd: json['window_end'] as String,
      flushTrigger: json['flush_trigger'] as String? ?? 'studio',
      sessionId: json['session_id'] as String?,
      label: json['label'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sample_count': sampleCount,
      'window_start': windowStart,
      'window_end': windowEnd,
      'flush_trigger': flushTrigger,
      if (sessionId != null) 'session_id': sessionId,
      if (label != null) 'label': label,
    };
  }
}

/// Lot de télémétrie complet conforme à TelemetryBatch.
/// Référence contractuelle : health-kicks-edge-script/src/healthkicks_edge/schemas.py (TelemetryBatch)
class TelemetryBatch {
  final TelemetryHeader header;
  final BatchMetadata metadata;
  final List<TelemetryItem> readings;

  const TelemetryBatch({
    required this.header,
    required this.metadata,
    required this.readings,
  });

  factory TelemetryBatch.fromJson(Map<String, dynamic> json) {
    return TelemetryBatch(
      header: TelemetryHeader.fromJson(json['header'] as Map<String, dynamic>),
      metadata: BatchMetadata.fromJson(json['metadata'] as Map<String, dynamic>),
      readings: (json['readings'] as List<dynamic>)
          .map((r) => TelemetryItem.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'header': header.toJson(),
      'metadata': metadata.toJson(),
      'readings': readings.map((r) => r.toJson()).toList(),
    };
  }

  /// Découpe une [StudioSessionModel] en une liste de [TelemetryBatch] conformes Pydantic.
  /// Chaque lot reste sous la limite AWS IoT Core (128 Ko par message).
  static List<TelemetryBatch> fromStudioSession(
    StudioSessionModel session, {
    int maxReadingsPerChunk = 500,
  }) {
    if (session.readings.isEmpty) {
      return [];
    }

    final batches = <TelemetryBatch>[];
    final totalReadings = session.readings.length;

    for (int i = 0; i < totalReadings; i += maxReadingsPerChunk) {
      final end = (i + maxReadingsPerChunk < totalReadings)
          ? i + maxReadingsPerChunk
          : totalReadings;
      final chunkSlice = session.readings.sublist(i, end);

      final telemetryItems = chunkSlice.map((reading) {
        final sampleTimeMs =
            (session.startTimestampEpoch * 1000.0).round() + reading.deltaMs;
        final sampleDate =
            DateTime.fromMillisecondsSinceEpoch(sampleTimeMs, isUtc: true);

        return TelemetryItem(
          header: TelemetryHeader(
            deviceId: session.deviceId,
            timestamp: sampleDate.toIso8601String(),
          ),
          payload: ImuPayload(
            ax: reading.ax,
            ay: reading.ay,
            az: reading.az,
            gx: reading.gx,
            gy: reading.gy,
            gz: reading.gz,
          ),
        );
      }).toList();

      final firstSampleTimeMs =
          (session.startTimestampEpoch * 1000.0).round() + chunkSlice.first.deltaMs;
      final lastSampleTimeMs =
          (session.startTimestampEpoch * 1000.0).round() + chunkSlice.last.deltaMs;

      final windowStart = DateTime.fromMillisecondsSinceEpoch(firstSampleTimeMs, isUtc: true)
          .toIso8601String();
      final windowEnd = DateTime.fromMillisecondsSinceEpoch(lastSampleTimeMs, isUtc: true)
          .toIso8601String();

      final batch = TelemetryBatch(
        header: TelemetryHeader(
          deviceId: session.deviceId,
          timestamp: DateTime.now().toUtc().toIso8601String(),
        ),
        metadata: BatchMetadata(
          sampleCount: telemetryItems.length,
          windowStart: windowStart,
          windowEnd: windowEnd,
          flushTrigger: 'studio',
          sessionId: session.sessionId,
          label: session.label,
        ),
        readings: telemetryItems,
      );

      batches.add(batch);
    }

    return batches;
  }
}
