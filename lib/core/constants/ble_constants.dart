/// Constantes et UUIDs du profil GATT HealthKicks
/// Référence contractuelle : contracts/ble_gatt_specs.md
class BleConstants {
  static const String baseUuid = '7a5a0000-c529-4d64-8848-18e5904de22a';

  /// Primary Service UUID
  static const String footwearServiceUuid = '7a5a0001-c529-4d64-8848-18e5904de22a';

  /// Caractéristique 1 : Activity Detection (READ, NOTIFY)
  static const String activityDetectionCharUuid = '7a5a0002-c529-4d64-8848-18e5904de22a';

  /// Caractéristique 2 : Haptic Command (WRITE, WRITE WITHOUT RESPONSE)
  static const String hapticCommandCharUuid = '7a5a0003-c529-4d64-8848-18e5904de22a';

  /// Caractéristique 3 : Studio Control (WRITE, NOTIFY)
  static const String studioControlCharUuid = '7a5a0004-c529-4d64-8848-18e5904de22a';

  /// Caractéristique 4 : Studio Data Burst (NOTIFY)
  static const String studioDataBurstCharUuid = '7a5a0005-c529-4d64-8848-18e5904de22a';

  // Packet types pour le Burst Transfer
  static const int packetTypeStartOfBurst = 0x01;
  static const int packetTypeDataChunk = 0x02;
  static const int packetTypeEndOfBurst = 0x03;

  // Fréquence nominale IMU
  static const int sampleRateHz = 50;
  static const int bytesPerFrame = 14;

  /// Durée maximale de scan avant arrêt automatique si aucun équipement n'est trouvé
  static const Duration defaultScanTimeout = Duration(minutes: 3);
}
