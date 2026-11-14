import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/services/audio/studio_audio_feedback_service.dart';
import 'package:healthkicks_mobile/ui/widgets/imu_calibration_dialog.dart';

void main() {
  group('ImuCalibrationDialog Widget & Audio Feedback Tests', () {
    late StreamController<String> statusController;
    late StudioAudioFeedbackService audioService;

    setUp(() {
      statusController = StreamController<String>.broadcast();
      audioService = StudioAudioFeedbackService();
    });

    tearDown(() {
      statusController.close();
      audioService.dispose();
    });

    testWidgets('starts continuous tone on calibration start and plays chime on success', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImuCalibrationDialog(
              onCalibrate: () async {},
              isConnected: true,
              studioStatusStream: statusController.stream,
              audioService: audioService,
            ),
          ),
        ),
      );

      expect(find.text('Calibration de l\'Assiette'), findsOneWidget);
      expect(find.text('Démarrer'), findsOneWidget);
      expect(audioService.isContinuousPlaying, isFalse);

      // Start calibration
      await tester.tap(find.text('Démarrer'));
      await tester.pump();

      expect(find.text('Mesure de l\'assiette en cours...\nNe bougez pas la chaussure.'), findsOneWidget);
      expect(audioService.isContinuousPlaying, isTrue);

      // Shoes emits CALIBRATION_OK
      statusController.add('STATUS CALIBRATION_OK');
      await tester.pump();

      expect(audioService.isContinuousPlaying, isFalse);
      expect(find.textContaining('Calibration réussie !'), findsOneWidget);
      expect(find.text('Terminer'), findsOneWidget);
    });

    testWidgets('completes countdown autonomously after 4.0 seconds and triggers success chime', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImuCalibrationDialog(
              onCalibrate: () async {},
              isConnected: true,
              audioService: audioService,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Démarrer'));
      await tester.pump();

      expect(audioService.isContinuousPlaying, isTrue);

      // Advance 4.1 seconds to trigger autonomous timer completion
      await tester.pump(const Duration(milliseconds: 4100));

      expect(audioService.isContinuousPlaying, isFalse);
      expect(find.textContaining('Calibration réussie !'), findsOneWidget);
    });

    testWidgets('stops continuous tone on error from footwear', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImuCalibrationDialog(
              onCalibrate: () async {},
              isConnected: true,
              studioStatusStream: statusController.stream,
              audioService: audioService,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Démarrer'));
      await tester.pump();
      expect(audioService.isContinuousPlaying, isTrue);

      // BLE transmits calibration failure
      statusController.add('STATUS CALIBRATION_ERROR');
      await tester.pump();

      expect(audioService.isContinuousPlaying, isFalse);
      expect(find.textContaining('Erreur de calibration reçue de la chaussure.'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    });

    testWidgets('stops continuous tone on cancel during calibration', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImuCalibrationDialog(
              onCalibrate: () async {},
              isConnected: true,
              audioService: audioService,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Démarrer'));
      await tester.pump();
      expect(audioService.isContinuousPlaying, isTrue);

      // Tap Annuler while calibrating
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(audioService.isContinuousPlaying, isFalse);
      expect(find.text('Calibration de l\'Assiette'), findsNothing);
    });

    testWidgets('stops tone on widget disposal', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (_) => ImuCalibrationDialog(
                    onCalibrate: () async {},
                    isConnected: true,
                    audioService: audioService,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Démarrer'));
      await tester.pump();
      expect(audioService.isContinuousPlaying, isTrue);

      // Pop route via Navigator
      final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
      navigatorState.pop();
      await tester.pumpAndSettle();

      expect(audioService.isContinuousPlaying, isFalse);
    });
  });
}
