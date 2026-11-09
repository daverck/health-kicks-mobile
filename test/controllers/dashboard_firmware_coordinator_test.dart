import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/controllers/dashboard_firmware_coordinator.dart';
import 'package:healthkicks_mobile/models/firmware_release_model.dart';
import 'package:healthkicks_mobile/services/firmware/firmware_service.dart';

class FakeFirmwareService extends FirmwareService {
  final FirmwareReleaseModel release;
  final String? installedVersion;
  final DateTime? installedDate;
  int fetchLatestReleaseCallCount = 0;

  FakeFirmwareService({
    required this.release,
    this.installedVersion,
    this.installedDate,
  });

  @override
  Future<String?> getLocalInstalledVersion() async => installedVersion;

  @override
  Future<DateTime?> getLocalInstalledDate() async => installedDate;

  @override
  Future<FirmwareReleaseModel> fetchLatestRelease({
    String? backendUrl,
    String? token,
    String? fallbackS3Url,
  }) async {
    fetchLatestReleaseCallCount++;
    return release;
  }
}

void main() {
  group('DashboardFirmwareCoordinator tests', () {
    final release = FirmwareReleaseModel(
      version: 'v1.2.1-esp32s3',
      downloadUrl: 'https://example.com/firmware.bin',
      sha256: '',
      sizeBytes: 100,
      expiresInSeconds: 900,
      releaseDate: DateTime.utc(2026, 10, 22),
    );

    test('notifies when newer firmware release is found', () async {
      final fakeService = FakeFirmwareService(
        release: release,
        installedVersion: 'v1.2.0-esp32s3',
        installedDate: DateTime.utc(2026, 10, 21),
      );
      String? snackBarMessage;
      final logs = <String>[];

      final coordinator = DashboardFirmwareCoordinator(
        firmwareService: fakeService,
      );

      await coordinator.checkForFirmwareUpdate(
        addLog: (tag, msg, {color}) => logs.add('[$tag] $msg'),
        onShowSnackBar: (msg, {backgroundColor}) => snackBarMessage = msg,
      );

      expect(fakeService.fetchLatestReleaseCallCount, 1);
      expect(coordinator.latestFirmwareRelease, release);
      expect(coordinator.installedFirmwareVersion, 'v1.2.0-esp32s3');
      expect(snackBarMessage, contains('Nouveau firmware disponible'));
      expect(snackBarMessage, contains(release.version));
      expect(logs.any((l) => l.contains('Vérification automatique terminée')), isTrue);
    });

    test('does not notify when installed firmware is already current', () async {
      final fakeService = FakeFirmwareService(
        release: release,
        installedVersion: release.version,
        installedDate: release.releaseDate,
      );
      String? snackBarMessage;
      final logs = <String>[];

      final coordinator = DashboardFirmwareCoordinator(
        firmwareService: fakeService,
      );

      await coordinator.checkForFirmwareUpdate(
        addLog: (tag, msg, {color}) => logs.add('[$tag] $msg'),
        onShowSnackBar: (msg, {backgroundColor}) => snackBarMessage = msg,
      );

      expect(snackBarMessage, isNull);
      expect(coordinator.announcedFirmwareReleaseVersion, isNull);
    });
  });
}
