import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/models/activity_detection_model.dart';
import 'package:healthkicks_mobile/models/hitl/hitl_detection_item.dart';
import 'package:healthkicks_mobile/services/hitl/hitl_coordinator.dart';
import 'package:healthkicks_mobile/ui/widgets/events/hitl_history_view.dart';

void main() {
  ActivityDetectionModel createDetection({
    required String label,
    bool isFall = false,
  }) {
    return ActivityDetectionModel(
      stateCode: 0x02,
      eventType: label,
      confidencePercent: 95,
      timestampEpochSec: 1000,
      isFall: isFall,
      isHapticTriggered: false,
    );
  }

  HitlDetectionItem createItem({
    required String id,
    required String label,
    bool isFall = false,
  }) {
    return HitlDetectionItem(
      id: id,
      timestamp: DateTime.now(),
      detectedLabel: label,
      confidencePercent: 95,
      isFall: isFall,
      rawDetection: createDetection(label: label, isFall: isFall),
    );
  }

  group('matchesHitlCategory tests', () {
    final walkItem = createItem(id: '1', label: 'walk', isFall: false);
    final fallItem = createItem(id: '2', label: 'fall_forward', isFall: true);
    final impactItem = createItem(id: '3', label: 'free_fall', isFall: false);

    test('all category matches everything', () {
      expect(matchesHitlCategory(walkItem, 'all'), isTrue);
      expect(matchesHitlCategory(fallItem, 'all'), isTrue);
      expect(matchesHitlCategory(impactItem, 'all'), isTrue);
    });

    test('falls category matches fall events', () {
      expect(matchesHitlCategory(fallItem, 'falls'), isTrue);
      expect(matchesHitlCategory(walkItem, 'falls'), isFalse);
    });

    test('impacts category matches impact-related labels', () {
      expect(matchesHitlCategory(impactItem, 'impacts'), isTrue);
      expect(matchesHitlCategory(walkItem, 'impacts'), isFalse);
    });

    test('activity category matches non-fall activities', () {
      expect(matchesHitlCategory(walkItem, 'activity'), isTrue);
      expect(matchesHitlCategory(fallItem, 'activity'), isFalse);
    });
  });

  group('HitlHistoryHeader Widget Tests', () {
    testWidgets('renders active status with badge and responds to switch and clear', (tester) async {
      final coordinator = HitlCoordinator();
      coordinator.setHitlActive(true);
      coordinator.registerDetection(createDetection(label: 'walk'));

      bool? toggledState;
      bool clearedCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HitlHistoryHeader(
              coordinator: coordinator,
              onToggleHitl: (val) => toggledState = val,
              onCleared: () => clearedCalled = true,
            ),
          ),
        ),
      );

      expect(find.text('Mode HITL (Labellisation)'), findsOneWidget);
      expect(find.text('1 détection en attente'), findsOneWidget);
      expect(find.text('Tout effacer'), findsOneWidget);

      // Toggle switch
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(toggledState, isFalse);

      // Clear button
      await tester.tap(find.text('Tout effacer'));
      await tester.pump();
      expect(clearedCalled, isTrue);
      expect(coordinator.items, isEmpty);
    });
  });

  group('HitlHistoryView Widget Tests', () {
    testWidgets('renders empty state when queue is empty', (tester) async {
      final coordinator = HitlCoordinator();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HitlHistoryView(
              coordinator: coordinator,
              selectedCategory: 'all',
            ),
          ),
        ),
      );

      expect(find.text('Mode HITL actif (File vide)'), findsOneWidget);
    });

    testWidgets('renders filter empty message when no items match category', (tester) async {
      final coordinator = HitlCoordinator();
      coordinator.registerDetection(createDetection(label: 'walk'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HitlHistoryView(
              coordinator: coordinator,
              selectedCategory: 'falls',
            ),
          ),
        ),
      );

      expect(find.text('Aucune détection HITL pour ce filtre'), findsOneWidget);
      expect(find.text('1 détection présente dans d\'autres catégories.'), findsOneWidget);
    });

    testWidgets('renders items matching category', (tester) async {
      final coordinator = HitlCoordinator();
      coordinator.registerDetection(createDetection(label: 'walk'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HitlHistoryView(
              coordinator: coordinator,
              selectedCategory: 'all',
            ),
          ),
        ),
      );

      expect(find.text('Détecté : walk (95%)'), findsOneWidget);
    });
  });
}
