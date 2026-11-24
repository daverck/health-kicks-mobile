import 'dart:typed_data';

/// Represents an active movement bout recorded autonomously by the connected footwear.
/// Contract reference: contracts/ble_gatt_specs.md (Characteristic 0004, Opcode 0x31)
class ActivityBoutModel {
  final int startUptimeSec;
  final int durationSec;
  final int stepCount;
  final int activityType; // 0x01 = Walk, 0x02 = Run, 0x03 = Stairs, 0x04 = Unclassified
  final int avgCadence; // Steps per minute

  const ActivityBoutModel({
    required this.startUptimeSec,
    required this.durationSec,
    required this.stepCount,
    required this.activityType,
    required this.avgCadence,
  });

  /// Decodes an 8-byte big-endian packed record from raw BLE payload bytes.
  factory ActivityBoutModel.fromBytes(Uint8List bytes, int offset) {
    if (bytes.length < offset + 8) {
      throw ArgumentError('Insufficient bytes to decode ActivityBoutModel at offset $offset');
    }

    final startUptimeSec = (bytes[offset] << 8) | bytes[offset + 1];
    final durationSec = (bytes[offset + 2] << 8) | bytes[offset + 3];
    final stepCount = (bytes[offset + 4] << 8) | bytes[offset + 5];
    final activityType = bytes[offset + 6];
    final avgCadence = bytes[offset + 7];

    return ActivityBoutModel(
      startUptimeSec: startUptimeSec,
      durationSec: durationSec,
      stepCount: stepCount,
      activityType: activityType,
      avgCadence: avgCadence,
    );
  }

  /// Calculates the exact start time of this bout based on the hardware session start time.
  DateTime getStartTime(DateTime sessionStartTime) {
    return sessionStartTime.add(Duration(seconds: startUptimeSec));
  }

  /// Calculates the exact end time of this bout based on the hardware session start time.
  DateTime getEndTime(DateTime sessionStartTime) {
    final start = getStartTime(sessionStartTime);
    final effectiveDuration = durationSec > 0 ? durationSec : 1;
    return start.add(Duration(seconds: effectiveDuration));
  }

  /// Computes the proportional distribution of steps across calendar hours (0..23).
  ///
  /// If the bout occurred entirely within one hour, all steps are allocated to that hour.
  /// If the bout crosses one or more hour boundaries, steps are distributed proportionally
  /// to the time spent moving in each hour, with rounding differences reconciled so that
  /// sum(ventilated steps) == stepCount strictly.
  Map<int, int> computeHourlyVentilation(DateTime sessionStartTime) {
    if (stepCount <= 0) {
      return {};
    }

    final boutStart = getStartTime(sessionStartTime);
    final effectiveDuration = durationSec > 0 ? durationSec : 1;
    final boutEnd = boutStart.add(Duration(seconds: effectiveDuration));

    // Fast path: same hour
    if (boutStart.year == boutEnd.year &&
        boutStart.month == boutEnd.month &&
        boutStart.day == boutEnd.day &&
        boutStart.hour == boutEnd.hour) {
      return {boutStart.hour: stepCount};
    }

    // Split across hour boundaries
    final hourSeconds = <int, int>{};
    var current = boutStart;

    while (current.isBefore(boutEnd)) {
      final nextHour = DateTime(
        current.year,
        current.month,
        current.day,
        current.hour + 1,
      );
      final segmentEnd = boutEnd.isBefore(nextHour) ? boutEnd : nextHour;
      final secondsInSegment = segmentEnd.difference(current).inSeconds;

      if (secondsInSegment > 0) {
        hourSeconds[current.hour] = (hourSeconds[current.hour] ?? 0) + secondsInSegment;
      }
      current = segmentEnd;
    }

    final totalSeconds = hourSeconds.values.fold<int>(0, (sum, sec) => sum + sec);
    if (totalSeconds <= 0) {
      return {boutStart.hour: stepCount};
    }

    final result = <int, int>{};
    var allocatedSteps = 0;
    int? maxHour;
    var maxSeconds = -1;

    for (final entry in hourSeconds.entries) {
      final steps = (stepCount * entry.value / totalSeconds).round();
      result[entry.key] = steps;
      allocatedSteps += steps;

      if (entry.value > maxSeconds) {
        maxSeconds = entry.value;
        maxHour = entry.key;
      }
    }

    // Reconcile rounding error to guarantee sum(steps) == stepCount strictly
    final diff = stepCount - allocatedSteps;
    if (diff != 0 && maxHour != null) {
      result[maxHour] = (result[maxHour] ?? 0) + diff;
    }

    return result;
  }

  Map<String, dynamic> toJson() => {
    'start_uptime_sec': startUptimeSec,
    'duration_sec': durationSec,
    'step_count': stepCount,
    'activity_type': activityType,
    'avg_cadence': avgCadence,
  };

  @override
  String toString() {
    return 'ActivityBoutModel(startUptimeSec: $startUptimeSec, durationSec: $durationSec, '
        'stepCount: $stepCount, activityType: $activityType, avgCadence: $avgCadence)';
  }
}
