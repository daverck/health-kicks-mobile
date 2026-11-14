import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/models/log_entry_model.dart';
import 'package:healthkicks_mobile/ui/widgets/log_export_dialog.dart';

void main() {
  group('LogExportDialog Widget Tests', () {
    final sampleLogs = [
      LogEntry(
        timestamp: DateTime(2026, 11, 9, 10, 0, 0),
        tag: 'BLE',
        message: 'Connected to HK-2',
      ),
      LogEntry(
        timestamp: DateTime(2026, 11, 9, 10, 0, 5),
        tag: 'ACTIVITY',
        message: 'Detected walk step',
      ),
    ];

    testWidgets('renders dialog elements, log count and preview', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (_) => LogExportDialog(
                      logs: sampleLogs,
                      deviceId: 'HK-TEST',
                      deviceName: 'Test Shoe',
                      bleStatus: 'connected',
                      mtu: 247,
                      mqttConnected: true,
                    ),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Export du Journal'), findsOneWidget);
      expect(find.text('Envoyer les 2 événements par email.'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Copier'), findsOneWidget);
      expect(find.text('Envoyer'), findsOneWidget);
      expect(find.textContaining('Connected to HK-2'), findsOneWidget);
    });

    testWidgets('copy button triggers clipboard copy and closes dialog', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (_) => LogExportDialog(
                      logs: sampleLogs,
                      deviceId: 'HK-TEST',
                    ),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.byType(LogExportDialog), findsOneWidget);

      await tester.tap(find.text('Copier'));
      await tester.pumpAndSettle();

      expect(find.byType(LogExportDialog), findsNothing);
    });

    testWidgets('send button handles custom recipient and closes dialog', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (_) => LogExportDialog(
                      logs: sampleLogs,
                      deviceId: 'HK-TEST',
                    ),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'test@healthkicks.com');
      await tester.pump();

      await tester.tap(find.text('Envoyer'));
      await tester.pumpAndSettle();

      expect(find.byType(LogExportDialog), findsNothing);
    });
  });
}
