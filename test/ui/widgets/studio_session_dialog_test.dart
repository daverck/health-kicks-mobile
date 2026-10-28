import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/ui/widgets/studio_session_dialog.dart';

void main() {
  group('StudioSessionDialog', () {
    test('defaultActivities contains sit_down and stand_up options with correct Edge AI tags', () {
      const activities = StudioSessionDialog.defaultActivities;
      final sitDown = activities.firstWhere((a) => a.key == 'sit_down');
      expect(sitDown.label, equals("S'asseoir (Transition)"));
      expect(sitDown.emoji, equals('🪑'));
      expect(sitDown.isEdgeAi, isTrue);

      final standUp = activities.firstWhere((a) => a.key == 'stand_up');
      expect(standUp.label, equals('Se lever (Transition)'));
      expect(standUp.emoji, equals('🧍'));
      expect(standUp.isEdgeAi, isTrue);

      final sitDownIndex = activities.indexWhere((a) => a.key == 'sit_down');
      final standUpIndex = activities.indexWhere((a) => a.key == 'stand_up');
      expect(standUpIndex, equals(sitDownIndex + 1));

      final jump = activities.firstWhere((a) => a.key == 'jump');
      expect(jump.isEdgeAi, isFalse);

      final custom = activities.firstWhere((a) => a.key == 'custom');
      expect(custom.isEdgeAi, isFalse);
    });

    testWidgets('renders sit_down option and Edge AI tag in dropdown', (WidgetTester tester) async {
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
      expect(find.text('⚡ Edge AI'), findsOneWidget);
    });

    testWidgets('renders stand_up option when selected', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioSessionDialog(
              initialActivityKey: 'stand_up',
              onStartSession: ({required String label, required double durationSec}) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Se lever (Transition) 🧍'), findsOneWidget);
      expect(find.text('⚡ Edge AI'), findsOneWidget);
    });

    testWidgets('renders R&D tag when jump or custom is selected', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioSessionDialog(
              initialActivityKey: 'jump',
              onStartSession: ({required String label, required double durationSec}) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Saut 🦘'), findsOneWidget);
      expect(find.text('🧪 R&D'), findsOneWidget);
    });
  });
}
