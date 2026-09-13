import 'dart:convert';
import 'imu_reading_model.dart';

/// Modèle représentant une session d'enregistrement Studio complète réassemblée.
/// Référence contractuelle : contracts/README.md (Topic telemetry/raw)
class StudioSessionModel {
  final String sessionId;
  final String label;
  final String deviceId;
  final int sampleRateHz;
  final double startTimestampEpoch;
  final List<ImuReadingModel> readings;

  const StudioSessionModel({
    required this.sessionId,
    required this.label,
    required this.deviceId,
    this.sampleRateHz = 50,
    required this.startTimestampEpoch,
    required this.readings,
  });

  /// Découpe la session en lots (chunks) de messages JSON garantissant
  /// de rester strictement sous la limite AWS IoT Core (128 Ko par message).
  List<Map<String, dynamic>> toMqttBatchPayloads({int maxReadingsPerChunk = 500}) {
    final result = <Map<String, dynamic>>[];
    if (readings.isEmpty) {
      result.add({
        'device_id': deviceId,
        'session_id': sessionId,
        'label': label,
        'trigger': 'studio',
        'sample_rate_hz': sampleRateHz,
        'readings': [],
      });
      return result;
    }

    for (int i = 0; i < readings.length; i += maxReadingsPerChunk) {
      final end = (i + maxReadingsPerChunk < readings.length)
          ? i + maxReadingsPerChunk
          : readings.length;
      final chunkSlice = readings.sublist(i, end);

      result.add({
        'device_id': deviceId,
        'session_id': sessionId,
        'label': label,
        'trigger': 'studio',
        'sample_rate_hz': sampleRateHz,
        'chunk_index': (i ~/ maxReadingsPerChunk) + 1,
        'total_chunks': ((readings.length - 1) ~/ maxReadingsPerChunk) + 1,
        'readings': chunkSlice.map((r) => r.toJson(startTimestampEpoch)).toList(),
      });
    }

    return result;
  }
}
