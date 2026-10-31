import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:healthkicks_mobile/services/fall_sensitivity_settings_service.dart';
import 'package:healthkicks_mobile/ui/widgets/settings/settings_fall_sensitivity_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SettingsFallSensitivityCard - Widget Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('Renders card with default 1.38 g threshold, badges and slider', (tester) async {
      final service = FallSensitivitySettingsService();
      await service.loadSettings();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SettingsFallSensitivityCard(
                fallSensitivityService: service,
                isBleReady: false,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Sensibilité détection de chute'), findsOneWidget);
      expect(find.text('Équilibrée (Recommandée)'), findsOneWidget);
      expect(find.text('1.38 g (13.5 m/s²)'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('0.80 g (Ultra sensible)'), findsOneWidget);
      expect(find.text('1.90 g (Robuste)'), findsOneWidget);
      expect(find.text('Enregistré localement. Sera transmis à la connexion de la chaussure.'), findsOneWidget);
    });

    testWidgets('Shows connected status note when isBleReady is true', (tester) async {
      final service = FallSensitivitySettingsService();
      await service.loadSettings();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SettingsFallSensitivityCard(
                fallSensitivityService: service,
                isBleReady: true,
              ),
            ),
          ),
        ),
      );

      expect(find.text('Synchronisé en direct avec la chaussure via BLE.'), findsOneWidget);
    });

    testWidgets('Interacting with slider updates threshold and label', (tester) async {
      final service = FallSensitivitySettingsService();
      await service.loadSettings();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SettingsFallSensitivityCard(
                fallSensitivityService: service,
                isBleReady: false,
              ),
            ),
          ),
        ),
      );

      // Programmatically update threshold to test reactive rebuild
      await service.updateThreshold(0.80);
      await tester.pumpAndSettle();

      expect(find.text('0.80 g (7.8 m/s²)'), findsOneWidget);
      expect(find.text('Ultra sensible (Démo)'), findsOneWidget);

      await service.updateThreshold(1.90);
      await tester.pumpAndSettle();

      expect(find.text('1.90 g (18.6 m/s²)'), findsOneWidget);
      expect(find.text('Robuste'), findsOneWidget);
    });
  });
}
