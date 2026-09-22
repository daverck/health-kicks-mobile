import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/models/log_entry_model.dart';
import 'package:healthkicks_mobile/ui/screens/event_logs_screen.dart';

void main() {
  testWidgets('EventLogsScreen renders logs and allows filtering', (tester) async {
    final logs = [
      LogEntry(
        timestamp: DateTime(2026, 9, 22, 10, 30, 0),
        tag: 'BLE',
        message: 'GATT services discovered',
        color: Colors.blue,
      ),
      LogEntry(
        timestamp: DateTime(2026, 9, 22, 10, 30, 5),
        tag: 'MQTT',
        message: 'Connected to AWS IoT Core',
        color: Colors.teal,
      ),
      LogEntry(
        timestamp: DateTime(2026, 9, 22, 10, 30, 10),
        tag: 'ACTIVITY',
        message: 'WALK (95%)',
        color: Colors.orange,
      ),
    ];

    bool cleared = false;

    await tester.pumpWidget(
      MaterialApp(
        home: EventLogsScreen(
          logs: logs,
          onClearLogs: () => cleared = true,
        ),
      ),
    );

    expect(find.text('Journal d\'événements'), findsOneWidget);
    expect(find.text('GATT services discovered'), findsOneWidget);
    expect(find.text('Connected to AWS IoT Core'), findsOneWidget);
    expect(find.text('WALK (95%)'), findsOneWidget);
    expect(find.text('Total : 3 / 3 événements'), findsOneWidget);

    // Filter by tag
    await tester.tap(find.widgetWithText(FilterChip, 'MQTT'));
    await tester.pumpAndSettle();

    expect(find.text('Connected to AWS IoT Core'), findsOneWidget);
    expect(find.text('GATT services discovered'), findsNothing);
    expect(find.text('Total : 1 / 3 événements'), findsOneWidget);

    // Search query
    await tester.tap(find.widgetWithText(FilterChip, 'ALL'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'services');
    await tester.pumpAndSettle();

    expect(find.text('GATT services discovered'), findsOneWidget);
    expect(find.text('Connected to AWS IoT Core'), findsNothing);

    // Clear logs modal
    await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Effacer les logs'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Effacer'));
    await tester.pumpAndSettle();
    expect(cleared, isTrue);
  });
}
