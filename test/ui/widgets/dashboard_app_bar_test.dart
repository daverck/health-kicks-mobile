import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/ui/widgets/dashboard/dashboard_app_bar.dart';

void main() {
  testWidgets('does not display a device ID in the dashboard header',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: DashboardAppBar(
            onOpenStepsHistory: () {},
            onOpenDetectionEventsHistory: () {},
            onOpenSettings: () {},
          ),
        ),
      ),
    );

    expect(find.text('HK-2'), findsNothing);
    expect(find.byIcon(Icons.perm_identity), findsNothing);
  });
}
