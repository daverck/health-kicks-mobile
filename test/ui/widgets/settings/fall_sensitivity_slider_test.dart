import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:healthkicks_mobile/services/fall_sensitivity_settings_service.dart';
import 'package:healthkicks_mobile/ui/widgets/settings/fall_sensitivity_slider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildTestWidget(FallSensitivitySettingsService service) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: FallSensitivitySlider(
            fallSensitivityService: service,
            bleClient: null,
          ),
        ),
      ),
    );
  }

  testWidgets('FallSensitivitySlider renders sensitivity badges, descriptions, and labels', (tester) async {
    final service = FallSensitivitySettingsService();
    await service.loadSettings();

    await tester.pumpWidget(buildTestWidget(service));

    expect(find.text('Niveau actuel:'), findsOneWidget);
    expect(find.text('Équilibrée'), findsWidgets);
    expect(find.text('65%'), findsWidgets);
    expect(find.text('Ultra sensible'), findsOneWidget);
    expect(find.text('Robuste'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('FallSensitivitySlider reacts to slider changes and debounce', (tester) async {
    final service = FallSensitivitySettingsService();
    await service.loadSettings();

    await tester.pumpWidget(buildTestWidget(service));

    final slider = find.byType(Slider);
    await tester.drag(slider, const Offset(-100, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(service.threshold, lessThan(0.65));
  });
}
