import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:healthkicks_mobile/services/fall_sensitivity_settings_service.dart';
import 'package:healthkicks_mobile/ui/widgets/settings/settings_fall_sensitivity_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildTestWidget(FallSensitivitySettingsService service, {bool isBleReady = true}) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SettingsFallSensitivityCard(
            fallSensitivityService: service,
            bleClient: null,
            isBleReady: isBleReady,
          ),
        ),
      ),
    );
  }

  testWidgets('SettingsFallSensitivityCard renders all main elements including cooldown slider', (tester) async {
    final service = FallSensitivitySettingsService();
    await service.loadSettings();

    await tester.pumpWidget(buildTestWidget(service));

    // Check for main title and cooldown section title
    expect(find.text('Sensibilité de détection des chutes'), findsOneWidget);
    expect(find.text('Délai entre deux alertes (Cooldown)'), findsOneWidget);

    // Check for icon
    expect(find.byIcon(Icons.shield_outlined), findsOneWidget);

    // Check for both sliders (confidence threshold + fall cooldown)
    expect(find.byType(Slider), findsNWidgets(2));

    // Check for sync status
    expect(find.textContaining('Synchronisé'), findsOneWidget);
  });

  testWidgets('SettingsFallSensitivityCard displays threshold percentage', (tester) async {
    final service = FallSensitivitySettingsService();
    await service.loadSettings();

    await tester.pumpWidget(buildTestWidget(service));

    // Default threshold is 0.65, which should be 65%
    expect(find.text('65%'), findsWidgets);
  });

  testWidgets('SettingsFallSensitivityCard displays sensitivity label', (tester) async {
    final service = FallSensitivitySettingsService();
    await service.loadSettings();

    await tester.pumpWidget(buildTestWidget(service));

    // Default threshold 0.65 should show "Équilibrée"
    expect(find.text('Équilibrée'), findsWidgets);
  });

  testWidgets('SettingsFallSensitivityCard displays range labels', (tester) async {
    final service = FallSensitivitySettingsService();
    await service.loadSettings();

    await tester.pumpWidget(buildTestWidget(service));

    // Check for range labels
    expect(find.text('35%'), findsOneWidget);
    expect(find.text('85%'), findsOneWidget);
    expect(find.text('Ultra sensible'), findsOneWidget);
    expect(find.text('Recommandée'), findsOneWidget);
    expect(find.text('Robuste'), findsOneWidget);
    expect(find.text('0.5 s'), findsOneWidget);
    expect(find.text('3 s (défaut)'), findsOneWidget);
    expect(find.text('30 s'), findsOneWidget);
  });

  testWidgets('SettingsFallSensitivityCard shows disconnected BLE status', (tester) async {
    final service = FallSensitivitySettingsService();
    await service.loadSettings();

    await tester.pumpWidget(
      buildTestWidget(service, isBleReady: false),
    );

    expect(find.textContaining('Sera synchronisé dès la prochaine connexion BLE'), findsOneWidget);
    expect(find.byIcon(Icons.bluetooth_disabled), findsOneWidget);
  });

  testWidgets('SettingsFallSensitivityCard shows connected BLE status', (tester) async {
    final service = FallSensitivitySettingsService();
    await service.loadSettings();

    await tester.pumpWidget(
      buildTestWidget(service, isBleReady: true),
    );

    expect(find.textContaining('Synchronisé en direct avec la chaussure'), findsOneWidget);
    expect(find.byIcon(Icons.bluetooth_connected), findsOneWidget);
  });

  testWidgets('SettingsFallSensitivityCard updates UI when slider values change', (tester) async {
    final service = FallSensitivitySettingsService();
    await service.loadSettings();

    await tester.pumpWidget(buildTestWidget(service));

    expect(find.text('65%'), findsWidgets);
    expect(find.text('Équilibrée'), findsWidgets);
    expect(find.text('3 s'), findsWidgets);

    // Update threshold and cooldown via service
    await service.setThreshold(0.85);
    await service.setCooldownSeconds(0.5);
    await tester.pumpAndSettle();

    expect(find.text('85%'), findsWidgets);
    expect(find.text('Robuste'), findsWidgets);
    expect(find.text('0.5 s'), findsWidgets);
  });
}
