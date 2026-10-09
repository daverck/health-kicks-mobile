import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/ui/screens/firmware_update_screen.dart';

void main() {
  group('FirmwareUpdateScreen Widget Tests', () {
    testWidgets('Renders current firmware version and selection controls', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FirmwareUpdateScreen(
            currentFirmwareVersion: 'v1.2.0-esp32s3',
          ),
        ),
      );

      // Verify app bar title
      expect(find.text('Mise à jour Firmware OTA'), findsOneWidget);

      // Verify current firmware version display
      expect(find.text('Version installée : v1.2.0-esp32s3'), findsOneWidget);

      // Verify section titles
      expect(find.text('Fichier Binaire Firmware (.bin)'), findsOneWidget);
      expect(find.text('Aucun fichier sélectionné'), findsOneWidget);

      // Verify Cloud S3 URL section and default URL text field
      expect(find.text('Télécharger depuis le Cloud (AWS S3) ou une URL'), findsOneWidget);
      expect(find.text('Télécharger'), findsOneWidget);
      expect(find.text(FirmwareUpdateScreen.defaultFirmwareUrl), findsOneWidget);

      // Verify Local file section
      expect(find.text('Ou charger un fichier local (.bin)'), findsOneWidget);
      expect(find.text('Charger'), findsOneWidget);

      // Verify trigger button is initially disabled (no device and no file)
      final flashButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Lancer la Mise à Jour OTA'),
      );
      expect(flashButton.onPressed, isNull);
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
