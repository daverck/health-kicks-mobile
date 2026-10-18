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

      case BleConstants.packetTypeDeltaChunk:
        if (!_receivedStart) {
          _receivedStart = true;
        }
        if (payload.length < 15) {
          return null;
        }

        final deltaUint8Payload = Uint8List.fromList(payload);
        final pData = ByteData.sublistView(deltaUint8Payload);
        final frameCount = pData.getUint8(0);

        final expectedMinLen = 1 + BleConstants.bytesPerFrame + (frameCount - 1) * 7;
        if (deltaUint8Payload.length < expectedMinLen) {
          return null;
        }

        // 1. Decode Keyframe (14 bytes starting at offset 1)
        int runningDeltaMs = pData.getUint16(1, Endian.big);
        int runningAx = pData.getInt16(3, Endian.big);
        int runningAy = pData.getInt16(5, Endian.big);
        int runningAz = pData.getInt16(7, Endian.big);
        int runningGx = pData.getInt16(9, Endian.big);
        int runningGy = pData.getInt16(11, Endian.big);
        int runningGz = pData.getInt16(13, Endian.big);

        _collectedReadings.add(ImuReadingModel(
          deltaMs: runningDeltaMs,
          ax: runningAx / 1000.0,
          ay: runningAy / 1000.0,
          az: runningAz / 1000.0,
          gx: runningGx / 10.0,
          gy: runningGy / 10.0,
          gz: runningGz / 10.0,
        ));
        _rawPayloadBytes.addAll(deltaUint8Payload.sublist(1, 15));

        // 2. Decode subsequent (frameCount - 1) delta frames (7 bytes each)
        int deltaOffset = 15;
        for (int i = 1; i < frameCount; i++) {
          final dMs = pData.getUint8(deltaOffset);
          final dAx = pData.getInt8(deltaOffset + 1);
          final dAy = pData.getInt8(deltaOffset + 2);
          final dAz = pData.getInt8(deltaOffset + 3);
          final dGx = pData.getInt8(deltaOffset + 4);
          final dGy = pData.getInt8(deltaOffset + 5);
          final dGz = pData.getInt8(deltaOffset + 6);

          runningDeltaMs += dMs;
          runningAx += dAx;
          runningAy += dAy;
          runningAz += dAz;
          runningGx += dGx;
          runningGy += dGy;
          runningGz += dGz;

          _collectedReadings.add(ImuReadingModel(
            deltaMs: runningDeltaMs,
            ax: runningAx / 1000.0,
            ay: runningAy / 1000.0,
            az: runningAz / 1000.0,
            gx: runningGx / 10.0,
            gy: runningGy / 10.0,
            gz: runningGz / 10.0,
          ));

          final reconstructed = ByteData(14);
          reconstructed.setUint16(0, runningDeltaMs, Endian.big);
          reconstructed.setInt16(2, runningAx, Endian.big);
          reconstructed.setInt16(4, runningAy, Endian.big);
          reconstructed.setInt16(6, runningAz, Endian.big);
          reconstructed.setInt16(8, runningGx, Endian.big);
          reconstructed.setInt16(10, runningGy, Endian.big);
          reconstructed.setInt16(12, runningGz, Endian.big);
          _rawPayloadBytes.addAll(reconstructed.buffer.asUint8List());

          deltaOffset += 7;
        }
        return null;

      case BleConstants.packetTypeRleChunk:
        if (!_receivedStart) {
          _receivedStart = true;
        }
        if (payload.length < 16) {
          return null;
        }

        final rleUint8Payload = Uint8List.fromList(payload);
        final rleData = ByteData.sublistView(rleUint8Payload);
        final runCount = rleData.getUint8(0);
        final startDeltaMs = rleData.getUint16(1, Endian.big);
        final stepMs = rleData.getUint8(3);
        final rleAx = rleData.getInt16(4, Endian.big);
        final rleAy = rleData.getInt16(6, Endian.big);
        final rleAz = rleData.getInt16(8, Endian.big);
        final rleGx = rleData.getInt16(10, Endian.big);
        final rleGy = rleData.getInt16(12, Endian.big);
        final rleGz = rleData.getInt16(14, Endian.big);

        for (int i = 0; i < runCount; i++) {
          final curDeltaMs = startDeltaMs + i * stepMs;
          _collectedReadings.add(ImuReadingModel(
            deltaMs: curDeltaMs,
            ax: rleAx / 1000.0,
            ay: rleAy / 1000.0,
            az: rleAz / 1000.0,
            gx: rleGx / 10.0,
            gy: rleGy / 10.0,
            gz: rleGz / 10.0,
          ));

          final reconstructed = ByteData(14);
          reconstructed.setUint16(0, curDeltaMs, Endian.big);
          reconstructed.setInt16(2, rleAx, Endian.big);
          reconstructed.setInt16(4, rleAy, Endian.big);
          reconstructed.setInt16(6, rleAz, Endian.big);
          reconstructed.setInt16(8, rleGx, Endian.big);
          reconstructed.setInt16(10, rleGy, Endian.big);
          reconstructed.setInt16(12, rleGz, Endian.big);
          _rawPayloadBytes.addAll(reconstructed.buffer.asUint8List());
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
