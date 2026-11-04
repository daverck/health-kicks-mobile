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
        body: SettingsFallSensitivityCard(
          fallSensitivityService: service,
          bleClient: null,
          isBleReady: isBleReady,
        ),
      ),
    );
  }

  testWidgets('SettingsFallSensitivityCard renders all main elements', (tester) async {
    final service = FallSensitivitySettingsService();
    await service.loadSettings();

    await tester.pumpWidget(buildTestWidget(service));

    // Check for main title
    expect(find.text('Sensibilité de détection des chutes'), findsOneWidget);
    
    // Check for icon
    expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
    
    // Check for slider
    expect(find.byType(Slider), findsOneWidget);
    
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

    // Check for range labels - they appear multiple times in the widget
    expect(find.text('35%'), findsWidgets);
    expect(find.text('85%'), findsWidgets);
    expect(find.text('Ultra sensible'), findsWidgets);
    expect(find.text('Recommandée'), findsWidgets);
    expect(find.text('Robuste'), findsWidgets);
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
  });

  testWidgets('SettingsFallSensitivityCard has correct description text', (tester) async {
    final service = FallSensitivitySettingsService();
    await service.loadSettings();

    await tester.pumpWidget(buildTestWidget(service));

    // Default threshold should have equilibrium description
    expect(find.textContaining('Équilibre optimal'), findsOneWidget);
  });
}
