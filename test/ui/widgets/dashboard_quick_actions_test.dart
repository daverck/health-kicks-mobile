import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/ui/widgets/dashboard/dashboard_quick_actions.dart';

void main() {
  group('DashboardQuickActions', () {
    testWidgets('disables both buttons when isConnected is false', (WidgetTester tester) async {
      var hapticTapped = false;
      var studioTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardQuickActions(
              onSendTestHaptic: () => hapticTapped = true,
              isClinicianOrAdmin: true,
              onOpenStudio: () => studioTapped = true,
              isConnected: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final hapticBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Test Haptique'));
      expect(hapticBtn.onPressed, isNull);

      final studioBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Studio'));
      expect(studioBtn.onPressed, isNull);

      // Verify tapping does not invoke callbacks
      await tester.tap(find.text('Test Haptique'), warnIfMissed: false);
      await tester.tap(find.text('Studio'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(hapticTapped, isFalse);
      expect(studioTapped, isFalse);
    });

    testWidgets('enables both buttons when isConnected is true and triggers callbacks', (WidgetTester tester) async {
      var hapticTapped = false;
      var studioTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardQuickActions(
              onSendTestHaptic: () => hapticTapped = true,
              isClinicianOrAdmin: true,
              onOpenStudio: () => studioTapped = true,
              isConnected: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final hapticBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Test Haptique'));
      expect(hapticBtn.onPressed, isNotNull);

      final studioBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Studio'));
      expect(studioBtn.onPressed, isNotNull);

      await tester.tap(find.text('Test Haptique'));
      await tester.pumpAndSettle();
      expect(hapticTapped, isTrue);

      await tester.tap(find.text('Studio'));
      await tester.pumpAndSettle();
      expect(studioTapped, isTrue);
    });

    testWidgets('hides Studio button when isClinicianOrAdmin is false', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DashboardQuickActions(
              onSendTestHaptic: () {},
              isClinicianOrAdmin: false,
              onOpenStudio: () {},
              isConnected: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Test Haptique'), findsOneWidget);
      expect(find.text('Studio'), findsNothing);
    });
  });
}

