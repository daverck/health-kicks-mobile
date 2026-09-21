import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/models/detection_event.dart';
import 'package:healthkicks_mobile/services/event_history_notifier.dart';
import 'package:healthkicks_mobile/services/event_history_service.dart';
import 'package:healthkicks_mobile/ui/screens/detection_events_history_screen.dart';

class FakeEventHistoryService extends EventHistoryService {
  final List<DetectionEvent> mockedEvents;
  final bool shouldThrow;

  FakeEventHistoryService({
    this.mockedEvents = const [],
    this.shouldThrow = false,
  });

  @override
  Future<EventHistoryResponse> fetchEvents({
    int page = 1,
    int size = 20,
    String category = 'all',
    String? deviceId,
  }) async {
    if (shouldThrow) {
      throw Exception('Erreur réseau de test');
    }

    final filtered = category == 'all'
        ? mockedEvents
        : mockedEvents.where((e) {
            if (category == 'falls') return e.severity == EventSeverity.critical;
            if (category == 'impacts') return e.severity == EventSeverity.warning;
            return e.severity == EventSeverity.info;
          }).toList();

    return EventHistoryResponse(
      events: filtered,
      total: filtered.length,
      page: page,
      size: size,
      hasMore: false,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final sampleEvents = [
    DetectionEvent(
      id: 'evt-fall-1',
      deviceId: 'HK-2',
      eventType: 'fall_detected',
      timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
      severity: EventSeverity.critical,
      peakImpactG: 3.2,
      confidence: 0.96,
      isValidated: true,
      metadata: {'room': 'salon'},
    ),
    DetectionEvent(
      id: 'evt-walk-2',
      deviceId: 'HK-2',
      eventType: 'walk',
      timestamp: DateTime.now().subtract(const Duration(minutes: 25)),
      severity: EventSeverity.info,
      confidence: 0.88,
      isValidated: false,
    ),
  ];

  group('DetectionEventsHistoryScreen - UI & Interactions', () {
    testWidgets('Displays AppBar and FilterChips correctly', (tester) async {
      final fakeService = FakeEventHistoryService(mockedEvents: sampleEvents);
      final notifier = EventHistoryNotifier(service: fakeService);

      await tester.pumpWidget(
        MaterialApp(
          home: DetectionEventsHistoryScreen(notifier: notifier),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Historique des Événements'), findsOneWidget);
      expect(find.text('Tous'), findsOneWidget);
      expect(find.text('Chutes / Urgences'), findsOneWidget);
      expect(find.text('Impacts'), findsOneWidget);
      expect(find.text('Activité'), findsOneWidget);
    });

    testWidgets('Displays list of DetectionEventCard and opens detail sheet on tap', (tester) async {
      final fakeService = FakeEventHistoryService(mockedEvents: sampleEvents);
      final notifier = EventHistoryNotifier(service: fakeService);

      await tester.pumpWidget(
        MaterialApp(
          home: DetectionEventsHistoryScreen(notifier: notifier),
        ),
      );
      await tester.pumpAndSettle();

      // Verify event cards
      expect(find.text('Chute détectée'), findsOneWidget);
      expect(find.text('Marche'), findsOneWidget);
      expect(find.text('3.2 g'), findsOneWidget);

      // Tap on the critical fall card to open modal bottom sheet
      await tester.tap(find.text('Chute détectée'));
      await tester.pumpAndSettle();

      // Verify BottomSheet contents
      expect(find.text('Horodatage précis'), findsOneWidget);
      expect(find.text('Pic d\'impact'), findsOneWidget);
      expect(find.text('3.20 g'), findsOneWidget);
      expect(find.text('Confiance ML'), findsOneWidget);
      expect(find.text('96.0 %'), findsOneWidget);
      expect(find.text('CRITICAL'), findsOneWidget);
      expect(find.text('Fermer'), findsOneWidget);

      // Close bottom sheet
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      expect(find.text('Pic d\'impact'), findsNothing);
    });

    testWidgets('Displays empty state when no events are returned', (tester) async {
      final fakeService = FakeEventHistoryService(mockedEvents: []);
      final notifier = EventHistoryNotifier(service: fakeService);

      await tester.pumpWidget(
        MaterialApp(
          home: DetectionEventsHistoryScreen(notifier: notifier),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Aucun événement détecté'), findsOneWidget);
      expect(
        find.text('Les alertes et événements biomécaniques enregistrés pour cette catégorie s\'afficheront ici.'),
        findsOneWidget,
      );
    });

    testWidgets('Displays error state and allows retry on network failure', (tester) async {
      final fakeService = FakeEventHistoryService(shouldThrow: true);
      final notifier = EventHistoryNotifier(service: fakeService);

      await tester.pumpWidget(
        MaterialApp(
          home: DetectionEventsHistoryScreen(notifier: notifier),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Erreur de chargement'), findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);
    });
  });
}
