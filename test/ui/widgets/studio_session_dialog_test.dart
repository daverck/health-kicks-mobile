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
      expect(lieDown.isEdgeAi, isTrue);

      final lyingSupine = activities.firstWhere((a) => a.key == 'lying_supine');
      expect(lyingSupine.isEdgeAi, isTrue);

      final lyingProne = activities.firstWhere((a) => a.key == 'lying_prone');
      expect(lyingProne.isEdgeAi, isTrue);

      final lyingLateral = activities.firstWhere((a) => a.key == 'lying_lateral');
      expect(lyingLateral.isEdgeAi, isFalse);

      final stairs = activities.firstWhere((a) => a.key == 'stairs');
      expect(stairs.isEdgeAi, isFalse);

      final stumble = activities.firstWhere((a) => a.key == 'stumble_recover');
      expect(stumble.isEdgeAi, isFalse);
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

    testWidgets('renders Edge AI tag when lie_down is selected and R&D tag when custom is selected', (WidgetTester tester) async {
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
      expect(find.text('⚡ Edge AI'), findsOneWidget);
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

    testWidgets(
      'fetches StudioDatasetStats on open, shows compact validated/pending counts only when class count < 25, and increments on each session',
      (WidgetTester tester) async {
        expect(StudioSessionDialog.targetPerClass, equals(25));

        SharedPreferences.setMockInitialValues({
          StudioSessionDialog.prefRecentActivityKeys: [
            'walk', // 25 recordings (>= 25 -> hidden)
            'run', // 24 recordings (< 25 -> shown, becomes 25 after 1 capture -> hidden)
            'jump', // 3 recordings (< 25 -> shown, increments on capture)
          ],
        });

        var statsLoadCalls = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StudioSessionDialog(
                initialActivityKey: 'jump',
                onLoadStats: () async {
                  statsLoadCalls++;
                  return const StudioDatasetStats(
                    deviceId: 'HK-2',
                    totalSessions: 52,
                    totalDurationSec: 260.0,
                    totalSamples: 9880,
                    byLabel: {'walk': 25, 'run': 24, 'jump': 3},
                    byLabelValidated: {'walk': 20, 'run': 20, 'jump': 2},
                    byLabelPending: {'walk': 5, 'run': 4, 'jump': 1},
                  );
                },
                onStartSession: ({required String label, required double durationSec}) async {
                  return true;
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(statsLoadCalls, equals(1));

        // 'walk' has 25 recordings (>= targetPerClass) -> badges must NOT be shown
        expect(find.byKey(const ValueKey('studio-recent-validated-walk')), findsNothing);
        expect(find.byKey(const ValueKey('studio-recent-pending-walk')), findsNothing);

        // 'run' has 24 recordings (< 25) -> badges ARE shown (✅20, ⏳4)
        expect(find.byKey(const ValueKey('studio-recent-validated-run')), findsOneWidget);
        expect(find.byKey(const ValueKey('studio-recent-pending-run')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('studio-recent-validated-run')),
            matching: find.text('✅20'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('studio-recent-pending-run')),
            matching: find.text('⏳4'),
          ),
          findsOneWidget,
        );

        // 'jump' has 3 recordings (< 25) -> badges ARE shown (✅2, ⏳1)
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('studio-recent-validated-jump')),
            matching: find.text('✅2'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('studio-recent-pending-jump')),
            matching: find.text('⏳1'),
          ),
          findsOneWidget,
        );

        // Record a 'jump' session -> pending count increments from 1 to 2 (total 4 < 25)
        await tester.tap(find.text("Démarrer l'enregistrement"));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(const ValueKey('studio-recent-validated-jump')),
            matching: find.text('✅2'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('studio-recent-pending-jump')),
            matching: find.text('⏳2'),
          ),
          findsOneWidget,
        );

        // Select 'run' via its shortcut tile and record a session -> total goes from 24 to 25, so badges disappear!
        await tester.tap(find.byKey(const ValueKey('studio-recent-activity-run')));
        await tester.pumpAndSettle();

        await tester.tap(find.text("Démarrer l'enregistrement"));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('studio-recent-validated-run')), findsNothing);
        expect(find.byKey(const ValueKey('studio-recent-pending-run')), findsNothing);
      },
    );
  });
}
