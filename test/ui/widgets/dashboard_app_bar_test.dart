import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/ui/widgets/dashboard/dashboard_app_bar.dart';

void main() {
  testWidgets('displays HealthKicks title and does not display device ID or history buttons',
      (tester) async {
    bool settingsOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: DashboardAppBar(
            onOpenSettings: () {
              settingsOpened = true;
            },
          ),
        ),
      ),
    );

    // Verify app bar title is HealthKicks
    expect(find.text('HealthKicks'), findsOneWidget);
    expect(find.text('HealthKicks BLE-to-MQTT Gateway'), findsNothing);
    
    expect(find.text('HK-2'), findsNothing);
    expect(find.byIcon(Icons.perm_identity), findsNothing);

    // Verify history buttons are not in the header
    expect(find.byIcon(Icons.show_chart_rounded), findsNothing);
    expect(find.byIcon(Icons.history_rounded), findsNothing);
    expect(find.byTooltip('Historique des Pas'), findsNothing);
    expect(find.byTooltip('Historique des Événements'), findsNothing);

    // Verify settings button is present and triggers callback
    final settingsBtn = find.byIcon(Icons.settings_outlined);
    expect(settingsBtn, findsOneWidget);
    await tester.tap(settingsBtn);
    expect(settingsOpened, isTrue);
  });
}
