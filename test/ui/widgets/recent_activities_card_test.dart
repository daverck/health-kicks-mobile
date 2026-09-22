import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/models/activity_detection_model.dart';
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
    expect(find.text('CHUTE'), findsOneWidget);
    expect(find.text('99% conf.'), findsOneWidget);
    expect(find.text('Rappel inactivité'), findsOneWidget);

    await tester.tap(find.text('Voir tout'));
    await tester.pump();
    expect(viewAllTapped, isTrue);
  });
}
