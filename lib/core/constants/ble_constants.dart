/// HealthKicks GATT profile constants and UUIDs
/// Contract reference: contracts/ble_gatt_specs.md
class BleConstants {
  static const String baseUuid = '7a5a0000-c529-4d64-8848-18e5904de22a';

  /// Primary Service UUID
  static const String footwearServiceUuid = '7a5a0001-c529-4d64-8848-18e5904de22a';

  /// Characteristic 1: Activity Detection (READ, NOTIFY)
  static const String activityDetectionCharUuid = '7a5a0002-c529-4d64-8848-18e5904de22a';

  /// Characteristic 2: Haptic Command (WRITE, WRITE WITHOUT RESPONSE)
  static const String hapticCommandCharUuid = '7a5a0003-c529-4d64-8848-18e5904de22a';

  /// Characteristic 3: Studio Control (WRITE, NOTIFY)
  static const String studioControlCharUuid = '7a5a0004-c529-4d64-8848-18e5904de22a';

  /// Characteristic 4: Studio Data Burst (NOTIFY)
  static const String studioDataBurstCharUuid = '7a5a0005-c529-4d64-8848-18e5904de22a';

  /// Characteristic 5: Step Counter / Pedometer (READ, NOTIFY)
  static const String stepCounterCharUuid = '7a5a0006-c529-4d64-8848-18e5904de22a';

  // Packet types for Burst Transfer
  static const int packetTypeStartOfBurst = 0x01;
  static const int packetTypeDataChunk = 0x02;
  static const int packetTypeEndOfBurst = 0x03;

  /// Command opcode to trigger level/tilt zero calibration (Characteristic 0003 & 0004)
  static const int commandCalibrateZero = 0x05;

  /// Command opcode to configure prolonged inactivity reminder (Characteristic 0003)
  static const int commandSetInactivity = 0x06;

  /// State code for prolonged inactivity alert (Characteristic 0002)
  static const int stateCodeInactivityAlert = 0x20;

  // Nominal IMU sampling rate
  static const int sampleRateHz = 50;
  static const int bytesPerFrame = 14;

  /// Maximum scan duration before automatic timeout if no device is found
  static const Duration defaultScanTimeout = Duration(minutes: 3);
}
