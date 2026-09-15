/// Modèle représentant une commande Studio descendante émise depuis le Web/Backend via AWS IoT Core.
/// Référence contractuelle : healthkicks/v1/{device_id}/commands/studio/start
class StudioCommandModel {
  final String sessionId;
  final String label;
  final double durationSec;
  final int? pulseCount;
  final int? pulseDurationMs;
  final int? pulsePauseMs;
  final int? pulseIntensity;

  const StudioCommandModel({
    required this.sessionId,
    required this.label,
    this.durationSec = 5.0,
    this.pulseCount,
    this.pulseDurationMs,
    this.pulsePauseMs,
    this.pulseIntensity,
  });

  factory StudioCommandModel.fromJson(Map<String, dynamic> json) {
    return StudioCommandModel(
      sessionId: json['session_id'] as String,
      label: json['label'] as String? ?? 'unlabeled',
      durationSec: (json['duration_sec'] as num?)?.toDouble() ?? 5.0,
      pulseCount: json['pulse_count'] as int?,
      pulseDurationMs: json['pulse_duration_ms'] as int?,
      pulsePauseMs: json['pulse_pause_ms'] as int?,
      pulseIntensity: json['pulse_intensity'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'session_id': sessionId,
      'label': label,
      'duration_sec': durationSec,
      if (pulseCount != null) 'pulse_count': pulseCount,
      if (pulseDurationMs != null) 'pulse_duration_ms': pulseDurationMs,
      if (pulsePauseMs != null) 'pulse_pause_ms': pulsePauseMs,
      if (pulseIntensity != null) 'pulse_intensity': pulseIntensity,
    };
  }
}
