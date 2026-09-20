import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/core/constants/ble_constants.dart';
import 'package:healthkicks_mobile/models/imu_reading_model.dart';
import 'package:healthkicks_mobile/services/ble/burst_reassembler.dart';

void main() {
  group('BurstReassembler & Crc32 - Studio Integrity and Reassembly', () {
    test('CRC32 calculation compliant with standard IEEE 802.3 test vector ("123456789")', () {
      final asciiBytes = utf8.encode('123456789');
      final crc = Crc32.compute(asciiBytes);
      // 0xCBF43926 = 3421780262
      expect(crc, equals(0xCBF43926));
    });

    test('Accurate decoding of a 14-byte IMU frame with scaling factors', () {
      // delta: 1500 ms, ax: 0.050 g (50), ay: 0.980 g (980), az: -0.120 g (-120)
      // gx: 12.5 deg/s (125), gy: -4.0 deg/s (-40), gz: 0.8 deg/s (8)
      final byteData = ByteData(14);
      byteData.setUint16(0, 1500, Endian.big);
      byteData.setInt16(2, 50, Endian.big);
      byteData.setInt16(4, 980, Endian.big);
      byteData.setInt16(6, -120, Endian.big);
      byteData.setInt16(8, 125, Endian.big);
      byteData.setInt16(10, -40, Endian.big);
      byteData.setInt16(12, 8, Endian.big);

      final frame = ImuReadingModel.fromBytes(byteData.buffer.asUint8List(), 0);

      expect(frame.deltaMs, equals(1500));
      expect(frame.ax, closeTo(0.050, 0.0001));
      expect(frame.ay, closeTo(0.980, 0.0001));
      expect(frame.az, closeTo(-0.120, 0.0001));
      expect(frame.gx, closeTo(12.5, 0.001));
      expect(frame.gy, closeTo(-4.0, 0.001));
      expect(frame.gz, closeTo(0.8, 0.001));
    });

    test('Reassembles a stream of 50 frames distributed over multiple packets with CRC32 validation', () {
      final reassembler = BurstReassembler();
      const totalFrames = 50;

      // 1. START_OF_BURST packet (type: 0x01, seq: 0, count: 50)
      final startData = ByteData(8);
      startData.setUint8(0, BleConstants.packetTypeStartOfBurst);
      startData.setUint16(1, 0, Endian.big);
      startData.setUint8(3, 0);
      startData.setUint32(4, totalFrames, Endian.big);

      expect(reassembler.processPacket(startData.buffer.asUint8List()), isNull);
      expect(reassembler.isCollecting, isTrue);

      // Generate 50 binary frames (50 * 14 = 700 bytes payload)
      final allPayloadBytes = <int>[];
      for (int i = 0; i < totalFrames; i++) {
        final bData = ByteData(14);
        bData.setUint16(0, i * 20, Endian.big);
        bData.setInt16(2, (i * 10).clamp(-32768, 32767), Endian.big);
        bData.setInt16(4, 980, Endian.big);
        bData.setInt16(6, 120, Endian.big);
        bData.setInt16(8, 0, Endian.big);
        bData.setInt16(10, 0, Endian.big);
        bData.setInt16(12, 0, Endian.big);
        allPayloadBytes.addAll(bData.buffer.asUint8List());
      }

      final expectedCrc = Crc32.compute(allPayloadBytes);

      // 2. Split into DATA_CHUNK packets of 10 frames (140 bytes payload + 4 bytes header)
      int seqNum = 1;
      for (int offset = 0; offset < allPayloadBytes.length; offset += 140) {
        final chunkSlice = allPayloadBytes.sublist(offset, offset + 140);
        final chunkHeader = ByteData(4);
        chunkHeader.setUint8(0, BleConstants.packetTypeDataChunk);
        chunkHeader.setUint16(1, seqNum++, Endian.big);
        chunkHeader.setUint8(3, 10); // 10 frames

        final packetBytes = chunkHeader.buffer.asUint8List() + chunkSlice;
        final res = reassembler.processPacket(packetBytes);
        expect(res, isNull);
      }

      // 3. END_OF_BURST packet (type: 0x03, seq: seqNum, total: 50, crc: expectedCrc)
      final endData = ByteData(12);
      endData.setUint8(0, BleConstants.packetTypeEndOfBurst);
      endData.setUint16(1, seqNum, Endian.big);
      endData.setUint8(3, 0);
      endData.setUint32(4, totalFrames, Endian.big);
      endData.setUint32(8, expectedCrc, Endian.big);

      final finalResult = reassembler.processPacket(endData.buffer.asUint8List());

      expect(finalResult, isNotNull);
      expect(finalResult!.isCompleted, isTrue);
      expect(finalResult.isCrcValid, isTrue);
      expect(finalResult.totalAnnounced, equals(50));
      expect(finalResult.framesRecovered, equals(50));
      expect(finalResult.isSuccess, isTrue);
      expect(finalResult.errorMessage, isNull);
    });

    test('Rejects stream when received CRC32 checksum is corrupted', () {
      final reassembler = BurstReassembler();

      // START
      final startData = ByteData(8);
      startData.setUint8(0, BleConstants.packetTypeStartOfBurst);
      startData.setUint32(4, 1, Endian.big);
      reassembler.processPacket(startData.buffer.asUint8List());

      // 1 CHUNK with 14 bytes
      final chunkData = Uint8List(4 + 14);
      chunkData[0] = BleConstants.packetTypeDataChunk;
      chunkData[3] = 1;
      reassembler.processPacket(chunkData);

      // END with invalid CRC
      final endData = ByteData(12);
      endData.setUint8(0, BleConstants.packetTypeEndOfBurst);
      endData.setUint32(4, 1, Endian.big);
      endData.setUint32(8, 0x12345678, Endian.big); // Invalid CRC

      final result = reassembler.processPacket(endData.buffer.asUint8List());

      expect(result, isNotNull);
      expect(result!.isCompleted, isTrue);
      expect(result.isCrcValid, isFalse);
      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('CRC32 integrity error'));
    });
  });
}
