import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:healthkicks_mobile/services/background_surveillance_service.dart';
import 'package:healthkicks_mobile/ui/screens/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SettingsScreen - UI and Mode Surveillance Active', () {
    testWidgets('Displays Settings AppBar and Mode Surveillance Active tile', (tester) async {
      final service = BackgroundSurveillanceService();
      addTearDown(service.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(surveillanceService: service),
        ),
      );

      expect(find.text('Paramètres'), findsOneWidget);
      expect(
        find.widgetWithText(SwitchListTile, 'Mode Surveillance Active'),
        findsOneWidget,
      );
      expect(
        find.text('Maintient la connexion active écran éteint pour l\'enregistrement et la télémétrie'),
        findsOneWidget,
      );
      expect(find.byType(SwitchListTile), findsOneWidget);
    });

    testWidgets('Reflects active state when service state changes', (tester) async {
      final service = BackgroundSurveillanceService();
      addTearDown(service.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(surveillanceService: service),
        ),
      );

      final switchTileFinder = find.byType(SwitchListTile);
      expect(switchTileFinder, findsOneWidget);

      SwitchListTile switchTile = tester.widget(switchTileFinder);
      expect(switchTile.value, isFalse);

      // Start surveillance
      await service.startSurveillance();
      await tester.pumpAndSettle();

      switchTile = tester.widget(switchTileFinder);
      expect(switchTile.value, isTrue);

      await service.stopSurveillance();
    });

    testWidgets('Displays Sensor Calibration tile and opens modal dialog', (tester) async {
      final service = BackgroundSurveillanceService();
      addTearDown(service.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            surveillanceService: service,
            isFootwearConnected: false,
          ),
        ),
      );

      expect(find.text('CALIBRATION DU CAPTEUR (ASSIETTE)'), findsOneWidget);
      expect(find.text('Calibration de l\'assiette (Zéro gravité)'), findsOneWidget);

      // Tap on calibration tile
      await tester.tap(find.text('Calibration de l\'assiette (Zéro gravité)'));
      await tester.pumpAndSettle();

      expect(find.text('Calibration de l\'Assiette'), findsOneWidget);
      expect(find.textContaining('Chaussure non connectée'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Démarrer'), findsOneWidget);

      // Start button should be disabled when not connected
      final startBtn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Démarrer'));
      expect(startBtn.onPressed, isNull);

      // Dismiss dialog
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(find.text('Calibration de l\'Assiette'), findsNothing);
    });

    testWidgets('Executes calibration immediately on Start (Option A) and shows countdown', (tester) async {
      final service = BackgroundSurveillanceService();
      addTearDown(service.dispose);

      bool calibrateCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            surveillanceService: service,
            isFootwearConnected: true,
            onCalibrateSensor: () async {
              calibrateCalled = true;
            },
          ),
        ),
      );

      await tester.tap(find.text('Calibration de l\'assiette (Zéro gravité)'));
      await tester.pumpAndSettle();

      expect(find.text('Calibration de l\'Assiette'), findsOneWidget);
      expect(find.textContaining('Chaussure non connectée'), findsNothing);

      // Tap start
      await tester.tap(find.widgetWithText(FilledButton, 'Démarrer'));
      await tester.pump();

      // Verified Option A: onCalibrate called immediately upon tapping start
      expect(calibrateCalled, isTrue);
      expect(find.textContaining('Mesure de l\'assiette en cours'), findsOneWidget);

      // Advance timer through countdown (4 seconds)
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.textContaining('Calibration réussie !'), findsOneWidget);
      expect(find.text('Terminer'), findsOneWidget);

      await tester.tap(find.text('Terminer'));
      await tester.pumpAndSettle();
      expect(find.text('Calibration de l\'Assiette'), findsNothing);
    });
  });
}
