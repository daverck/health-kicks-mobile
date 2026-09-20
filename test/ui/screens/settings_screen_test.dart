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
  });
}
