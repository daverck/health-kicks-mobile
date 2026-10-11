import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/ui/widgets/studio_session_dialog.dart';

void main() {
  group('StudioSessionDialog', () {
    test('defaultActivities contains sit_down option after idle', () {
      const activities = StudioSessionDialog.defaultActivities;
      final sitDown = activities.firstWhere((a) => a.key == 'sit_down');
      expect(sitDown.label, equals("S'asseoir (Transition)"));
      expect(sitDown.emoji, equals('🪑'));

      final idleIndex = activities.indexWhere((a) => a.key == 'idle');
      final sitDownIndex = activities.indexWhere((a) => a.key == 'sit_down');
      expect(sitDownIndex, equals(idleIndex + 1));
    });

    testWidgets('renders sit_down option in dropdown', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioSessionDialog(
              initialActivityKey: 'sit_down',
              onStartSession: ({required String label, required double durationSec}) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("S'asseoir (Transition) 🪑"), findsOneWidget);
    });
  });
}
