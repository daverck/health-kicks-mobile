import '../activity_detection_model.dart';
import '../imu_reading_model.dart';
import '../studio_session_model.dart';

/// Representation of an activity detection in Human-in-the-Loop (HITL) mode.
/// Contains the edge-inferred activity, confidence, raw 76-sample IMU burst readings,
/// and user-adjusted label for training dataset curation.
class HitlDetectionItem {
  final String id;
  final DateTime timestamp;
  final String detectedLabel;
  final int confidencePercent;
  final bool isFall;
  final ActivityDetectionModel rawDetection;

  String selectedLabel;
  List<ImuReadingModel> readings;
  bool isBurstReady;
  bool isPublishing;

  HitlDetectionItem({
    required this.id,
    required this.timestamp,
    required this.detectedLabel,
    required this.confidencePercent,
    required this.isFall,
    required this.rawDetection,
    String? selectedLabel,
    List<ImuReadingModel>? readings,
    this.isBurstReady = false,
    this.isPublishing = false,
  })  : selectedLabel = selectedLabel ?? detectedLabel,
        readings = readings ?? [];

  /// Converts this item into a validated Studio session model ready for DynamoDB/Aurora ingestion.
  StudioSessionModel toStudioSession({
    required String deviceId,
    String? sessionId,
    double durationSec = 4.0,
  }) {
    return StudioSessionModel.create(
      sessionId: sessionId ?? id,
      deviceId: deviceId,
      label: selectedLabel,
      startTimestampEpoch: timestamp.millisecondsSinceEpoch / 1000.0,
      durationSec: durationSec,
      isHitl: true,
      readings: readings,
    );
  }
}

