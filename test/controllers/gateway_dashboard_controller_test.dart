import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/controllers/gateway_dashboard_controller.dart';
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
  group('GatewayDashboardController firmware check', () {
    final release = FirmwareReleaseModel(
      version: 'v1.2.1-esp32s3',
      downloadUrl: 'https://example.com/firmware.bin',
      sha256: '',
      sizeBytes: 100,
      expiresInSeconds: 900,
      releaseDate: DateTime.utc(2026, 10, 22),
    );

    test('notifies when a newer cloud firmware is found', () async {
      final firmwareService = FakeFirmwareService(
        release: release,
        installedVersion: 'v1.2.0-esp32s3',
        installedDate: DateTime.utc(2026, 10, 21),
      );
      String? notification;
      final controller = GatewayDashboardController(
        firmwareService: firmwareService,
        onShowSnackBar: (message, {backgroundColor}) => notification = message,
      );

      await controller.checkForFirmwareUpdate();

      expect(firmwareService.fetchLatestReleaseCallCount, 1);
      expect(notification, contains('Nouveau firmware disponible'));
      expect(notification, contains(release.version));
      expect(
          controller.logs.any(
              (log) => log.message.contains('Nouveau firmware disponible')),
          isTrue);
      controller.dispose();
    });

    test('does not notify when the installed version is current', () async {
      final firmwareService = FakeFirmwareService(
        release: release,
        installedVersion: release.version,
        installedDate: release.releaseDate,
      );
      var notificationShown = false;
      final controller = GatewayDashboardController(
        firmwareService: firmwareService,
        onShowSnackBar: (message, {backgroundColor}) =>
            notificationShown = true,
      );

      await controller.checkForFirmwareUpdate();

      expect(notificationShown, isFalse);
      controller.dispose();
    });
  });
}
