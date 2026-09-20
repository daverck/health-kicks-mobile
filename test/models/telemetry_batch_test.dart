import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/models/imu_reading_model.dart';
import 'package:healthkicks_mobile/models/studio_session_model.dart';
import 'package:healthkicks_mobile/models/telemetry/telemetry_batch_model.dart';

void main() {
  group('TelemetryBatch & Edge Pydantic Contract', () {
    final uuidRegex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );

    test('Header generates compliant default values (schema_version 1.0, UUIDv4, ISO UTC)', () {
      final header = TelemetryHeader(deviceId: 'HK-DEV-001');
      final json = header.toJson();

      expect(json['device_id'], equals('HK-DEV-001'));
      expect(json['schema_version'], equals('1.0'));
      expect(uuidRegex.hasMatch(json['msg_id'] as String), isTrue);
      expect(DateTime.parse(json['timestamp'] as String).isUtc, isTrue);
    });

    test('Serializes a complete TelemetryBatch with strictly compliant tree', () {
      const session = StudioSessionModel(
        sessionId: 'session-test-uuid',
        label: 'sprint_400m',
        deviceId: 'HK-SHOE-042',
        startTimestampEpoch: 1718000000.0,
        readings: [
          ImuReadingModel(
            deltaMs: 0,
            ax: 0.12,
            ay: 0.98,
            az: -0.05,
            gx: 12.0,
            gy: -3.5,
            gz: 0.5,
          ),
          ImuReadingModel(
            deltaMs: 20,
            ax: 0.15,
            ay: 0.95,
            az: -0.04,
            gx: 14.2,
            gy: -2.8,
            gz: 0.8,
          ),
        ],
      );

      final batches = session.toTelemetryBatches();
      expect(batches.length, equals(1));

      final batch = batches.first;
      final json = batch.toJson();

      // 1. Header validation
      expect(json.containsKey('header'), isTrue);
      final header = json['header'] as Map<String, dynamic>;
      expect(header['device_id'], equals('HK-SHOE-042'));
      expect(header['schema_version'], equals('1.0'));
      expect(uuidRegex.hasMatch(header['msg_id'] as String), isTrue);
      expect(DateTime.parse(header['timestamp'] as String).isUtc, isTrue);

      // 2. Metadata validation
      expect(json.containsKey('metadata'), isTrue);
      final metadata = json['metadata'] as Map<String, dynamic>;
      expect(metadata['sample_count'], equals(2));
      expect(metadata['flush_trigger'], equals('studio'));
      expect(metadata['session_id'], equals('session-test-uuid'));
      expect(metadata['label'], equals('sprint_400m'));
      expect(DateTime.parse(metadata['window_start'] as String).isUtc, isTrue);
      expect(DateTime.parse(metadata['window_end'] as String).isUtc, isTrue);

      // 3. Readings validation
      expect(json.containsKey('readings'), isTrue);
      final readings = json['readings'] as List<dynamic>;
      expect(readings.length, equals(2));

      final firstReading = readings.first as Map<String, dynamic>;
      expect(firstReading.containsKey('header'), isTrue);
      expect(firstReading.containsKey('payload'), isTrue);

      final rHeader = firstReading['header'] as Map<String, dynamic>;
      expect(rHeader['device_id'], equals('HK-SHOE-042'));
      expect(rHeader['schema_version'], equals('1.0'));
      expect(uuidRegex.hasMatch(rHeader['msg_id'] as String), isTrue);
      expect(DateTime.parse(rHeader['timestamp'] as String).isUtc, isTrue);

      final rPayload = firstReading['payload'] as Map<String, dynamic>;
      expect(rPayload['ax'], closeTo(0.12, 0.001));
      expect(rPayload['ay'], closeTo(0.98, 0.001));
      expect(rPayload['az'], closeTo(-0.05, 0.001));
      expect(rPayload['gx'], closeTo(12.0, 0.001));
      expect(rPayload['gy'], closeTo(-3.5, 0.001));
      expect(rPayload['gz'], closeTo(0.5, 0.001));
    });

    test('toMqttBatchPayloads returns valid JSON-serializable payloads', () {
      const session = StudioSessionModel(
        sessionId: 'sess-json-test',
        label: 'marche',
        deviceId: 'HK-SHOE-001',
        startTimestampEpoch: 1718000000.0,
        readings: [
          ImuReadingModel(
            deltaMs: 0,
            ax: 0.0,
            ay: 1.0,
            az: 0.0,
            gx: 0.0,
            gy: 0.0,
            gz: 0.0,
          ),
        ],
      );

      final payloads = session.toMqttBatchPayloads();
      expect(payloads.length, equals(1));

      final rawString = jsonEncode(payloads.first);
      final decoded = jsonDecode(rawString) as Map<String, dynamic>;

      expect(decoded['header']['device_id'], equals('HK-SHOE-001'));
      expect(decoded['metadata']['sample_count'], equals(1));
      expect((decoded['readings'] as List).length, equals(1));
    });

    test('Batch chunking respects maximum chunk size', () {
      final dummyReadings = List.generate(
        1250,
        (i) => ImuReadingModel(
          deltaMs: i * 20,
          ax: 0.01 * (i % 100),
          ay: 0.98,
          az: 0.05,
          gx: 1.0,
          gy: 2.0,
          gz: 3.0,
        ),
      );

      final session = StudioSessionModel(
        sessionId: 'chunk-session',
        label: 'endurance',
        deviceId: 'HK-CHUNK-01',
        startTimestampEpoch: 1718000000.0,
        readings: dummyReadings,
      );

      final batches = session.toTelemetryBatches(maxReadingsPerChunk: 500);

      expect(batches.length, equals(3));
      expect(batches[0].metadata.sampleCount, equals(500));
      expect(batches[0].readings.length, equals(500));
      expect(batches[1].metadata.sampleCount, equals(500));
      expect(batches[1].readings.length, equals(500));
      expect(batches[2].metadata.sampleCount, equals(250));
      expect(batches[2].readings.length, equals(250));

      // Verify that each batch has consistent time windows
      final start0 = DateTime.parse(batches[0].metadata.windowStart);
      final end0 = DateTime.parse(batches[0].metadata.windowEnd);
      expect(start0.isBefore(end0), isTrue);

      final start1 = DateTime.parse(batches[1].metadata.windowStart);
      expect(end0.isBefore(start1) || end0.isAtSameMomentAs(start1), isTrue);
    });

    test('TelemetryBatch.fromJson accurately reconstructs an object', () {
      final original = TelemetryBatch(
        header: TelemetryHeader(deviceId: 'HK-999', schemaVersion: '1.0'),
        metadata: const BatchMetadata(
          sampleCount: 1,
          windowStart: '2026-09-15T08:00:00.000Z',
          windowEnd: '2026-09-15T08:00:00.020Z',
          flushTrigger: 'studio',
          sessionId: 's-999',
          label: 'reconstruction',
        ),
        readings: [
          TelemetryItem(
            header: TelemetryHeader(
              deviceId: 'HK-999',
              timestamp: '2026-09-15T08:00:00.000Z',
            ),
            payload: const ImuPayload(ax: 1, ay: 2, az: 3, gx: 4, gy: 5, gz: 6),
          ),
        ],
      );

      final json = original.toJson();
      final parsed = TelemetryBatch.fromJson(json);

      expect(parsed.header.deviceId, equals('HK-999'));
      expect(parsed.metadata.sessionId, equals('s-999'));
      expect(parsed.metadata.sampleCount, equals(1));
      expect(parsed.readings.first.payload.ax, equals(1.0));
      expect(parsed.readings.first.payload.gz, equals(6.0));
    });

    test('StudioSessionModel.create automatically generates canonical UUIDv4 and toRestApiPayload is compliant', () {
      final session = StudioSessionModel.create(
        label: 'course_vitesse',
        deviceId: 'HK-SHOE-777',
        durationSec: 8.5,
        readings: [
          const ImuReadingModel(
            deltaMs: 0,
            ax: 0.1,
            ay: 0.9,
            az: 0.0,
            gx: 0.0,
            gy: 0.0,
            gz: 0.0,
          ),
          const ImuReadingModel(
            deltaMs: 20,
            ax: 0.2,
            ay: 0.8,
            az: 0.1,
            gx: 1.0,
            gy: 0.0,
            gz: 0.0,
          ),
        ],
      );

      expect(uuidRegex.hasMatch(session.sessionId), isTrue);
      expect(session.durationSec, equals(8.5));

      final restPayload = session.toRestApiPayload();
      expect(restPayload['id'], equals(session.sessionId));
      expect(uuidRegex.hasMatch(restPayload['id'] as String), isTrue);
      expect(restPayload['device_id'], equals('HK-SHOE-777'));
      expect(restPayload['label'], equals('course_vitesse'));
      expect(restPayload['duration_sec'], equals(8.5));
      expect(restPayload['sample_count'], equals(2));
    });
  });
}
