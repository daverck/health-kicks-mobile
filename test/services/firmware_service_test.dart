import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/models/firmware_release_model.dart';
import 'package:healthkicks_mobile/services/firmware/firmware_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FirmwareService Unit Tests', () {
    test('isCloudReleaseNewer compares publication date with installed date correctly', () {
      final service = FirmwareService();

      final installedDate = DateTime.utc(2026, 10, 11, 8, 0, 0);
      final newerCloudDate = DateTime.utc(2026, 10, 11, 10, 0, 0);
      final olderCloudDate = DateTime.utc(2026, 10, 11, 7, 0, 0);
      final identicalCloudDate = DateTime.utc(2026, 10, 11, 8, 0, 0);

      // Newer cloud release -> true
      expect(
        service.isCloudReleaseNewer(
          cloudReleaseDate: newerCloudDate,
          installedDate: installedDate,
        ),
        isTrue,
      );

      // Older cloud release -> false
      expect(
        service.isCloudReleaseNewer(
          cloudReleaseDate: olderCloudDate,
          installedDate: installedDate,
        ),
        isFalse,
      );

      // Identical date -> false
      expect(
        service.isCloudReleaseNewer(
          cloudReleaseDate: identicalCloudDate,
          installedDate: installedDate,
        ),
        isFalse,
      );

      // No installed date -> true (update allowed)
      expect(
        service.isCloudReleaseNewer(
          cloudReleaseDate: newerCloudDate,
          installedDate: null,
        ),
        isTrue,
      );
    });

    test('parseBuildTimestamp parses C macro format and ISO format', () {
      // Standard C __DATE__ " " __TIME__: "Oct 11 2026 10:40:00"
      final parsedC = FirmwareService.parseBuildTimestamp('Oct 11 2026 10:40:00');
      expect(parsedC, isNotNull);
      expect(parsedC!.year, equals(2026));
      expect(parsedC.month, equals(10));
      expect(parsedC.day, equals(11));
      expect(parsedC.toLocal().hour, equals(10));
      expect(parsedC.toLocal().minute, equals(40));

      // ISO 8601
      final parsedIso = FirmwareService.parseBuildTimestamp('2026-10-11T10:40:00Z');
      expect(parsedIso, isNotNull);
      expect(parsedIso!.year, equals(2026));
      expect(parsedIso.month, equals(10));
      expect(parsedIso.day, equals(11));

      // Invalid string -> null
      expect(FirmwareService.parseBuildTimestamp('invalid_date'), isNull);
      expect(FirmwareService.parseBuildTimestamp(null), isNull);
    });

    test('FirmwareReleaseModel.parseUtcDateTime correctly enforces UTC timezone interpretation', () {
      // String with trailing Z
      final utc1 = FirmwareReleaseModel.parseUtcDateTime('2026-10-11T08:24:36Z');
      expect(utc1.isUtc, isTrue);
      expect(utc1.hour, equals(8));

      // Naive string without Z (must be parsed as UTC, not local)
      final utc2 = FirmwareReleaseModel.parseUtcDateTime('2026-10-11T08:24:36');
      expect(utc2.isUtc, isTrue);
      expect(utc2.hour, equals(8));

      // String with space
      final utc3 = FirmwareReleaseModel.parseUtcDateTime('2026-10-11 08:24:36');
      expect(utc3.isUtc, isTrue);
      expect(utc3.hour, equals(8));
    });

    test('computeSha256 and verifySha256 validates cryptographic digest', () {
      final service = FirmwareService();
      final dummyBytes = Uint8List.fromList(utf8.encode('HealthKicks Firmware Binary Content'));

      final computedHash = service.computeSha256(dummyBytes);
      expect(computedHash.length, equals(64));

      // Valid expected hash
      expect(
        service.verifySha256(
          binaryBytes: dummyBytes,
          expectedSha256: computedHash,
        ),
        isTrue,
      );

      // Case-insensitive verification
      expect(
        service.verifySha256(
          binaryBytes: dummyBytes,
          expectedSha256: computedHash.toUpperCase(),
        ),
        isTrue,
      );

      // Mismatched expected hash
      expect(
        service.verifySha256(
          binaryBytes: dummyBytes,
          expectedSha256: '0000000000000000000000000000000000000000000000000000000000000000',
        ),
        isFalse,
      );

      // Empty expected hash allows pass-through
      expect(
        service.verifySha256(
          binaryBytes: dummyBytes,
          expectedSha256: '',
        ),
        isTrue,
      );
    });

    test('Local installation metadata persistence in SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = FirmwareService(prefs: prefs);

      expect(await service.getLocalInstalledDate(), isNull);
      expect(await service.getLocalInstalledVersion(), isNull);

      final saveDate = DateTime.utc(2026, 10, 11, 10, 24, 0);
      await service.saveLocalInstalledFirmware(
        installedDate: saveDate,
        version: 'v1.2.1-esp32s3',
      );

      expect(await service.getLocalInstalledDate(), equals(saveDate));
      expect(await service.getLocalInstalledVersion(), equals('v1.2.1-esp32s3'));
    });

    test('fetchLatestRelease parses REST API response successfully', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/api/v1/firmware/latest')) {
          return http.Response(
            jsonEncode({
              'version': 'v1.2.1-esp32s3',
              'download_url': 'https://s3.example.com/firmware.bin',
              'sha256': 'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
              'size_bytes': 930525,
              'expires_in_seconds': 900,
              'release_date': '2026-10-11T10:24:36Z',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = FirmwareService(httpClient: mockClient);
      final release = await service.fetchLatestRelease(
        backendUrl: 'https://api.example.com',
        token: 'mock_jwt_token',
      );

      expect(release.version, equals('v1.2.1-esp32s3'));
      expect(release.downloadUrl, equals('https://s3.example.com/firmware.bin'));
      expect(release.sha256, startsWith('abcdef'));
      expect(release.sizeBytes, equals(930525));
      expect(release.releaseDate.year, equals(2026));
    });
  });
}

