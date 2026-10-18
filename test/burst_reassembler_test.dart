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
      expect(result.errorMessage, contains('CRC32 integrity check failed'));
    });

    test('Accurate decoding of a DELTA_CHUNK packet with keyframe and delta frames', () {
      final reassembler = BurstReassembler();

      // Keyframe: delta_ms=1000, ax=50, ay=980, az=-120, gx=125, gy=-40, gz=8
      // Delta 1: dMs=20, dAx=2, dAy=-5, dAz=1, dGx=-3, dGy=2, dGz=0
      // Delta 2: dMs=20, dAx=-4, dAy=3, dAz=-2, dGx=1, dGy=-1, dGz=1
      const frameCount = 3;
      final payloadBytes = 1 + 14 + 2 * 7; // 29 bytes
      final packet = ByteData(4 + payloadBytes);

      // 4-byte header
      packet.setUint8(0, BleConstants.packetTypeDeltaChunk);
      packet.setUint16(1, 0, Endian.big);
      packet.setUint8(3, payloadBytes);

      // Payload
      packet.setUint8(4, frameCount);

      // Keyframe (offset 5..18)
      packet.setUint16(5, 1000, Endian.big);
      packet.setInt16(7, 50, Endian.big);
      packet.setInt16(9, 980, Endian.big);
      packet.setInt16(11, -120, Endian.big);
      packet.setInt16(13, 125, Endian.big);
      packet.setInt16(15, -40, Endian.big);
      packet.setInt16(17, 8, Endian.big);

      // Delta 1 (offset 19..25)
      packet.setUint8(19, 20);
      packet.setInt8(20, 2);
      packet.setInt8(21, -5);
      packet.setInt8(22, 1);
      packet.setInt8(23, -3);
      packet.setInt8(24, 2);
      packet.setInt8(25, 0);

      // Delta 2 (offset 26..32)
      packet.setUint8(26, 20);
      packet.setInt8(27, -4);
      packet.setInt8(28, 3);
      packet.setInt8(29, -2);
      packet.setInt8(30, 1);
      packet.setInt8(31, -1);
      packet.setInt8(32, 1);

      expect(reassembler.processPacket(packet.buffer.asUint8List()), isNull);
      expect(reassembler.samplesCount, equals(3));

      // Check reconstructed Keyframe
      final endPacket = ByteData(12);
      endPacket.setUint8(0, BleConstants.packetTypeEndOfBurst);
      endPacket.setUint32(4, 3, Endian.big);

      // Compute expected CRC32 over the 3 reconstructed 14-byte frames
      final expectedRaw = ByteData(42);
      // Frame 0: 1000, 50, 980, -120, 125, -40, 8
      expectedRaw.setUint16(0, 1000, Endian.big);
      expectedRaw.setInt16(2, 50, Endian.big);
      expectedRaw.setInt16(4, 980, Endian.big);
      expectedRaw.setInt16(6, -120, Endian.big);
      expectedRaw.setInt16(8, 125, Endian.big);
      expectedRaw.setInt16(10, -40, Endian.big);
      expectedRaw.setInt16(12, 8, Endian.big);
      // Frame 1: 1020, 52, 975, -119, 122, -38, 8
      expectedRaw.setUint16(14, 1020, Endian.big);
      expectedRaw.setInt16(16, 52, Endian.big);
      expectedRaw.setInt16(18, 975, Endian.big);
      expectedRaw.setInt16(20, -119, Endian.big);
      expectedRaw.setInt16(22, 122, Endian.big);
      expectedRaw.setInt16(24, -38, Endian.big);
      expectedRaw.setInt16(26, 8, Endian.big);
      // Frame 2: 1040, 48, 978, -121, 123, -39, 9
      expectedRaw.setUint16(28, 1040, Endian.big);
      expectedRaw.setInt16(30, 48, Endian.big);
      expectedRaw.setInt16(32, 978, Endian.big);
      expectedRaw.setInt16(34, -121, Endian.big);
      expectedRaw.setInt16(36, 123, Endian.big);
      expectedRaw.setInt16(38, -39, Endian.big);
      expectedRaw.setInt16(40, 9, Endian.big);

      final expectedCrc = Crc32.compute(expectedRaw.buffer.asUint8List());
      endPacket.setUint32(8, expectedCrc, Endian.big);

      final result = reassembler.processPacket(endPacket.buffer.asUint8List());
      expect(result, isNotNull);
      expect(result!.isSuccess, isTrue);
      expect(result.framesRecovered, equals(3));
      expect(result.isCrcValid, isTrue);

      final r0 = result.readings[0];
      expect(r0.deltaMs, equals(1000));
      expect(r0.ax, closeTo(0.050, 0.0001));
      expect(r0.ay, closeTo(0.980, 0.0001));
      expect(r0.az, closeTo(-0.120, 0.0001));

      final r1 = result.readings[1];
      expect(r1.deltaMs, equals(1020));
      expect(r1.ax, closeTo(0.052, 0.0001));
      expect(r1.ay, closeTo(0.975, 0.0001));
      expect(r1.az, closeTo(-0.119, 0.0001));

      final r2 = result.readings[2];
      expect(r2.deltaMs, equals(1040));
      expect(r2.ax, closeTo(0.048, 0.0001));
      expect(r2.ay, closeTo(0.978, 0.0001));
      expect(r2.az, closeTo(-0.121, 0.0001));
    });

    test('Reassembles a mixed stream with both DELTA_CHUNK and DATA_CHUNK packets verified by CRC32', () {
      final reassembler = BurstReassembler();
      const totalFrames = 30;

      // START
      final startData = ByteData(8);
      startData.setUint8(0, BleConstants.packetTypeStartOfBurst);
      startData.setUint32(4, totalFrames, Endian.big);
      reassembler.processPacket(startData.buffer.asUint8List());

      // Generate 30 smooth consecutive raw frames
      final allRawBytes = <int>[];
      final rawFramesList = <List<int>>[];
      for (int i = 0; i < totalFrames; i++) {
        final b = ByteData(14);
        b.setUint16(0, i * 20, Endian.big);
        b.setInt16(2, 50 + (i * 2), Endian.big);
        b.setInt16(4, 980 - (i * 1), Endian.big);
        b.setInt16(6, -120 + (i * 1), Endian.big);
        b.setInt16(8, 10 + i, Endian.big);
        b.setInt16(10, -20 + i, Endian.big);
        b.setInt16(12, 5, Endian.big);
        final bytes = b.buffer.asUint8List();
        rawFramesList.add(bytes);
        allRawBytes.addAll(bytes);
      }

      final expectedCrc = Crc32.compute(allRawBytes);

      // Packet 1: DELTA_CHUNK with frames 0..19 (1 keyframe + 19 deltas = 20 frames)
      const deltaCount = 19;
      final p1PayloadLen = 1 + 14 + deltaCount * 7;
      final p1 = ByteData(4 + p1PayloadLen);
      p1.setUint8(0, BleConstants.packetTypeDeltaChunk);
      p1.setUint16(1, 0, Endian.big);
      p1.setUint8(3, p1PayloadLen);
      p1.setUint8(4, 20); // frameCount
      // Keyframe = frame 0
      for (int b = 0; b < 14; b++) {
        p1.setUint8(5 + b, rawFramesList[0][b]);
      }
      // 19 deltas
      int off = 19;
      for (int i = 1; i <= deltaCount; i++) {
        p1.setUint8(off + 0, 20); // dMs = 20
        p1.setInt8(off + 1, 2);  // dAx = 2
        p1.setInt8(off + 2, -1); // dAy = -1
        p1.setInt8(off + 3, 1);  // dAz = 1
        p1.setInt8(off + 4, 1);  // dGx = 1
        p1.setInt8(off + 5, 1);  // dGy = 1
        p1.setInt8(off + 6, 0);  // dGz = 0
        off += 7;
      }
      expect(reassembler.processPacket(p1.buffer.asUint8List()), isNull);
      expect(reassembler.samplesCount, equals(20));

      // Packet 2: DATA_CHUNK with frames 20..29 (10 raw frames = 140 bytes)
      final p2Bytes = <int>[];
      for (int i = 20; i < 30; i++) {
        p2Bytes.addAll(rawFramesList[i]);
      }
      final p2Header = ByteData(4);
      p2Header.setUint8(0, BleConstants.packetTypeDataChunk);
      p2Header.setUint16(1, 1, Endian.big);
      p2Header.setUint8(3, 140);
      expect(reassembler.processPacket(p2Header.buffer.asUint8List() + p2Bytes), isNull);
      expect(reassembler.samplesCount, equals(30));

      // Packet 3: END_OF_BURST with expected CRC
      final pEnd = ByteData(12);
      pEnd.setUint8(0, BleConstants.packetTypeEndOfBurst);
      pEnd.setUint16(1, 2, Endian.big);
      pEnd.setUint32(4, 30, Endian.big);
      pEnd.setUint32(8, expectedCrc, Endian.big);

      final result = reassembler.processPacket(pEnd.buffer.asUint8List());
      expect(result, isNotNull);
      expect(result!.isSuccess, isTrue);
      expect(result.framesRecovered, equals(30));
      expect(result.isCrcValid, isTrue);
      expect(result.readings.length, equals(30));
    });

    test('Accurate decoding of an RLE_CHUNK packet with repeated static frames', () {
      final reassembler = BurstReassembler();
      const runCount = 10;
      const startDeltaMs = 500;
      const stepMs = 20;

      // 1. Send RLE_CHUNK packet (4 bytes header + 16 bytes payload = 20 bytes)
      final rlePacket = ByteData(20);
      rlePacket.setUint8(0, BleConstants.packetTypeRleChunk);
      rlePacket.setUint16(1, 0, Endian.big);
      rlePacket.setUint8(3, 16); // payload length

      rlePacket.setUint8(4, runCount);
      rlePacket.setUint16(5, startDeltaMs, Endian.big);
      rlePacket.setUint8(7, stepMs);
      rlePacket.setInt16(8, 0, Endian.big);    // ax = 0 mg
      rlePacket.setInt16(10, 0, Endian.big);   // ay = 0 mg
      rlePacket.setInt16(12, 1000, Endian.big); // az = 1000 mg (1.0g vertical)
      rlePacket.setInt16(14, 0, Endian.big);   // gx = 0 dps
      rlePacket.setInt16(16, 0, Endian.big);   // gy = 0 dps
      rlePacket.setInt16(18, 0, Endian.big);   // gz = 0 dps

      expect(reassembler.processPacket(rlePacket.buffer.asUint8List()), isNull);
      expect(reassembler.samplesCount, equals(runCount));

      // 2. Build expected 10 raw frames (140 bytes) to compute expected CRC32
      final rawBytes = <int>[];
      for (int i = 0; i < runCount; i++) {
        final b = ByteData(14);
        b.setUint16(0, startDeltaMs + i * stepMs, Endian.big);
        b.setInt16(2, 0, Endian.big);
        b.setInt16(4, 0, Endian.big);
        b.setInt16(6, 1000, Endian.big);
        b.setInt16(8, 0, Endian.big);
        b.setInt16(10, 0, Endian.big);
        b.setInt16(12, 0, Endian.big);
        rawBytes.addAll(b.buffer.asUint8List());
      }
      final expectedCrc = Crc32.compute(rawBytes);

      // 3. Send END_OF_BURST
      final endPacket = ByteData(12);
      endPacket.setUint8(0, BleConstants.packetTypeEndOfBurst);
      endPacket.setUint16(1, 1, Endian.big);
      endPacket.setUint32(4, runCount, Endian.big);
      endPacket.setUint32(8, expectedCrc, Endian.big);

      final result = reassembler.processPacket(endPacket.buffer.asUint8List());
      expect(result, isNotNull);
      expect(result!.isSuccess, isTrue);
      expect(result.framesRecovered, equals(runCount));
      expect(result.isCrcValid, isTrue);
      expect(result.readings.length, equals(runCount));
      expect(result.readings.first.deltaMs, equals(500));
      expect(result.readings.first.az, closeTo(1.0, 0.0001));
      expect(result.readings.last.deltaMs, equals(500 + 9 * 20));
      expect(result.readings.last.az, closeTo(1.0, 0.0001));
    });

    test('Mixed multi-packet stream with RLE_CHUNK, DELTA_CHUNK and DATA_CHUNK validated by CRC32', () {
      final reassembler = BurstReassembler();
      final allRawBytes = <int>[];

      // Phase 1: 5 identical frames (RLE) from t=0 to t=80ms
      for (int i = 0; i < 5; i++) {
        final b = ByteData(14);
        b.setUint16(0, i * 20, Endian.big);
        b.setInt16(2, 10, Endian.big);
        b.setInt16(4, 20, Endian.big);
        b.setInt16(6, 980, Endian.big);
        b.setInt16(8, 0, Endian.big);
        b.setInt16(10, 0, Endian.big);
        b.setInt16(12, 0, Endian.big);
        allRawBytes.addAll(b.buffer.asUint8List());
      }

      // Phase 2: 3 delta frames from t=100ms
      // Frame 5 (keyframe): t=100, ax=10, ay=20, az=980, gx=0, gy=0, gz=0
      // Frame 6: t=120, ax=15 (+5), ay=18 (-2), az=983 (+3), gx=2 (+2), gy=0, gz=-1 (-1)
      // Frame 7: t=140, ax=18 (+3), ay=16 (-2), az=985 (+2), gx=4 (+2), gy=1 (+1), gz=-1 (0)
      final f5 = ByteData(14);
      f5.setUint16(0, 100, Endian.big);
      f5.setInt16(2, 10, Endian.big);
      f5.setInt16(4, 20, Endian.big);
      f5.setInt16(6, 980, Endian.big);
      f5.setInt16(8, 0, Endian.big);
      f5.setInt16(10, 0, Endian.big);
      f5.setInt16(12, 0, Endian.big);
      allRawBytes.addAll(f5.buffer.asUint8List());

      final f6 = ByteData(14);
      f6.setUint16(0, 120, Endian.big);
      f6.setInt16(2, 15, Endian.big);
      f6.setInt16(4, 18, Endian.big);
      f6.setInt16(6, 983, Endian.big);
      f6.setInt16(8, 2, Endian.big);
      f6.setInt16(10, 0, Endian.big);
      f6.setInt16(12, -1, Endian.big);
      allRawBytes.addAll(f6.buffer.asUint8List());

      final f7 = ByteData(14);
      f7.setUint16(0, 140, Endian.big);
      f7.setInt16(2, 18, Endian.big);
      f7.setInt16(4, 16, Endian.big);
      f7.setInt16(6, 985, Endian.big);
      f7.setInt16(8, 4, Endian.big);
      f7.setInt16(10, 1, Endian.big);
      f7.setInt16(12, -1, Endian.big);
      allRawBytes.addAll(f7.buffer.asUint8List());

      // Phase 3: 2 raw frames (DATA_CHUNK)
      final f8 = ByteData(14);
      f8.setUint16(0, 200, Endian.big);
      f8.setInt16(2, 300, Endian.big);
      f8.setInt16(4, -400, Endian.big);
      f8.setInt16(6, 1500, Endian.big);
      f8.setInt16(8, 250, Endian.big);
      f8.setInt16(10, -120, Endian.big);
      f8.setInt16(12, 80, Endian.big);
      allRawBytes.addAll(f8.buffer.asUint8List());

      final f9 = ByteData(14);
      f9.setUint16(0, 220, Endian.big);
      f9.setInt16(2, 310, Endian.big);
      f9.setInt16(4, -390, Endian.big);
      f9.setInt16(6, 1490, Endian.big);
      f9.setInt16(8, 240, Endian.big);
      f9.setInt16(10, -115, Endian.big);
      f9.setInt16(12, 75, Endian.big);
      allRawBytes.addAll(f9.buffer.asUint8List());

      const totalFrames = 10;
      final expectedCrc = Crc32.compute(allRawBytes);

      // Packet 1: RLE_CHUNK (5 frames)
      final pRle = ByteData(20);
      pRle.setUint8(0, BleConstants.packetTypeRleChunk);
      pRle.setUint16(1, 0, Endian.big);
      pRle.setUint8(3, 16);
      pRle.setUint8(4, 5); // 5 frames
      pRle.setUint16(5, 0, Endian.big);
      pRle.setUint8(7, 20); // 20ms step
      pRle.setInt16(8, 10, Endian.big);
      pRle.setInt16(10, 20, Endian.big);
      pRle.setInt16(12, 980, Endian.big);
      pRle.setInt16(14, 0, Endian.big);
      pRle.setInt16(16, 0, Endian.big);
      pRle.setInt16(18, 0, Endian.big);
      expect(reassembler.processPacket(pRle.buffer.asUint8List()), isNull);
      expect(reassembler.samplesCount, equals(5));

      // Packet 2: DELTA_CHUNK (1 keyframe + 2 deltas = 3 frames)
      // payload = 1 + 14 + 2 * 7 = 29 bytes
      final pDelta = ByteData(4 + 29);
      pDelta.setUint8(0, BleConstants.packetTypeDeltaChunk);
      pDelta.setUint16(1, 1, Endian.big);
      pDelta.setUint8(3, 29);
      pDelta.setUint8(4, 3); // 3 frames
      // Keyframe (f5)
      pDelta.setUint16(5, 100, Endian.big);
      pDelta.setInt16(7, 10, Endian.big);
      pDelta.setInt16(9, 20, Endian.big);
      pDelta.setInt16(11, 980, Endian.big);
      pDelta.setInt16(13, 0, Endian.big);
      pDelta.setInt16(15, 0, Endian.big);
      pDelta.setInt16(17, 0, Endian.big);
      // Delta 1 (f6 - f5)
      pDelta.setUint8(19, 20); // diff_ms
      pDelta.setInt8(20, 5);   // diff_ax
      pDelta.setInt8(21, -2);  // diff_ay
      pDelta.setInt8(22, 3);   // diff_az
      pDelta.setInt8(23, 2);   // diff_gx
      pDelta.setInt8(24, 0);   // diff_gy
      pDelta.setInt8(25, -1);  // diff_gz
      // Delta 2 (f7 - f6)
      pDelta.setUint8(26, 20); // diff_ms
      pDelta.setInt8(27, 3);   // diff_ax
      pDelta.setInt8(28, -2);  // diff_ay
      pDelta.setInt8(29, 2);   // diff_az
      pDelta.setInt8(30, 2);   // diff_gx
      pDelta.setInt8(31, 1);   // diff_gy
      pDelta.setInt8(32, 0);   // diff_gz
      expect(reassembler.processPacket(pDelta.buffer.asUint8List()), isNull);
      expect(reassembler.samplesCount, equals(8));

      // Packet 3: DATA_CHUNK (2 raw frames = 28 bytes)
      final pData = ByteData(4 + 28);
      pData.setUint8(0, BleConstants.packetTypeDataChunk);
      pData.setUint16(1, 2, Endian.big);
      pData.setUint8(3, 28);
      for (int i = 0; i < 14; i++) {
        pData.setUint8(4 + i, f8.getUint8(i));
        pData.setUint8(18 + i, f9.getUint8(i));
      }
      expect(reassembler.processPacket(pData.buffer.asUint8List()), isNull);
      expect(reassembler.samplesCount, equals(10));

      // Packet 4: END_OF_BURST
      final pEnd = ByteData(12);
      pEnd.setUint8(0, BleConstants.packetTypeEndOfBurst);
      pEnd.setUint16(1, 3, Endian.big);
      pEnd.setUint32(4, totalFrames, Endian.big);
      pEnd.setUint32(8, expectedCrc, Endian.big);

      final result = reassembler.processPacket(pEnd.buffer.asUint8List());
      expect(result, isNotNull);
      expect(result!.isSuccess, isTrue);
      expect(result.framesRecovered, equals(10));
      expect(result.isCrcValid, isTrue);
      expect(result.readings.length, equals(10));
    });
  });
}
