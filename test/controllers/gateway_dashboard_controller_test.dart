import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/controllers/gateway_dashboard_controller.dart';
import 'package:healthkicks_mobile/models/activity_detection_model.dart';
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

  group('GatewayDashboardController inactivity alert handling', () {
    test('inactivity_alert triggers SnackBar even when HITL is active', () {
      String? snackBarMessage;
      final controller = GatewayDashboardController(
        onShowSnackBar: (msg, {backgroundColor}) => snackBarMessage = msg,
      );

      // Enable HITL mode
      controller.hitlCoordinator.setHitlActive(true);
      expect(controller.hitlCoordinator.isHitlActive, isTrue);

      const inactDetection = ActivityDetectionModel(
        stateCode: 0x20,
        eventType: 'inactivity_alert',
        confidencePercent: 100,
        timestampEpochSec: 1729000000,
        isFall: false,
        isHapticTriggered: true,
      );

      controller.handleActivityDetection(inactDetection);

      expect(snackBarMessage, isNotNull);
      expect(controller.hitlCoordinator.items, isEmpty);
      controller.dispose();
    });

    test('inactivity_alert triggers SnackBar even after active movement', () {
      String? snackBarMessage;
      final controller = GatewayDashboardController(
        onShowSnackBar: (msg, {backgroundColor}) => snackBarMessage = msg,
      );

      // Simulate a recent walk detection
      const walkDetection = ActivityDetectionModel(
        stateCode: 0x01,
        eventType: 'walk',
        confidencePercent: 95,
        timestampEpochSec: 1729000010,
        isFall: false,
        isHapticTriggered: false,
      );
      controller.handleActivityDetection(walkDetection);

      // Now receive an inactivity alert
      const inactDetection = ActivityDetectionModel(
        stateCode: 0x20,
        eventType: 'inactivity_alert',
        confidencePercent: 100,
        timestampEpochSec: 1729000015,
        isFall: false,
        isHapticTriggered: true,
      );
      controller.handleActivityDetection(inactDetection);

      expect(snackBarMessage, isNotNull);
      controller.dispose();
    });

    test('active movement automatically invokes onDismissSnackBar', () {
      var dismissedCount = 0;
      final controller = GatewayDashboardController(
        onDismissSnackBar: () => dismissedCount++,
      );

      const walkDetection = ActivityDetectionModel(
        stateCode: 0x01,
        eventType: 'walk',
        confidencePercent: 90,
        timestampEpochSec: 1729000000,
        isFall: false,
        isHapticTriggered: false,
      );

      controller.handleActivityDetection(walkDetection);
      expect(dismissedCount, 1);
      controller.dispose();
    });

    test('inactivity_alert triggers SnackBar even when marked as offline buffered', () {
      String? snackBarMessage;
      final controller = GatewayDashboardController(
        onShowSnackBar: (msg, {backgroundColor}) => snackBarMessage = msg,
      );

      const bufferedInact = ActivityDetectionModel(
        stateCode: 0x20,
        eventType: 'inactivity_alert',
        confidencePercent: 100,
        timestampEpochSec: 1729000000,
        isFall: false,
        isHapticTriggered: true,
        isOfflineBuffered: true,
      );

      controller.handleActivityDetection(bufferedInact);
      expect(snackBarMessage, isNotNull);
      controller.dispose();
    });
  
    test('enabling HITL mode clears recentActivities history', () async {
      final controller = GatewayDashboardController();

      const walkDetection = ActivityDetectionModel(
        stateCode: 0x01,
        eventType: 'walk',
        confidencePercent: 90,
        timestampEpochSec: 1729000000,
        isFall: false,
        isHapticTriggered: false,
      );
      controller.handleActivityDetection(walkDetection);
      expect(controller.recentActivities.length, equals(1));

      await controller.setHitlActive(true);
      expect(controller.recentActivities, isEmpty);
      expect(controller.hitlCoordinator.isHitlActive, isTrue);

      controller.dispose();
    });
});
}
