import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:healthkicks_mobile/main.dart';
import 'package:healthkicks_mobile/services/auth/auth_service.dart';
import 'package:healthkicks_mobile/services/auth/token_storage_service.dart';
import 'package:healthkicks_mobile/ui/widgets/studio_session_dialog.dart';
import '../../services/auth/token_storage_service_test.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Studio Session Dialog Widget Tests', () {
    testWidgets('renders all activities and fixed 5s duration indicator', (WidgetTester tester) async {
      String? triggeredLabel;
      double? triggeredDuration;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioSessionDialog(
              onStartSession: ({required String label, required double durationSec}) async {
                triggeredLabel = label;
                triggeredDuration = durationSec;
              },
            ),
          ),
        ),
      );

      expect(find.text('Enregistrement Studio'), findsOneWidget);
      expect(find.text("Type d'activité"), findsOneWidget);
      expect(find.text('Durée : 5 secondes'), findsOneWidget);
      expect(find.text("Démarrer l'enregistrement"), findsOneWidget);

      // Confirm with defaults (walk, 5.0)
      await tester.tap(find.text("Démarrer l'enregistrement"));
      await tester.pumpAndSettle();

      expect(triggeredLabel, 'walk');
      expect(triggeredDuration, 5.0);
    });

    testWidgets('allows selecting custom activity tag with 5s duration', (WidgetTester tester) async {
      String? triggeredLabel;
      double? triggeredDuration;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StudioSessionDialog(
              onStartSession: ({required String label, required double durationSec}) async {
                triggeredLabel = label;
                triggeredDuration = durationSec;
              },
            ),
          ),
        ),
      );

      // Open dropdown and select 'custom'
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Autre / Personnalisé 🏷️').last);
      await tester.pumpAndSettle();

      // Enter custom tag
      expect(find.byType(TextField), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'sprint_incline');
      await tester.pumpAndSettle();

      // Confirm
      await tester.tap(find.text("Démarrer l'enregistrement"));
      await tester.pumpAndSettle();

      expect(triggeredLabel, 'sprint_incline');
      expect(triggeredDuration, 5.0);
    });
  });

  group('GatewayDashboardScreen Role-based Studio Visibility', () {
    AuthService createAuthServiceWithRole(String role) {
      final fakeStorage = FakeFlutterSecureStorage();
      fakeStorage.write(key: 'hk_access_token', value: 'valid_mock_token');
      final tokenStorage = TokenStorageService(storage: fakeStorage);

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/auth/me') {
          return http.Response(
            jsonEncode({
              'id': 1,
              'email': 'user@example.com',
              'name': 'User Test',
              'role': role,
              'is_active': true,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      return AuthService(
        backendBaseUrl: 'http://127.0.0.1:8000',
        tokenStorage: tokenStorage,
        httpClient: mockClient,
      );
    }

    testWidgets('Studio button is HIDDEN when role is "user"', (WidgetTester tester) async {
      final authService = createAuthServiceWithRole('user');

      await tester.pumpWidget(HealthKicksApp(authService: authService));
      await tester.pumpAndSettle();

      expect(find.text('Test Haptique'), findsOneWidget);
      expect(find.text('Studio'), findsNothing);
    });

    testWidgets('Studio button is VISIBLE when role is "clinician"', (WidgetTester tester) async {
      final authService = createAuthServiceWithRole('clinician');

      await tester.pumpWidget(HealthKicksApp(authService: authService));
      await tester.pumpAndSettle();

      expect(find.text('Test Haptique'), findsOneWidget);
      expect(find.text('Studio'), findsOneWidget);

      // Tap Studio button to open dialog
      await tester.tap(find.text('Studio'));
      await tester.pumpAndSettle();

      expect(find.text('Enregistrement Studio'), findsOneWidget);
      expect(find.text("Démarrer l'enregistrement"), findsOneWidget);
    });

    testWidgets('Studio button is VISIBLE when role is "admin"', (WidgetTester tester) async {
      final authService = createAuthServiceWithRole('admin');

      await tester.pumpWidget(HealthKicksApp(authService: authService));
      await tester.pumpAndSettle();

      expect(find.text('Test Haptique'), findsOneWidget);
      expect(find.text('Studio'), findsOneWidget);
    });
  });
}
