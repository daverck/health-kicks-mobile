import 'dart:typed_data';
import '../../core/constants/ble_constants.dart';
import '../../models/imu_reading_model.dart';

/// IEEE 802.3 CRC32 algorithm (matching Python zlib.crc32).
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

/// Result of processing and reassembling a Burst stream.
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

  bool get isSuccess =>
      isCompleted && isCrcValid && (totalAnnounced == 0 || framesRecovered == totalAnnounced);
}

/// Binary stream reassembler for Studio Data Burst (Characteristic 7a5a0005).
/// Contract reference: contracts/ble_gatt_specs.md (Characteristic 4)
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

  /// Resets state for a new capture session.
  void reset() {
    _rawPayloadBytes.clear();
    _collectedReadings.clear();
    _totalSamplesAnnounced = 0;
    _lastSequenceNum = -1;
    _receivedStart = false;
    _receivedEnd = false;
    _announcedCrc32 = 0;
  }

  /// Processes a binary packet received from the Studio Data Burst characteristic.
  /// Returns a BurstReassemblyResult when the final END_OF_BURST packet is validated,
  /// or null if collection is still in progress.
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

        // Decode each 14-byte IMU frame
        final uint8Payload = Uint8List.fromList(payload);
        for (int offset = 0; offset + BleConstants.bytesPerFrame <= uint8Payload.length; offset += BleConstants.bytesPerFrame) {
          try {
            final frame = ImuReadingModel.fromBytes(uint8Payload, offset);
            _collectedReadings.add(frame);
          } catch (e) {
            // Corrupted frame
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

        // Compute and verify CRC32 over all received bytes
        final computedCrc = Crc32.compute(_rawPayloadBytes);
        final isCrcValid = (computedCrc == _announcedCrc32);

        return BurstReassemblyResult(
          isCompleted: true,
          isCrcValid: isCrcValid,
          totalAnnounced: _totalSamplesAnnounced,
          framesRecovered: _collectedReadings.length,
          readings: List.unmodifiable(_collectedReadings),
          errorMessage: isCrcValid ? null : 'CRC32 integrity check failed (expected: $_announcedCrc32, computed: $computedCrc)',
        );

      default:
        return null;
    }
  }
}
