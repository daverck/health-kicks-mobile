import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/models/activity_detection_model.dart';
import 'package:healthkicks_mobile/models/hitl/hitl_detection_item.dart';
import 'package:healthkicks_mobile/ui/widgets/events/hitl_card_action_row.dart';

void main() {
  HitlDetectionItem createItem({
    bool isBurstReady = false,
    bool isPublishing = false,
    bool isSynchronized = false,
    String label = 'walk',
  }) {
    return HitlDetectionItem(
      id: 'test_item_1',
      timestamp: DateTime.now(),
      detectedLabel: label,
      confidencePercent: 92,
      isFall: false,
      isBurstReady: isBurstReady,
      isPublishing: isPublishing,
      isSynchronized: isSynchronized,
      rawDetection: const ActivityDetectionModel(
        stateCode: 0x02,
        eventType: 'walk',
        confidencePercent: 92,
        timestampEpochSec: 1000,
        isFall: false,
        isHapticTriggered: false,
      ),
    );
  }

  Widget buildTestWidget({
    required HitlDetectionItem item,
    VoidCallback? onTap,
    void Function(HitlDetectionItem, String)? onUpdateLabel,
    void Function(HitlDetectionItem)? onConfirm,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: HitlCardActionRow(
          item: item,
          availableLabels: const ['walk', 'run', 'idle'],
          onTap: onTap,
          onUpdateLabel: onUpdateLabel,
          onConfirm: onConfirm,
        ),
      ),
    );
  }

  group('HitlCardActionRow Widget Tests', () {
    testWidgets('displays "Capture 4s..." when burst is not yet ready', (tester) async {
      final item = createItem(isBurstReady: false);
      await tester.pumpWidget(buildTestWidget(item: item));

      expect(find.text('Capture 4s...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('displays "Valider & Envoyer" when burst is ready, triggers onConfirm', (tester) async {
      final item = createItem(isBurstReady: true);
      HitlDetectionItem? confirmedItem;

      await tester.pumpWidget(
        buildTestWidget(
          item: item,
          onConfirm: (it) => confirmedItem = it,
        ),
      );

      final button = find.widgetWithText(FilledButton, 'Valider & Envoyer');
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pump();

      expect(confirmedItem, isNotNull);
      expect(confirmedItem!.id, equals('test_item_1'));
    });

    testWidgets('displays "Synchronisé" badge when item is synchronized', (tester) async {
      final item = createItem(isSynchronized: true);
      await tester.pumpWidget(buildTestWidget(item: item));

      expect(find.text('Synchronisé'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_done_rounded), findsOneWidget);
    });

    testWidgets('displays progress indicator when publishing', (tester) async {
      final item = createItem(isPublishing: true);
      await tester.pumpWidget(buildTestWidget(item: item));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('selecting a new label triggers onUpdateLabel callback', (tester) async {
      final item = createItem(isBurstReady: true);
      String? selectedLabel;

      await tester.pumpWidget(
        buildTestWidget(
          item: item,
          onUpdateLabel: (it, newLabel) => selectedLabel = newLabel,
        ),
      );

      // Open PopupMenuButton
      final dropdownFinder = find.byKey(ValueKey('hitl_label_dropdown_${item.id}'));
      expect(dropdownFinder, findsOneWidget);

      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();

      // Tap 'run' option
      final runOptionFinder = find.text('run').last;
      await tester.tap(runOptionFinder);
      await tester.pumpAndSettle();

      expect(selectedLabel, equals('run'));
    });
  });
}
