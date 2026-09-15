import 'package:uuid/uuid.dart';
import 'imu_reading_model.dart';
import 'telemetry/telemetry_batch_model.dart';

const _uuid = Uuid();

/// Modèle représentant une session d'enregistrement Studio complète réassemblée.
/// Référence contractuelle : contracts/README.md (Topic telemetry/raw) & TelemetryBatch
class StudioSessionModel {
  final String sessionId;
  final String label;
  final String deviceId;
  final int sampleRateHz;
  final double startTimestampEpoch;
  final double durationSec;
  final List<ImuReadingModel> readings;

  const StudioSessionModel({
    required this.sessionId,
    required this.label,
    required this.deviceId,
    this.sampleRateHz = 50,
    required this.startTimestampEpoch,
    this.durationSec = 5.0,
    required this.readings,
  });

  /// Fabrique assurant la génération d'un UUID v4 canonique pour [sessionId].
  factory StudioSessionModel.create({
    String? sessionId,
    required String label,
    required String deviceId,
    int sampleRateHz = 50,
    double? startTimestampEpoch,
    double durationSec = 5.0,
    required List<ImuReadingModel> readings,
  }) {
    return StudioSessionModel(
      sessionId: sessionId ?? _uuid.v4(),
      label: label,
      deviceId: deviceId,
      sampleRateHz: sampleRateHz,
      startTimestampEpoch:
          startTimestampEpoch ?? DateTime.now().millisecondsSinceEpoch / 1000.0,
      durationSec: durationSec,
      readings: readings,
    );
  }

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

  /// Sérialise le payload pour la déclaration REST auprès du backend FastAPI.
  Map<String, dynamic> toRestApiPayload() {
    return {
      'id': sessionId,
      'device_id': deviceId,
      'label': label,
      'duration_sec': durationSec,
      'sample_count': readings.length,
    };
  }
}
