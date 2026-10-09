import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/models/studio_session_model.dart';
import 'package:healthkicks_mobile/ui/widgets/studio_recording_dialog.dart';

void main() {
  group('StudioRecordingDialog Widget Tests', () {
    late StreamController<String> statusController;
    late StreamController<StudioSessionModel> sessionSavedController;

    setUp(() {
      statusController = StreamController<String>.broadcast();
      sessionSavedController = StreamController<StudioSessionModel>.broadcast();
    });

    tearDown(() {
      statusController.close();
      sessionSavedController.close();
    });

    testWidgets('shows countdown step and badge on COUNTDOWN events', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioRecordingDialog(
              label: 'walk',
              durationSec: 5.0,
              studioStatusStream: statusController.stream,
              sessionSavedStream: sessionSavedController.stream,
            ),
          ),
        ),
      );

      // Initial state is countdown step 1 (remaining steps: 3)
      expect(find.text('Session Studio : walk'), findsOneWidget);
      expect(find.text('Préparez-vous : 3... 2... 1...'), findsOneWidget);
      expect(find.byKey(const Key('countdown_step_text')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('countdown_step_text'))).data, '3');
      expect(find.text('🚶'), findsOneWidget);

      // Emit COUNTDOWN 2/3 (remaining steps: 2)
      statusController.add('COUNTDOWN 2/3');
      await tester.pump(const Duration(milliseconds: 10));
      expect(tester.widget<Text>(find.byKey(const Key('countdown_step_text'))).data, '2');

      // Emit COUNTDOWN 3/3 (remaining steps: 1)
      statusController.add('COUNTDOWN 3/3');
      await tester.pump(const Duration(milliseconds: 10));
      expect(tester.widget<Text>(find.byKey(const Key('countdown_step_text'))).data, '1');
    });

    testWidgets('shows progress bar and timer when stream emits RECORDING', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioRecordingDialog(
              label: 'run',
              durationSec: 5.0,
              studioStatusStream: statusController.stream,
              sessionSavedStream: sessionSavedController.stream,
            ),
          ),
        ),
      );

      statusController.add('RECORDING 5.0');
      await tester.pump();

      expect(find.text('🔴 Enregistrement en cours...'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Annuler'), findsOneWidget);

      // Advance clock by 1 second
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('/ 5.0s'), findsOneWidget);

      // Complete to stop periodic timer
      statusController.add('CANCELLED');
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('shows transmitting state on FINISHED and success on session saved', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioRecordingDialog(
              label: 'stairs',
              durationSec: 5.0,
              studioStatusStream: statusController.stream,
              sessionSavedStream: sessionSavedController.stream,
            ),
          ),
        ),
      );

      // Emit FINISHED
      statusController.add('FINISHED 250 test-session-id');
      await tester.pump();

      expect(find.text('⚡ Synchronisation des données biomécaniques...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Emit saved session event
      const mockSession = StudioSessionModel(
        sessionId: 'test-session-id',
        label: 'stairs',
        deviceId: 'HK-2',
        startTimestampEpoch: 1700000000.0,
        durationSec: 5.0,
        readings: [],
      );
      sessionSavedController.add(mockSession);
      await tester.pump();

      expect(find.text('✅ Capture terminée avec succès !'), findsOneWidget);

      // Advance to allow auto-dismiss timer to complete
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('triggers onCancel when Annuler button is pressed', (WidgetTester tester) async {
      bool cancelCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioRecordingDialog(
              label: 'jump',
              durationSec: 5.0,
              studioStatusStream: statusController.stream,
              sessionSavedStream: sessionSavedController.stream,
              onCancel: () async {
                cancelCalled = true;
              },
            ),
          ),
        ),
      );

      statusController.add('RECORDING 5.0');
      await tester.pump();

      expect(find.text('Annuler'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pump();

      expect(cancelCalled, isTrue);

      // Drain periodic timer
      statusController.add('CANCELLED');
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('displays error feedback when stream emits ERROR', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioRecordingDialog(
              label: 'walk',
              durationSec: 5.0,
              studioStatusStream: statusController.stream,
              sessionSavedStream: sessionSavedController.stream,
            ),
          ),
        ),
      );

      statusController.add('ERROR buffer_overflow');
      await tester.pump();

      expect(find.text('Erreur Studio'), findsOneWidget);
      expect(find.text('buffer_overflow'), findsOneWidget);
      expect(find.text('Fermer'), findsOneWidget);
    });

    testWidgets('displays cancelled feedback when stream emits CANCELLED', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioRecordingDialog(
              label: 'walk',
              durationSec: 5.0,
              studioStatusStream: statusController.stream,
              sessionSavedStream: sessionSavedController.stream,
            ),
          ),
        ),
      );

      statusController.add('CANCELLED');
      await tester.pump();

      expect(find.text('Session annulée'), findsOneWidget);

      // Drain dismiss timer
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('progresses countdown autonomously if BLE notifications are delayed or dropped', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioRecordingDialog(
              label: 'walk',
              durationSec: 5.0,
              studioStatusStream: statusController.stream,
              sessionSavedStream: sessionSavedController.stream,
            ),
          ),
        ),
      );

      // Initial state is step 1 -> remaining 3
      expect(tester.widget<Text>(find.byKey(const Key('countdown_step_text'))).data, '3');

      // 1 second elapses without any BLE packet: should tick to step 2 -> remaining 2
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<Text>(find.byKey(const Key('countdown_step_text'))).data, '2');

      // 1 second elapses: should tick to step 3 -> remaining 1
      await tester.pump(const Duration(seconds: 1));
      expect(tester.widget<Text>(find.byKey(const Key('countdown_step_text'))).data, '1');

      // 1 second elapses: should transition to recording
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('🔴 Enregistrement en cours...'), findsOneWidget);

      // Drain periodic timer
      statusController.add('CANCELLED');
      await tester.pump(const Duration(seconds: 2));
    });
  });
}
