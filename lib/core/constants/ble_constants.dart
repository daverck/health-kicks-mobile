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

  /// Secondary Service: OTA Firmware Update
  static const String otaServiceUuid = '7a5a0010-c529-4d64-8848-18e5904de22a';

  /// OTA Characteristic 1: OTA Control (WRITE, NOTIFY)
  static const String otaControlCharUuid = '7a5a0011-c529-4d64-8848-18e5904de22a';

  /// OTA Characteristic 2: OTA Data (WRITE, WRITE WITHOUT RESPONSE)
  static const String otaDataCharUuid = '7a5a0012-c529-4d64-8848-18e5904de22a';

  /// Standard Bluetooth SIG Device Information Service (DIS 0x180A)
  static const String disServiceUuid = '180a';
  static const String firmwareRevisionCharUuid = '2a26';
  static const String softwareRevisionCharUuid = '2a28';

  // OTA Commands (Phone -> ESP32)
  static const int otaCmdBegin = 0x01;
  static const int otaCmdEnd = 0x02;
  static const int otaCmdAbort = 0x03;

  // OTA Notifications (ESP32 -> Phone)
  static const int otaRespReady = 0x10;
  static const int otaRespChunkAck = 0x11;
  static const int otaRespSuccess = 0x12;
  static const int otaRespError = 0xFF;
  static const int otaErrChecksumMismatch = 0x07;

  // Packet types for Burst Transfer
  static const int packetTypeStartOfBurst = 0x01;
  static const int packetTypeDataChunk = 0x02;
  static const int packetTypeEndOfBurst = 0x03;
  static const int packetTypeDeltaChunk = 0x04;

  /// Command opcode to trigger level/tilt zero calibration (Characteristic 0003 & 0004)
  static const int commandCalibrateZero = 0x05;

  /// Command opcode to configure prolonged inactivity reminder (Characteristic 0003)
  static const int commandSetInactivity = 0x06;

  /// State code for prolonged inactivity alert (Characteristic 0002)
  static const int stateCodeInactivityAlert = 0x20;

  /// State codes for activities (Characteristic 0002)
  static const int stateCodeIdle = 0x00;
  static const int stateCodeWalk = 0x01;
  static const int stateCodeRun = 0x02;
  static const int stateCodeStairsUp = 0x03;
  static const int stateCodeStairsDown = 0x04;
  static const int stateCodeSitDown = 0x05;
  static const int stateCodeFallForward = 0x10;
  static const int stateCodeFallBackward = 0x11;
  static const int stateCodeFallLateral = 0x12;
  static const int stateCodeFallRecovery = 0x13;
  static const int stateCodeStumbleRecover = 0x1E;
  static const int stateCodeFallGeneric = 0x1F;

  // Nominal IMU sampling rate
  static const int sampleRateHz = 50;
  static const int bytesPerFrame = 14;

  /// Maximum scan duration before automatic timeout if no device is found
  static const Duration defaultScanTimeout = Duration(minutes: 3);
}
