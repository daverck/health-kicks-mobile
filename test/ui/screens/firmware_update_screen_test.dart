import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/models/firmware_release_model.dart';
import 'package:healthkicks_mobile/services/firmware/firmware_service.dart';
import 'package:healthkicks_mobile/ui/screens/firmware_update_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockFirmwareService extends FirmwareService {
  final FirmwareReleaseModel? stubRelease;
  final bool stubIsNewer;
  final DateTime? stubInstalledDate;

  MockFirmwareService({
    this.stubRelease,
    this.stubIsNewer = true,
    this.stubInstalledDate,
  });

  @override
  Future<DateTime?> getLocalInstalledDate() async {
    return stubInstalledDate ?? DateTime.utc(2026, 10, 11, 8, 0, 0);
  }

  @override
  Future<String?> getLocalInstalledVersion() async {
    return 'v1.2.0-esp32s3';
  }

  @override
  Future<FirmwareReleaseModel> fetchLatestRelease({
    String? backendUrl,
    String? token,
    String? fallbackS3Url,
  }) async {
    if (stubRelease != null) return stubRelease!;
    return FirmwareReleaseModel(
      version: 'v1.2.1-esp32s3',
      downloadUrl: FirmwareUpdateScreen.defaultFirmwareUrl,
      sha256: 'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
      sizeBytes: 930525,
      expiresInSeconds: 900,
      releaseDate: DateTime.utc(2026, 10, 11, 10, 30, 0),
    );
  }

  @override
  bool isCloudReleaseNewer({
    required DateTime cloudReleaseDate,
    DateTime? installedDate,
  }) {
    return stubIsNewer;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FirmwareUpdateScreen Widget Tests', () {
    testWidgets('Renders current firmware version, date info, and selection controls', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final mockFirmwareService = MockFirmwareService(stubIsNewer: true);

      await tester.pumpWidget(
        MaterialApp(
          home: FirmwareUpdateScreen(
            currentFirmwareVersion: 'v1.2.0-esp32s3',
            firmwareService: mockFirmwareService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify app bar title
      expect(find.text('Mise à jour Firmware OTA'), findsOneWidget);

      // Verify current firmware version display
      expect(find.text('Version installée : v1.2.0-esp32s3'), findsOneWidget);
      expect(find.textContaining('Date firmware actif :'), findsOneWidget);

      // Verify Cloud release section
      expect(find.text('Dernière Release Cloud'), findsOneWidget);
      expect(find.textContaining('Nouvelle version disponible'), findsOneWidget);

      // Verify section titles
      expect(find.text('Fichier Binaire Firmware (.bin)'), findsOneWidget);
      expect(find.text('Aucun fichier sélectionné'), findsOneWidget);

      // Verify Cloud S3 URL section and default URL text field
      expect(find.text('Télécharger depuis le Cloud (AWS S3) ou une URL'), findsOneWidget);
      expect(find.text('Télécharger'), findsOneWidget);
      expect(find.text(FirmwareUpdateScreen.defaultFirmwareUrl), findsOneWidget);

      // Verify trigger button is initially disabled (no device and no file)
      final flashButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Lancer la Mise à Jour OTA'),
      );
      expect(flashButton.onPressed, isNull);
    });

    testWidgets('Displays up to date badge when cloud release is not newer', (WidgetTester tester) async {
      final mockFirmwareService = MockFirmwareService(stubIsNewer: false);

      await tester.pumpWidget(
        MaterialApp(
          home: FirmwareUpdateScreen(
            currentFirmwareVersion: 'v1.2.1-esp32s3',
            firmwareService: mockFirmwareService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify up-to-date badge
      expect(find.textContaining('Votre firmware est à jour'), findsOneWidget);
    });

    testWidgets('URL field is pre-filled with official default AWS S3 firmware URL', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FirmwareUpdateScreen(
            currentFirmwareVersion: 'v1.2.0-esp32s3',
          ),
        ),
      );

      final textField = tester.widget<TextField>(
        find.widgetWithText(TextField, FirmwareUpdateScreen.defaultFirmwareUrl),
      );
      expect(textField.controller?.text, equals(FirmwareUpdateScreen.defaultFirmwareUrl));
      expect(textField.controller?.text, contains('healthkicks-firmware-releases'));
      expect(textField.controller?.text, endsWith('firmware.bin'));
    });
  });
}
