import 'package:uuid/uuid.dart';
import 'imu_reading_model.dart';
import 'telemetry/telemetry_batch_model.dart';

const _uuid = Uuid();

/// Model representing a complete reassembled Studio recording session.
/// Contract reference: contracts/README.md (Topic telemetry/raw) & TelemetryBatch
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

  /// Factory ensuring canonical UUID v4 generation for [sessionId].
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

  /// Converts the Studio session into telemetry batches conforming to the Pydantic TelemetryBatch contract.
  List<TelemetryBatch> toTelemetryBatches({int maxReadingsPerChunk = 500}) {
    return TelemetryBatch.fromStudioSession(this, maxReadingsPerChunk: maxReadingsPerChunk);
  }

  /// Splits the session into chunks of JSON dictionaries serialized per TelemetryBatch,
  /// guaranteeing to stay under the AWS IoT Core limit (128 KB per message).
  List<Map<String, dynamic>> toMqttBatchPayloads({int maxReadingsPerChunk = 500}) {
    return toTelemetryBatches(maxReadingsPerChunk: maxReadingsPerChunk)
        .map((batch) => batch.toJson())
        .toList();
  }

  /// Serializes the payload for REST declaration with the FastAPI backend.
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
