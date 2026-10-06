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

      // Verify test binary buttons
      expect(find.text('Binaire Test 64 Ko'), findsOneWidget);
      expect(find.text('Binaire Test 256 Ko'), findsOneWidget);

      // Verify trigger button is initially disabled (no device and no file)
      final flashButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Lancer la Mise à Jour OTA'),
      );
      expect(flashButton.onPressed, isNull);
    });

    testWidgets('Tapping demo test binary loads binary and displays file card', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: FirmwareUpdateScreen(
            currentFirmwareVersion: 'v1.2.0-esp32s3',
          ),
        ),
      );

      // Tap on 64 Ko test binary button
      await tester.tap(find.text('Binaire Test 64 Ko'));
      await tester.pumpAndSettle();

      // Verify selected binary card is rendered
      expect(find.text('demo_firmware_64kb.bin'), findsOneWidget);
      expect(find.textContaining('64.0 Ko'), findsOneWidget);
      expect(find.textContaining('v1.2.1-test'), findsOneWidget);
    });
  });
}
