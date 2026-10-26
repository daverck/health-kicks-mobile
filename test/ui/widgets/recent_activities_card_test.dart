import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/models/activity_detection_model.dart';
import 'package:healthkicks_mobile/models/hitl/hitl_detection_item.dart';
import 'package:healthkicks_mobile/ui/widgets/recent_activities_card.dart';

void main() {
  testWidgets('RecentActivitiesCard renders empty state correctly', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RecentActivitiesCard(activities: []),
        ),
      ),
    );

    expect(find.text('Activités récentes'), findsOneWidget);
    expect(find.text('En attente de détections...'), findsOneWidget);
    expect(find.byIcon(Icons.history_toggle_off_rounded), findsOneWidget);
  });

  testWidgets('RecentActivitiesCard renders list of activities and handles view all callback', (tester) async {
    bool viewAllTapped = false;
    final activities = [
      const ActivityDetectionModel(
        stateCode: 0x01,
        eventType: 'walk',
        confidencePercent: 95,
        timestampEpochSec: 1726999200,
        isFall: false,
        isHapticTriggered: false,
      ),
      const ActivityDetectionModel(
        stateCode: 0x1F,
        eventType: 'fall_generic',
        confidencePercent: 99,
        timestampEpochSec: 1726999230,
        isFall: true,
        isHapticTriggered: true,
      ),
      const ActivityDetectionModel(
        stateCode: 0x10,
        eventType: 'fall_forward',
        confidencePercent: 92,
        timestampEpochSec: 1726999245,
        isFall: true,
        isHapticTriggered: true,
      ),
      const ActivityDetectionModel(
        stateCode: 0x1E,
        eventType: 'fall_recovery',
        confidencePercent: 88,
        timestampEpochSec: 1726999250,
        isFall: false,
        isHapticTriggered: false,
      ),
      const ActivityDetectionModel(
        stateCode: 0x20,
        eventType: 'inactivity_alert',
        confidencePercent: 100,
        timestampEpochSec: 1726999260,
        isFall: false,
        isHapticTriggered: true,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecentActivitiesCard(
            activities: activities,
            onViewAll: () => viewAllTapped = true,
          ),
        ),
      ),
    );

    expect(find.text('Activités récentes'), findsOneWidget);
    expect(find.text('Voir tout'), findsOneWidget);
    expect(find.text('Marche'), findsOneWidget);
    expect(find.text('95% conf.'), findsOneWidget);
    expect(find.text('Chute'), findsOneWidget);
    expect(find.text('Chute avant'), findsOneWidget);
    expect(find.text('Chute relevée'), findsOneWidget);
    expect(find.text('CHUTE'), findsNWidgets(2));
    expect(find.text('99% conf.'), findsOneWidget);
    expect(find.text('Rappel inactivité'), findsOneWidget);

    await tester.tap(find.text('Voir tout'));
    await tester.pump();
    expect(viewAllTapped, isTrue);
  });

  testWidgets('RecentActivitiesCard renders stairs_up, stairs_down and calibration correctly', (tester) async {
    final activities = [
      const ActivityDetectionModel(
        stateCode: 0x03,
        eventType: 'stairs_up',
        confidencePercent: 91,
        timestampEpochSec: 1726999300,
        isFall: false,
        isHapticTriggered: false,
      ),
      const ActivityDetectionModel(
        stateCode: 0x04,
        eventType: 'stairs_down',
        confidencePercent: 89,
        timestampEpochSec: 1726999310,
        isFall: false,
        isHapticTriggered: false,
      ),
      const ActivityDetectionModel(
        stateCode: 0xFD,
        eventType: 'calibration',
        confidencePercent: 100,
        timestampEpochSec: 1726999320,
        isFall: false,
        isHapticTriggered: false,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecentActivitiesCard(activities: activities),
        ),
      ),
    );

    expect(find.text('Escaliers (Montée)'), findsOneWidget);
    expect(find.text('Escaliers (Descente)'), findsOneWidget);
    expect(find.text('Calibration des capteurs'), findsOneWidget);
    expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
  });

  testWidgets('RecentActivitiesCard displays HITL toggle when canUseHitl is true and handles toggle', (tester) async {
    bool toggled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecentActivitiesCard(
            activities: const [],
            canUseHitl: true,
            isHitlActive: false,
            onToggleHitl: (val) => toggled = val,
          ),
        ),
      ),
    );

    expect(find.text('Mode HITL (Labellisation)'), findsOneWidget);
    final switchFinder = find.byType(Switch);
    expect(switchFinder, findsOneWidget);

    await tester.tap(switchFinder);
    await tester.pump();
    expect(toggled, isTrue);
  });

  testWidgets('RecentActivitiesCard displays HITL items with label selector and confirm button', (tester) async {
    final detection = const ActivityDetectionModel(
      stateCode: 0x01,
      eventType: 'walk',
      confidencePercent: 90,
      timestampEpochSec: 1729800000,
      isFall: false,
      isHapticTriggered: false,
    );

    final item = HitlDetectionItem(
      id: 'test-hitl-1',
      timestamp: DateTime(2026, 10, 24, 14, 30, 0),
      detectedLabel: 'walk',
      confidencePercent: 90,
      isFall: false,
      rawDetection: detection,
      isBurstReady: true,
    );

    HitlDetectionItem? confirmedItem;
    HitlDetectionItem? dismissedItem;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RecentActivitiesCard(
              activities: const [],
              canUseHitl: true,
              isHitlActive: true,
              hitlItems: [item],
              onConfirmHitl: (i) => confirmedItem = i,
              onDismissHitl: (i) => dismissedItem = i,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Détecté : walk (90%)'), findsOneWidget);
    expect(find.text('Valider & Envoyer'), findsOneWidget);

    await tester.tap(find.text('Valider & Envoyer'));
    await tester.pump();
    expect(confirmedItem, equals(item));

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(dismissedItem, equals(item));
  });

  testWidgets('RecentActivitiesCard handles clear all HITL items callback', (tester) async {
    const detection = ActivityDetectionModel(
      stateCode: 0x01,
      eventType: 'walk',
      confidencePercent: 90,
      timestampEpochSec: 1726999200,
      isFall: false,
      isHapticTriggered: false,
    );

    final item = HitlDetectionItem(
      id: 'test-hitl-1',
      timestamp: DateTime(2026, 10, 24, 14, 30, 0),
      detectedLabel: 'walk',
      confidencePercent: 90,
      isFall: false,
      rawDetection: detection,
      isBurstReady: true,
    );

    bool clearAllCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RecentActivitiesCard(
              activities: const [],
              canUseHitl: true,
              isHitlActive: true,
              hitlItems: [item],
              onClearHitl: () => clearAllCalled = true,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Tout effacer'), findsOneWidget);
    await tester.tap(find.text('Tout effacer'));
    await tester.pump();
    expect(clearAllCalled, isTrue);
  });

  testWidgets('RecentActivitiesCard highlights selected card on tap', (tester) async {
    const activities = [
      ActivityDetectionModel(
        stateCode: 0x01,
        eventType: 'walk',
        confidencePercent: 95,
        timestampEpochSec: 1726999200,
        isFall: false,
        isHapticTriggered: false,
      ),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RecentActivitiesCard(
            activities: activities,
          ),
        ),
      ),
    );

    expect(find.text('Actif'), findsNothing);

    // Tap card
    await tester.tap(find.text('Marche'));
    await tester.pump();

    // Now highlighted with 'Actif' badge
    expect(find.text('Actif'), findsOneWidget);
  });

  testWidgets('RecentActivitiesCard highlights HITL card when opening label dropdown select', (tester) async {
    const detection = ActivityDetectionModel(
      stateCode: 0x01,
      eventType: 'walk',
      confidencePercent: 90,
      timestampEpochSec: 1726999200,
      isFall: false,
      isHapticTriggered: false,
    );

    final item = HitlDetectionItem(
      id: 'test-hitl-select-1',
      timestamp: DateTime(2026, 10, 24, 14, 30, 0),
      detectedLabel: 'walk',
      confidencePercent: 90,
      isFall: false,
      rawDetection: detection,
      isBurstReady: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecentActivitiesCard(
            activities: const [],
            canUseHitl: true,
            isHitlActive: true,
            hitlItems: [item],
          ),
        ),
      ),
    );

    expect(find.text('Actif'), findsNothing);

    // Tap dropdown button
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pump();

    // Now highlighted with 'Actif' badge
    expect(find.text('Actif'), findsOneWidget);
  });
}



