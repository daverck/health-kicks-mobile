import 'dart:typed_data';
import '../../core/constants/ble_constants.dart';
import '../../models/imu_reading_model.dart';

/// Algorithme CRC32 conforme IEEE 802.3 (identique à Python zlib.crc32).
class Crc32 {
  static final List<int> _table = _generateTable();

  static List<int> _generateTable() {
    final table = List<int>.filled(256, 0);
    for (int i = 0; i < 256; i++) {
      int c = i;
      for (int j = 0; j < 8; j++) {
        c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      }
      table[i] = c;
    }
    return table;
  }

  static int compute(List<int> bytes) {
    int crc = 0xFFFFFFFF;
    for (final b in bytes) {
      crc = _table[(crc ^ b) & 0xFF] ^ (crc >>> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}

/// Résultat du traitement et de l'assemblage d'un flux Burst.
class BurstReassemblyResult {
  final bool isCompleted;
  final bool isCrcValid;
  final int totalAnnounced;
  final int framesRecovered;
  final List<ImuReadingModel> readings;
  final String? errorMessage;

  const BurstReassemblyResult({
    required this.isCompleted,
    required this.isCrcValid,
    required this.totalAnnounced,
    required this.framesRecovered,
    required this.readings,
    this.errorMessage,
  });

  bool get isSuccess => isCompleted && isCrcValid && (framesRecovered == totalAnnounced);
}

/// Réassembleur de flux binaire Studio Data Burst (Caractéristique 7a5a0005).
/// Référence contractuelle : contracts/ble_gatt_specs.md (Caractéristique 4)
class BurstReassembler {
  final List<int> _rawPayloadBytes = [];
  final List<ImuReadingModel> _collectedReadings = [];

  int _totalSamplesAnnounced = 0;
  int _lastSequenceNum = -1;
  bool _receivedStart = false;
  bool _receivedEnd = false;
  int _announcedCrc32 = 0;

  bool get isCollecting => _receivedStart && !_receivedEnd;
  int get samplesCount => _collectedReadings.length;
  int get lastSequenceNum => _lastSequenceNum;

  /// Réinitialise l'état pour une nouvelle session de capture.
  void reset() {
    _rawPayloadBytes.clear();
    _collectedReadings.clear();
    _totalSamplesAnnounced = 0;
    _lastSequenceNum = -1;
    _receivedStart = false;
    _receivedEnd = false;
    _announcedCrc32 = 0;
  }

  /// Traite un paquet binaire reçu de la caractéristique Studio Data Burst.
  /// Retourne un BurstReassemblyResult lorsque le paquet final END_OF_BURST est validé,
  /// ou null si la collecte est toujours en cours.
  BurstReassemblyResult? processPacket(List<int> rawPacket) {
    if (rawPacket.length < 4) {
      return null;
    }

    final byteData = ByteData.sublistView(Uint8List.fromList(rawPacket));
    final packetType = byteData.getUint8(0);
    final seqNum = byteData.getUint16(1, Endian.big);
    final payloadLen = byteData.getUint8(3);
    final payload = rawPacket.sublist(4);

    if (payload.length < payloadLen) {
      return null;
    }

    _lastSequenceNum = seqNum;

    switch (packetType) {
      case BleConstants.packetTypeStartOfBurst:
        reset();
        _receivedStart = true;
        if (payload.length >= 4) {
          final pData = ByteData.sublistView(Uint8List.fromList(payload));
          _totalSamplesAnnounced = pData.getUint32(0, Endian.big);
        }
        return null;

      case BleConstants.packetTypeDataChunk:
        if (!_receivedStart) {
          _receivedStart = true;
        }
        _rawPayloadBytes.addAll(payload);

        // Décoder chaque trame IMU de 14 octets
        final uint8Payload = Uint8List.fromList(payload);
        for (int offset = 0; offset + BleConstants.bytesPerFrame <= uint8Payload.length; offset += BleConstants.bytesPerFrame) {
          try {
            final frame = ImuReadingModel.fromBytes(uint8Payload, offset);
            _collectedReadings.add(frame);
          } catch (e) {
            // Trame altérée
          }
        }
        return null;

      case BleConstants.packetTypeEndOfBurst:
        _receivedEnd = true;
        if (payload.length >= 8) {
          final pData = ByteData.sublistView(Uint8List.fromList(payload));
          final endSamples = pData.getUint32(0, Endian.big);
          _announcedCrc32 = pData.getUint32(4, Endian.big);
          if (_totalSamplesAnnounced == 0) {
            _totalSamplesAnnounced = endSamples;
          }
        }

        // Calcul et vérification du CRC32 sur l'ensemble des octets reçus
        final computedCrc = Crc32.compute(_rawPayloadBytes);
        final isCrcValid = (computedCrc == _announcedCrc32);

        return BurstReassemblyResult(
          isCompleted: true,
          isCrcValid: isCrcValid,
          totalAnnounced: _totalSamplesAnnounced,
          framesRecovered: _collectedReadings.length,
          readings: List.unmodifiable(_collectedReadings),
          errorMessage: isCrcValid ? null : 'Erreur intégrité CRC32 (attendu: $_announcedCrc32, calculé: $computedCrc)',
        );

      default:
        return null;
    }
  }
}
