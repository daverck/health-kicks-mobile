import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/controllers/fall_alert_controller.dart';
import 'package:healthkicks_mobile/models/activity_detection_model.dart';
import 'package:healthkicks_mobile/models/fall_alert_model.dart';
import 'package:healthkicks_mobile/screens/fall_alert_screen.dart';
import 'package:healthkicks_mobile/services/location/fall_location_provider.dart';

void main() {
  group('FallAlertScreen Widget Tests', () {
    const liveFallDetection = ActivityDetectionModel(
      stateCode: 0x10,
      eventType: 'fall_forward',
      confidencePercent: 92,
      timestampEpochSec: 1792745943,
      isFall: true,
      isHapticTriggered: true,
    );

    testWidgets('Displays PENDING 60s countdown, cancel button, confirm button, and 112 button', (tester) async {
      final published = <FallAlertUplinkPayload>[];
      final controller = FallAlertController(
        deviceId: 'HK-1',
        locationProvider: const StaticFallLocationProvider(),
        isMqttConnectedGetter: () => true,
        onPublishUplink: (payload) async {
          published.add(payload);
          return true;
        },
      );

      await controller.onActivityDetected(liveFallDetection);

      await tester.pumpWidget(
        MaterialApp(
          home: FallAlertScreen(controller: controller),
        ),
      );

      expect(find.text('Chute détectée — Ça va ?'), findsOneWidget);
      expect(find.byKey(const Key('fall_alert_countdown_value')), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
      expect(find.text('Je vais bien (Annuler l\'alerte)'), findsOneWidget);
      expect(find.text('J\'ai besoin d\'aide maintenant'), findsOneWidget);
      expect(find.text('Appeler le 112'), findsOneWidget);

      // Tap "J'ai besoin d'aide maintenant"
      await tester.tap(find.byKey(const Key('fall_alert_confirm_button')));
      await tester.pump();

      expect(controller.state, equals('ESCALATING'));
      expect(published.last.action, equals('CONFIRM'));

      controller.dispose();
    });

    testWidgets('Updates UI across ESCALATING, ACKNOWLEDGED, and EXHAUSTED states', (tester) async {
      var called112 = false;
      final controller = FallAlertController(
        deviceId: 'HK-1',
        locationProvider: const StaticFallLocationProvider(),
        isMqttConnectedGetter: () => true,
        onPublishUplink: (_) async => true,
        onCall112: () async {
          called112 = true;
        },
      );

      await controller.onActivityDetected(liveFallDetection);
      final eventId = controller.activeEventId!;

      await tester.pumpWidget(
        MaterialApp(
          home: FallAlertScreen(controller: controller),
        ),
      );

      // Transition to ESCALATING (contact 2 of 4)
      controller.onDownlinkStatusReceived(FallAlertStatusModel(
        eventId: eventId,
        alertId: 10,
        state: 'ESCALATING',
        currentContactRank: 2,
        contactsTotal: 4,
      ));
      await tester.pump();

      expect(
        find.text('Alerte envoyée au proche n°2 sur 4 — En attente de confirmation…'),
        findsOneWidget,
      );
      expect(find.text('Je vais bien (Annuler l\'alerte)'), findsOneWidget);

      // Transition to ACKNOWLEDGED by Paul
      controller.onDownlinkStatusReceived(FallAlertStatusModel(
        eventId: eventId,
        alertId: 10,
        state: 'ACKNOWLEDGED',
        currentContactRank: 2,
        contactsTotal: 4,
        acknowledgedBy: const FallAlertAcknowledgedBy(firstName: 'Paul'),
      ));
      await tester.pump();

      expect(
        find.text('Rassurez-vous : Paul a pris en charge votre alerte'),
        findsOneWidget,
      );

      // Transition to EXHAUSTED -> 112 fallback
      controller.onDownlinkStatusReceived(FallAlertStatusModel(
        eventId: eventId,
        alertId: 10,
        state: 'EXHAUSTED',
        currentContactRank: 4,
        contactsTotal: 4,
      ));
      await tester.pump();

      expect(
        find.text('Aucun proche n\'a répondu — Appeler le 112'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('fall_alert_call_112_button')));
      await tester.pump();
      expect(called112, isTrue);

      controller.dispose();
    });
  });
}
