import 'dart:typed_data';

/// Modèle représentant un événement de détection d'activité décodé depuis la caractéristique BLE 7a5a0002.
/// Référence contractuelle : contracts/ble_gatt_specs.md (Caractéristique 1)
class ActivityDetectionModel {
  final int stateCode;
  final String eventType;
  final int confidencePercent;
  final int timestampEpochSec;
  final bool isFall;
  final bool isHapticTriggered;

  const ActivityDetectionModel({
    required this.stateCode,
    required this.eventType,
    required this.confidencePercent,
    required this.timestampEpochSec,
    required this.isFall,
    required this.isHapticTriggered,
  });

  /// Décode les 7 octets du payload binaire Big-Endian selon la spécification GATT HealthKicks.
  factory ActivityDetectionModel.fromBytes(List<int> bytes) {
    if (bytes.length < 7) {
      throw FormatException(
        'Payload Activity Detection invalide : attendu au moins 7 octets, reçu ${bytes.length}',
      );
    }

    final byteData = ByteData.sublistView(Uint8List.fromList(bytes));
    final stateCode = byteData.getUint8(0);
    final confidence = byteData.getUint8(1);
    final timestamp = byteData.getUint32(2, Endian.big);
    final flags = byteData.getUint8(6);

    final eventType = _mapStateCodeToEventType(stateCode);
    final isFall = (flags & 0x01) != 0;
    final isHapticTriggered = (flags & 0x02) != 0;

    return ActivityDetectionModel(
      stateCode: stateCode,
      eventType: eventType,
      confidencePercent: confidence,
      timestampEpochSec: timestamp,
      isFall: isFall,
      isHapticTriggered: isHapticTriggered,
    );
  }

  /// Convertit la détection en message JSON normalisé pour publication MQTT AWS IoT Core.
  /// Référence : contracts/README.md (Topic healthkicks/v1/{device_id}/events/detection)
  Map<String, dynamic> toMqttPayload(String deviceId) {
    final utcDateTime = DateTime.fromMillisecondsSinceEpoch(
      timestampEpochSec * 1000,
      isUtc: true,
    );

    return {
      'device_id': deviceId,
      'event_type': eventType,
      'confidence': (confidencePercent / 100.0),
      'timestamp': utcDateTime.toIso8601String(),
      'is_fall': isFall,
      'haptic_triggered': isHapticTriggered,
    };
  }

  static String _mapStateCodeToEventType(int code) {
    switch (code) {
      case 0x00:
        return 'idle';
      case 0x01:
        return 'walk';
      case 0x02:
        return 'run';
      case 0x10:
        return 'fall_forward';
      case 0x11:
        return 'fall_backward';
      case 0x12:
        return 'fall_lateral';
      case 0x1F:
        return 'fall_generic';
      default:
        return 'unknown_0x${code.toRadixString(16).padLeft(2, '0')}';
    }
  }

  @override
  String toString() {
    return 'ActivityDetectionModel(eventType: $eventType, conf: $confidencePercent%, ts: $timestampEpochSec, fall: $isFall)';
  }
}
