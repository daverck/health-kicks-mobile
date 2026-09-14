import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:healthkicks_mobile/main.dart';
import 'package:healthkicks_mobile/services/auth/auth_service.dart';
import 'package:healthkicks_mobile/services/auth/token_storage_service.dart';
import 'services/auth/token_storage_service_test.dart';

void main() {
  testWidgets('HealthKicksApp affiche LoginScreen si aucun token en local sans champ d\'URL backend', (WidgetTester tester) async {
    final fakeStorage = FakeFlutterSecureStorage();
    final tokenStorage = TokenStorageService(storage: fakeStorage);
    final authService = AuthService(
      backendBaseUrl: 'http://127.0.0.1:8000',
      tokenStorage: tokenStorage,
    );

    await tester.pumpWidget(HealthKicksApp(authService: authService));
    await tester.pumpAndSettle();

    expect(find.text('HealthKicks'), findsOneWidget);
    expect(find.text('Continuer avec Google'), findsOneWidget);
    expect(find.text('Continuer avec Microsoft / Azure'), findsOneWidget);
    expect(find.text('Se connecter'), findsNothing);
    expect(find.byIcon(Icons.settings), findsNothing);
    expect(find.textContaining('Serveur Backend'), findsNothing);
  });

  testWidgets('HealthKicksApp affiche GatewayDashboardScreen si token authentifié', (WidgetTester tester) async {
    final fakeStorage = FakeFlutterSecureStorage();
    await fakeStorage.write(key: 'hk_access_token', value: 'valid_mock_token');
    final tokenStorage = TokenStorageService(storage: fakeStorage);

    final mockClient = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/me') {
        return http.Response(
          jsonEncode({
            'id': 1,
            'email': 'user@example.com',
            'name': 'User Test',
            'role': 'user',
            'is_active': true,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('Not Found', 404);
    });

    final authService = AuthService(
      backendBaseUrl: 'http://127.0.0.1:8000',
      tokenStorage: tokenStorage,
      httpClient: mockClient,
    );

    await tester.pumpWidget(HealthKicksApp(authService: authService));
    await tester.pumpAndSettle();

    expect(find.text('HealthKicks BLE-to-MQTT Gateway'), findsOneWidget);
  });
}
