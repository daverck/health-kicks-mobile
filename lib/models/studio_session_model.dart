import 'imu_reading_model.dart';
import 'telemetry/telemetry_batch_model.dart';

/// Modèle représentant une session d'enregistrement Studio complète réassemblée.
/// Référence contractuelle : contracts/README.md (Topic telemetry/raw) & TelemetryBatch
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

  /// Convertit la session Studio en lots de télémétrie conformes au contrat Pydantic TelemetryBatch.
  List<TelemetryBatch> toTelemetryBatches({int maxReadingsPerChunk = 500}) {
    return TelemetryBatch.fromStudioSession(this, maxReadingsPerChunk: maxReadingsPerChunk);
  }

  /// Découpe la session en lots (chunks) de dictionnaires JSON sérialisés selon TelemetryBatch,
  /// garantissant de rester sous la limite AWS IoT Core (128 Ko par message).
  List<Map<String, dynamic>> toMqttBatchPayloads({int maxReadingsPerChunk = 500}) {
    return toTelemetryBatches(maxReadingsPerChunk: maxReadingsPerChunk)
        .map((batch) => batch.toJson())
        .toList();
  }
}
