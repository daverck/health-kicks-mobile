import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:healthkicks_mobile/services/integrations/health_connect_service.dart';
import 'package:healthkicks_mobile/ui/widgets/settings/settings_health_connect_card.dart';

class MockHealthForCard extends Health {
  bool available = true;
  bool authGranted = true;

  @override
  Future<void> configure() async {}

  @override
  Future<bool> isHealthConnectAvailable() async => available;

  @override
  Future<bool?> hasPermissions(List<HealthDataType> types, {List<HealthDataAccess>? permissions}) async => true;

  @override
  Future<bool> requestAuthorization(List<HealthDataType> types, {List<HealthDataAccess>? permissions}) async => authGranted;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildTestWidget(HealthConnectService service) {
    return MaterialApp(
      home: Scaffold(
        body: SettingsHealthConnectCard(healthConnectService: service),
      ),
    );
  }

  testWidgets('SettingsHealthConnectCard renders title, subtitle and switch', (tester) async {
    final mockHealth = MockHealthForCard();
    final service = HealthConnectService(health: mockHealth);
    await service.init();

    await tester.pumpWidget(buildTestWidget(service));

    expect(find.text('Google Health Connect'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(find.byIcon(Icons.health_and_safety_outlined), findsOneWidget);

    final switchFinder = find.byType(Switch);
    final switchWidget = tester.widget<Switch>(switchFinder);
    expect(switchWidget.value, isFalse);
  });

  testWidgets('SettingsHealthConnectCard reflects active state and last sync', (tester) async {
    final mockHealth = MockHealthForCard();
    final now = DateTime.utc(2026, 10, 18, 14, 25, 0);
    SharedPreferences.setMockInitialValues({
      HealthConnectService.keyEnabled: true,
      HealthConnectService.keyLastSync: now.toIso8601String(),
    });

    final service = HealthConnectService(health: mockHealth);
    await service.init();

    await tester.pumpWidget(buildTestWidget(service));

    final switchFinder = find.byType(Switch);
    final switchWidget = tester.widget<Switch>(switchFinder);
    expect(switchWidget.value, isTrue);
    expect(find.textContaining('Actif • Dernière synchro'), findsOneWidget);
  });

  testWidgets('SettingsHealthConnectCard renders Apple Santé title and icon on iOS', (tester) async {
    final mockHealth = MockHealthForCard();
    final service = HealthConnectService(health: mockHealth, isIosOverride: true);
    await service.init();

    await tester.pumpWidget(buildTestWidget(service));

    expect(find.text('Apple Santé (HealthKit)'), findsOneWidget);
    expect(find.text('Exporter les pas de la chaussure vers Apple Santé'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_outline), findsOneWidget);
  });

  testWidgets('Toggling switch ON on iOS requests permissions and enables sync', (tester) async {
    final mockHealth = MockHealthForCard();
    final service = HealthConnectService(health: mockHealth, isIosOverride: true);
    await service.init();

    await tester.pumpWidget(buildTestWidget(service));

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(service.isEnabled, isTrue);
    expect(find.text('Synchronisation Apple Santé activée !'), findsOneWidget);
  });

  testWidgets('Toggling switch OFF on iOS disables sync', (tester) async {
    final mockHealth = MockHealthForCard();
    final service = HealthConnectService(health: mockHealth, isIosOverride: true);
    await service.init();
    await service.setEnabled(true);

    await tester.pumpWidget(buildTestWidget(service));

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(service.isEnabled, isFalse);
    expect(find.text('Synchronisation Apple Santé désactivée.'), findsOneWidget);
  });
}
