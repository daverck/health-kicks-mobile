import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/models/studio_session_model.dart';
import 'package:healthkicks_mobile/services/audio/studio_audio_feedback_service.dart';
import 'package:healthkicks_mobile/ui/widgets/studio_recording_dialog.dart';
import 'package:healthkicks_mobile/services/ble/ble_connection_manager.dart';

void main() {
  group('StudioRecordingDialog Widget Tests', () {
    late StreamController<String> statusController;
    late StreamController<StudioSessionModel> sessionSavedController;
    late StreamController<BleConnectionStatus> bleStatusController;

    setUp(() {
      statusController = StreamController<String>.broadcast();
      sessionSavedController = StreamController<StudioSessionModel>.broadcast();
      bleStatusController = StreamController<BleConnectionStatus>.broadcast();
    });

    tearDown(() {
      statusController.close();
      sessionSavedController.close();
      bleStatusController.close();
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

    testWidgets('allows finishing after two seconds and uses actual duration', (WidgetTester tester) async {
      var finishCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioRecordingDialog(
              label: 'walk',
              durationSec: 5.0,
              studioStatusStream: statusController.stream,
              sessionSavedStream: sessionSavedController.stream,
              onFinish: () async {
                finishCalled = true;
              },
            ),
          ),
        ),
      );

      statusController.add('RECORDING 5.0');
      await tester.pump();
      expect(find.text('Terminer'), findsNothing);

      await tester.pump(const Duration(milliseconds: 1950));
      expect(find.text('Terminer'), findsNothing);

      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Terminer'), findsOneWidget);

      await tester.tap(find.text('Terminer'));
      await tester.pump();
      expect(finishCalled, isTrue);
      expect(find.text('Arrêt...'), findsOneWidget);

      statusController.add('FINISHED 105 test-session-id 2.1');
      await tester.pump();
      expect(find.text('⚡ Synchronisation des données biomécaniques...'), findsOneWidget);

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

    testWidgets('triggers audio feedback service throughout countdown and recording', (WidgetTester tester) async {
      final audioService = StudioAudioFeedbackService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioRecordingDialog(
              label: 'walk',
              durationSec: 5.0,
              studioStatusStream: statusController.stream,
              sessionSavedStream: sessionSavedController.stream,
              audioService: audioService,
            ),
          ),
        ),
      );

      // On init, first countdown beep is played
      expect(audioService.countdownBeepsPlayed, 1);
      expect(audioService.isContinuousPlaying, isFalse);

      // Next countdown step
      statusController.add('COUNTDOWN 2/3');
      await tester.pump(const Duration(milliseconds: 10));
      expect(audioService.countdownBeepsPlayed, 2);

      // Recording starts: continuous tone starts
      statusController.add('RECORDING 5.0');
      await tester.pump();
      expect(audioService.isContinuousPlaying, isTrue);

      // Session finished: continuous tone stops
      statusController.add('FINISHED 250 test-session-id');
      await tester.pump();
      expect(audioService.isContinuousPlaying, isFalse);

      // Session saved: finished chime played
      const mockSession = StudioSessionModel(
        sessionId: 'test-session-id',
        label: 'walk',
        deviceId: 'HK-2',
        startTimestampEpoch: 1700000000.0,
        durationSec: 5.0,
        readings: [],
      );
      sessionSavedController.add(mockSession);
      await tester.pump();
      expect(audioService.isContinuousPlaying, isFalse);

      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('allows abandoning transfer during transmitting state', (WidgetTester tester) async {
      bool cancelCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioRecordingDialog(
              label: 'walk',
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

      statusController.add('FINISHED 250 test-session-id');
      await tester.pump();

      expect(find.text('⚡ Synchronisation des données biomécaniques...'), findsOneWidget);
      expect(find.text('Abandonner'), findsOneWidget);

      await tester.tap(find.text('Abandonner'));
      await tester.pump();

      expect(cancelCalled, isTrue);

      statusController.add('CANCELLED');
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('shows error when transmission times out after 15 seconds', (WidgetTester tester) async {
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

      statusController.add('FINISHED 250 test-session-id');
      await tester.pump();

      expect(find.text('⚡ Synchronisation des données biomécaniques...'), findsOneWidget);

      // Advance 15 seconds
      await tester.pump(const Duration(seconds: 15));

      expect(find.text('Erreur Studio'), findsOneWidget);
      expect(find.textContaining('Délai d\'envoi dépassé'), findsOneWidget);
      expect(find.text('Fermer'), findsOneWidget);

      statusController.add('CANCELLED');
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('displays error and enables close button when BLE disconnects during session', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioRecordingDialog(
              label: 'walk',
              durationSec: 5.0,
              studioStatusStream: statusController.stream,
              sessionSavedStream: sessionSavedController.stream,
              connectionStatusStream: bleStatusController.stream,
            ),
          ),
        ),
      );

      // Start recording
      statusController.add('RECORDING 5.0');
      await tester.pump();
      expect(find.text('🔴 Enregistrement en cours...'), findsOneWidget);

      // BLE disconnects unexpectedly
      bleStatusController.add(BleConnectionStatus.disconnected);
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Erreur Studio'), findsOneWidget);
      expect(find.textContaining('Connexion Bluetooth avec la chaussure interrompue.'), findsOneWidget);
      expect(find.text('Fermer'), findsOneWidget);
    });

    testWidgets('watchdog timer triggers error if recording completes without receiving FINISHED', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioRecordingDialog(
              label: 'walk',
              durationSec: 5.0,
              studioStatusStream: statusController.stream,
              sessionSavedStream: sessionSavedController.stream,
              connectionStatusStream: bleStatusController.stream,
            ),
          ),
        ),
      );

      statusController.add('RECORDING 5.0');
      await tester.pump();

      // Advance durationSec (5.0s) + 6.0s = 11s watchdog timeout
      await tester.pump(const Duration(seconds: 12));

      expect(find.text('Erreur Studio'), findsOneWidget);
      expect(find.textContaining("Délai de capture dépassé"), findsOneWidget);
      expect(find.text('Fermer'), findsOneWidget);
    });

    testWidgets('onCancel dismisses dialog gracefully even if cancel callback throws or times out', (WidgetTester tester) async {
      bool dialogPopped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (_) => StudioRecordingDialog(
                    label: 'walk',
                    durationSec: 5.0,
                    studioStatusStream: statusController.stream,
                    sessionSavedStream: sessionSavedController.stream,
                    onCancel: () async {
                      throw StateError('BLE write failed on disconnected device');
                    },
                  ),
                ).then((_) => dialogPopped = true);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Session Studio : walk'), findsOneWidget);

      // Tap Annuler
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(dialogPopped, isTrue);
      expect(find.text('Session Studio : walk'), findsNothing);
    });
      test('StudioRecordingGauge.computeProgressColor smoothly transitions red to green at 65%', () {
      final colorAt0 = StudioRecordingGauge.computeProgressColor(0.0);
      expect(colorAt0.toARGB32(), Colors.redAccent.toARGB32());

      // At half-threshold (~32.5%), should be orange/amber
      final colorAtHalfway = StudioRecordingGauge.computeProgressColor(0.325);
      expect(colorAtHalfway.toARGB32(), Colors.orangeAccent.toARGB32());

      // At 65%, should reach full green
      final colorAt65 = StudioRecordingGauge.computeProgressColor(0.65);
      expect(colorAt65.toARGB32(), const Color(0xFF10B981).toARGB32());

      // Beyond 65%, stays green
      final colorAt80 = StudioRecordingGauge.computeProgressColor(0.80);
      expect(colorAt80.toARGB32(), const Color(0xFF10B981).toARGB32());

      final colorAt100 = StudioRecordingGauge.computeProgressColor(1.0);
      expect(colorAt100.toARGB32(), const Color(0xFF10B981).toARGB32());
    });
});
}
