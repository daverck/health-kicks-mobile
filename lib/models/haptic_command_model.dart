import 'dart:typed_data';

/// Model representing a tactile haptic stimulation command received from Cloud MQTT
/// and serialized to BLE characteristic 7a5a0003.
/// Contract reference: contracts/ble_gatt_specs.md (Characteristic 2)
class HapticCommandModel {
  final String commandId;
  final int patternId;
  final int intensity;
  final int durationMs;

  const HapticCommandModel({
    required this.commandId,
    this.patternId = 0,
    required this.intensity,
    required this.durationMs,
  });

  /// Parses a JSON message received from AWS IoT Core on healthkicks/v1/{device_id}/commands/haptic.
  factory HapticCommandModel.fromJson(Map<String, dynamic> json) {
    final rawIntensity = json['intensity'] as int? ?? 180;
    final rawDuration = json['duration_ms'] as int? ?? 500;
    final patternStr = json['pattern'] as String? ?? 'single_pulse';

    int patternCode = 0;
    if (patternStr == 'double_pulse') {
      patternCode = 1;
    } else if (patternStr == 'alert_pattern') {
      patternCode = 2;
    }

    // Validate contract bounds
    final clampedIntensity = rawIntensity.clamp(0, 255);
    final clampedDuration = rawDuration.clamp(50, 10000);

    return HapticCommandModel(
      commandId: json['command_id'] as String? ?? '',
      patternId: patternCode,
      intensity: clampedIntensity,
      durationMs: clampedDuration,
    );
  }

  /// Serializes the command to 4 Big-Endian bytes:
  /// [pattern_id (uint8), intensity (uint8), duration_ms (uint16 big-endian)]
  Uint8List toBleBytes() {
    final byteData = ByteData(4);
    byteData.setUint8(0, patternId);
    byteData.setUint8(1, intensity);
    byteData.setUint16(2, durationMs, Endian.big);
    return byteData.buffer.asUint8List();
  }

  @override
  String toString() {
    return 'HapticCommandModel(id: $commandId, pattern: $patternId, intensity: $intensity, duration: ${durationMs}ms)';
  }
}
