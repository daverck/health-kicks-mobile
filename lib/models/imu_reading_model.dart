import 'dart:typed_data';

/// Model representing an unpacked 6-axis IMU inertial frame (14 bytes) received during Burst Transfer.
/// Contract reference: contracts/ble_gatt_specs.md (Characteristic 4)
class ImuReadingModel {
  final int deltaMs;
  final double ax;
  final double ay;
  final double az;
  final double gx;
  final double gy;
  final double gz;

  const ImuReadingModel({
    required this.deltaMs,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
  });

  /// Decodes 14 bytes of a Big-Endian IMU frame:
  /// delta_ms: uint16, ax/ay/az: 3x int16 (milli-g / 1000.0), gx/gy/gz: 3x int16 (0.1 deg/s / 10.0)
  factory ImuReadingModel.fromBytes(Uint8List bytes, int offset) {
    if (bytes.length < offset + 14) {
      throw FormatException(
        'Truncated IMU frame: expected 14 bytes at offset $offset, total available: ${bytes.length}',
      );
    }

    final byteData = ByteData.sublistView(bytes, offset, offset + 14);

    final deltaMs = byteData.getUint16(0, Endian.big);
    final axRaw = byteData.getInt16(2, Endian.big);
    final ayRaw = byteData.getInt16(4, Endian.big);
    final azRaw = byteData.getInt16(6, Endian.big);
    final gxRaw = byteData.getInt16(8, Endian.big);
    final gyRaw = byteData.getInt16(10, Endian.big);
    final gzRaw = byteData.getInt16(12, Endian.big);

    return ImuReadingModel(
      deltaMs: deltaMs,
      ax: axRaw / 1000.0,
      ay: ayRaw / 1000.0,
      az: azRaw / 1000.0,
      gx: gxRaw / 10.0,
      gy: gyRaw / 10.0,
      gz: gzRaw / 10.0,
    );
  }

  /// Serializes to JSON dictionary conforming to DynamoDB Backend requirements.
  Map<String, dynamic> toJson(double sessionStartTimestamp) {
    return {
      'timestamp': sessionStartTimestamp + (deltaMs / 1000.0),
      'ax': ax,
      'ay': ay,
      'az': az,
      'gx': gx,
      'gy': gy,
      'gz': gz,
    };
  }

  @override
  String toString() {
    return 'ImuReading(delta: ${deltaMs}ms, accel: [$ax, $ay, $az] g, gyro: [$gx, $gy, $gz] deg/s)';
  }
}
