import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/ui/widgets/studio_session_dialog.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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
      expect(jump.isEdgeAi, isTrue);

      final custom = activities.firstWhere((a) => a.key == 'custom');
      expect(custom.isEdgeAi, isFalse);

      final lieDown = activities.firstWhere((a) => a.key == 'lie_down');
      expect(lieDown.isEdgeAi, isFalse);

      final lyingSupine = activities.firstWhere((a) => a.key == 'lying_supine');
      expect(lyingSupine.isEdgeAi, isTrue);

      final lyingProne = activities.firstWhere((a) => a.key == 'lying_prone');
      expect(lyingProne.isEdgeAi, isTrue);

      final lyingLateral = activities.firstWhere((a) => a.key == 'lying_lateral');
      expect(lyingLateral.isEdgeAi, isFalse);
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

    testWidgets('renders R&D tag when lie_down or custom is selected', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioSessionDialog(
              initialActivityKey: 'lie_down',
              onStartSession: ({required String label, required double durationSec}) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text("S'allonger (Transition) 🛏️"), findsOneWidget);
      expect(find.text('🧪 R&D'), findsOneWidget);
    });

    testWidgets('renders Edge AI tag when jump is selected', (WidgetTester tester) async {
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
      expect(find.text('⚡ Edge AI'), findsOneWidget);
    });

    testWidgets('displays Fermer button and pops dialog on tap', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showDialog<void>(
                  context: ctx,
                  builder: (_) => StudioSessionDialog(
                    onStartSession: ({required String label, required double durationSec}) async {},
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Fermer'), findsOneWidget);
      expect(find.text('Annuler'), findsNothing);

      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();

      expect(find.text('Fermer'), findsNothing);
    });

    testWidgets('keeps dialog open after capture and displays success message', (WidgetTester tester) async {
      var callCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioSessionDialog(
              initialActivityKey: 'walk',
              onStartSession: ({required String label, required double durationSec}) async {
                callCount++;
                return true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Capture réalisée avec succès'), findsNothing);

      // Tap start recording
      await tester.tap(find.text("Démarrer l'enregistrement"));
      await tester.pumpAndSettle();

      expect(callCount, 1);
      // Dialog remains mounted with success message
      expect(find.text('Enregistrement Studio'), findsOneWidget);
      expect(find.text('Capture réalisée avec succès'), findsOneWidget);
      expect(find.text("Démarrer l'enregistrement"), findsOneWidget);

      // Can immediately chain another capture
      await tester.tap(find.text("Démarrer l'enregistrement"));
      await tester.pumpAndSettle();

      expect(callCount, 2);
      expect(find.text('Capture réalisée avec succès'), findsOneWidget);
    });

    testWidgets('displays up to 8 recent activity shortcuts in two columns and evicts 8th oldest when 9th is recorded', (WidgetTester tester) async {
      expect(StudioSessionDialog.maxRecentActivities, equals(8));

      SharedPreferences.setMockInitialValues({
        StudioSessionDialog.prefRecentActivityKeys: [
          'run',
          'walk',
          'stairs',
          'idle',
          'sit_down',
          'stand_up',
          'lying_supine',
          'lying_prone',
        ],
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioSessionDialog(
              initialActivityKey: 'jump',
              onStartSession: ({required String label, required double durationSec}) async {
                return true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially displays all 8 existing recent shortcuts
      for (final key in ['run', 'walk', 'stairs', 'idle', 'sit_down', 'stand_up', 'lying_supine', 'lying_prone']) {
        expect(find.byKey(ValueKey('studio-recent-activity-$key')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('studio-recent-activity-jump')), findsNothing);

      // Verify two-column layout:
      // Row 0: 'run' (col 0) and 'walk' (col 1) share the same Y and have distinct X
      final runPos = tester.getTopLeft(find.byKey(const ValueKey('studio-recent-activity-run')));
      final walkPos = tester.getTopLeft(find.byKey(const ValueKey('studio-recent-activity-walk')));
      // Row 1: 'stairs' (col 0) and 'idle' (col 1) are on the next line
      final stairsPos = tester.getTopLeft(find.byKey(const ValueKey('studio-recent-activity-stairs')));
      final idlePos = tester.getTopLeft(find.byKey(const ValueKey('studio-recent-activity-idle')));

      expect(runPos.dy, equals(walkPos.dy));
      expect(runPos.dx, lessThan(walkPos.dx));
      expect(stairsPos.dy, equals(idlePos.dy));
      expect(stairsPos.dx, equals(runPos.dx));
      expect(idlePos.dx, equals(walkPos.dx));
      expect(stairsPos.dy, greaterThan(runPos.dy));

      // Start recording for the 9th activity ('jump')
      await tester.tap(find.text("Démarrer l'enregistrement"));
      await tester.pumpAndSettle();

      expect(find.text('Capture réalisée avec succès'), findsOneWidget);

      // 'jump' is now immediately at index 0, and the 8th oldest ('lying_prone') is evicted
      for (final key in ['jump', 'run', 'walk', 'stairs', 'idle', 'sit_down', 'stand_up', 'lying_supine']) {
        expect(find.byKey(ValueKey('studio-recent-activity-$key')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('studio-recent-activity-lying_prone')), findsNothing);

      // Verify visual order: 'jump' (col 0) appears to the left of 'run' (col 1) on the first row
      final jumpTopLeft = tester.getTopLeft(find.byKey(const ValueKey('studio-recent-activity-jump')));
      final runTopLeft = tester.getTopLeft(find.byKey(const ValueKey('studio-recent-activity-run')));
      expect(jumpTopLeft.dy, equals(runTopLeft.dy));
      expect(jumpTopLeft.dx, lessThan(runTopLeft.dx));
    });
  });
}

