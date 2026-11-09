import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:healthkicks_mobile/services/fall_sensitivity_settings_service.dart';
import 'package:healthkicks_mobile/ui/widgets/settings/fall_cooldown_slider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildTestWidget(FallSensitivitySettingsService service) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: FallCooldownSlider(
            fallSensitivityService: service,
            bleClient: null,
          ),
        ),
      ),
    );
  }

  testWidgets('FallCooldownSlider renders cooldown header, badges, and labels', (tester) async {
    final service = FallSensitivitySettingsService();
    await service.loadSettings();

    await tester.pumpWidget(buildTestWidget(service));

    expect(find.text('Délai entre deux alertes (Cooldown)'), findsOneWidget);
    expect(find.text('3 s'), findsOneWidget);
    expect(find.text('0.5 s'), findsOneWidget);
    expect(find.text('3 s (défaut)'), findsOneWidget);
    expect(find.text('30 s'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('FallCooldownSlider updates value upon user interaction', (tester) async {
    final service = FallSensitivitySettingsService();
    await service.loadSettings();

    await tester.pumpWidget(buildTestWidget(service));

    final slider = find.byType(Slider);
    await tester.drag(slider, const Offset(100, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(service.cooldownSeconds, greaterThan(3.0));
  });
}
