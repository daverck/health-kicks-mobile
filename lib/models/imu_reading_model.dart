import 'dart:typed_data';

/// Modèle d'une trame inertielle IMU découpée (14 octets) reçue lors d'un Burst Transfer.
/// Référence contractuelle : contracts/ble_gatt_specs.md (Caractéristique 4)
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

  /// Décode les 14 octets d'une trame IMU Big-Endian :
  /// delta_ms: uint16, ax/ay/az: 3x int16 (milli-g / 1000.0), gx/gy/gz: 3x int16 (0.1 deg/s / 10.0)
  factory ImuReadingModel.fromBytes(Uint8List bytes, int offset) {
    if (bytes.length < offset + 14) {
      throw FormatException(
        'Trame IMU tronquée : attendu 14 octets à l\'offset $offset, total disponible: ${bytes.length}',
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

  /// Sérialise en dictionnaire JSON conforme aux attentes du Backend DynamoDB.
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
