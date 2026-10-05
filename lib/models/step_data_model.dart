import 'dart:typed_data';

/// Immutable model representing step counter data decoded from BLE characteristic 7a5a0006.
/// Contract reference: contracts/ble_gatt_specs.md (Characteristic 5 - Step Counter)
class StepDataModel {
  final int totalSteps;
  final int walkSteps;
  final int runSteps;
  final int stairsSteps;
  final int unclassifiedSteps;
  final int cadenceSpm;
  final int gctMs;
  final DateTime timestamp;

  const StepDataModel({
    required this.totalSteps,
    required this.walkSteps,
    required this.runSteps,
    required this.stairsSteps,
    required this.unclassifiedSteps,
    required this.cadenceSpm,
    this.gctMs = 0,
    required this.timestamp,
  });

  /// Decodes 13 to 15 bytes of Big-Endian binary payload per the HealthKicks GATT specification:
  /// - uint32 total_steps (offset 0..3)
  /// - uint16 walk_steps (offset 4..5)
  /// - uint16 run_steps (offset 6..7)
  /// - uint16 stairs_steps (offset 8..9)
  /// - uint16 unclassified_steps (offset 10..11)
  /// - uint8 cadence_spm (offset 12)
  /// - uint16 current_gct_ms (offset 13..14, optional for backward compatibility)
  factory StepDataModel.fromBytes(List<int> bytes, [DateTime? timestamp]) {
    if (bytes.length < 13) {
      throw FormatException(
        'Invalid Step Counter payload: expected at least 13 bytes, got ${bytes.length}',
      );
    }

    final byteData = ByteData.sublistView(Uint8List.fromList(bytes));
    final totalSteps = byteData.getUint32(0, Endian.big);
    final walkSteps = byteData.getUint16(4, Endian.big);
    final runSteps = byteData.getUint16(6, Endian.big);
    final stairsSteps = byteData.getUint16(8, Endian.big);
    final unclassifiedSteps = byteData.getUint16(10, Endian.big);
    final cadenceSpm = byteData.getUint8(12);
    final gctMs = bytes.length >= 15 ? byteData.getUint16(13, Endian.big) : 0;

    return StepDataModel(
      totalSteps: totalSteps,
      walkSteps: walkSteps,
      runSteps: runSteps,
      stairsSteps: stairsSteps,
      unclassifiedSteps: unclassifiedSteps,
      cadenceSpm: cadenceSpm,
      gctMs: gctMs,
      timestamp: timestamp ?? DateTime.now(),
    );
  }

  /// Converts step data to a JSON map for telemetry and storage.
  Map<String, dynamic> toJson() {
    return {
      'total_steps': totalSteps,
      'walk_steps': walkSteps,
      'run_steps': runSteps,
      'stairs_steps': stairsSteps,
      'unclassified_steps': unclassifiedSteps,
      'cadence_spm': cadenceSpm,
      'gct_ms': gctMs,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// Converts step data to normalized MQTT payload.
  Map<String, dynamic> toMqttPayload(String deviceId) {
    return {
      'device_id': deviceId,
      'total_steps': totalSteps,
      'walk_steps': walkSteps,
      'run_steps': runSteps,
      'stairs_steps': stairsSteps,
      'unclassified_steps': unclassifiedSteps,
      'cadence_spm': cadenceSpm,
      'gct_ms': gctMs,
      'timestamp': timestamp.toUtc().millisecondsSinceEpoch,
    };
  }

  StepDataModel copyWith({
    int? totalSteps,
    int? walkSteps,
    int? runSteps,
    int? stairsSteps,
    int? unclassifiedSteps,
    int? cadenceSpm,
    int? gctMs,
    DateTime? timestamp,
  }) {
    return StepDataModel(
      totalSteps: totalSteps ?? this.totalSteps,
      walkSteps: walkSteps ?? this.walkSteps,
      runSteps: runSteps ?? this.runSteps,
      stairsSteps: stairsSteps ?? this.stairsSteps,
      unclassifiedSteps: unclassifiedSteps ?? this.unclassifiedSteps,
      cadenceSpm: cadenceSpm ?? this.cadenceSpm,
      gctMs: gctMs ?? this.gctMs,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StepDataModel &&
          runtimeType == other.runtimeType &&
          totalSteps == other.totalSteps &&
          walkSteps == other.walkSteps &&
          runSteps == other.runSteps &&
          stairsSteps == other.stairsSteps &&
          unclassifiedSteps == other.unclassifiedSteps &&
          cadenceSpm == other.cadenceSpm &&
          gctMs == other.gctMs;

  @override
  int get hashCode =>
      totalSteps.hashCode ^
      walkSteps.hashCode ^
      runSteps.hashCode ^
      stairsSteps.hashCode ^
      unclassifiedSteps.hashCode ^
      cadenceSpm.hashCode ^
      gctMs.hashCode;

  @override
  String toString() {
    return 'StepDataModel(total: $totalSteps, walk: $walkSteps, run: $runSteps, stairs: $stairsSteps, unclassified: $unclassifiedSteps, cadence: ${cadenceSpm}spm, gct: ${gctMs}ms)';
  }
}

