import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:healthkicks_mobile/services/background_surveillance_service.dart';
import 'package:healthkicks_mobile/services/ble/ble_connection_manager.dart';
import 'package:healthkicks_mobile/services/theme_service.dart';
import 'package:healthkicks_mobile/ui/screens/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SettingsScreen - UI and Mode Surveillance Active', () {
    testWidgets('Displays Settings AppBar, BLE and Cloud connection controls', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = BackgroundSurveillanceService();
      addTearDown(service.dispose);

      bool scanCalled = false;
      bool disconnectCalled = false;
      bool reconnectMqttCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            surveillanceService: service,
            bleStatus: BleConnectionStatus.ready,
            isMqttConnected: true,
            deviceName: 'HealthKicks-HK-2',
            onStartBleScan: () async => scanCalled = true,
            onDisconnectBle: () async => disconnectCalled = true,
            onReconnectMqtt: () async => reconnectMqttCalled = true,
          ),
        ),
      );

      expect(find.text('Paramètres'), findsOneWidget);
      expect(find.text('PASSERELLE & CONNECTIVITÉ'), findsOneWidget);
      expect(find.text('Bluetooth'), findsOneWidget);
      expect(find.text('Cloud'), findsOneWidget);
      expect(find.text('Re-scanner'), findsOneWidget);
      expect(find.text('Déconnecter'), findsOneWidget);
      expect(find.text('Re-connecter Cloud MQTT'), findsOneWidget);

      await tester.tap(find.text('Re-scanner'));
      expect(scanCalled, isTrue);

      await tester.tap(find.text('Re-connecter Cloud MQTT'));
      expect(reconnectMqttCalled, isTrue);

      await tester.tap(find.text('Déconnecter'));
      expect(disconnectCalled, isTrue);
      await tester.pump();
      // After tapping Déconnecter, button transitions immediately to disconnected state
      expect(find.text('Déconnecter'), findsNothing);
      expect(find.text('Déconnecté'), findsOneWidget);
    });

    testWidgets('Displays Settings AppBar and Mode Surveillance Active tile', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = BackgroundSurveillanceService();
      addTearDown(service.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(surveillanceService: service),
        ),
      );

      expect(find.text('Paramètres'), findsOneWidget);
      expect(
        find.widgetWithText(SwitchListTile, 'Mode Surveillance Active'),
        findsOneWidget,
      );
      expect(
        find.text('Maintient la connexion active écran éteint pour l\'enregistrement et la télémétrie'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(SwitchListTile, 'Alerte de sédentarité'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(SwitchListTile, 'Répéter les alertes'),
        findsOneWidget,
      );
      expect(find.byType(SwitchListTile), findsNWidgets(3));
    });

    testWidgets('Reflects active state when service state changes', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = BackgroundSurveillanceService();
      addTearDown(service.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(surveillanceService: service),
        ),
      );

      final switchTileFinder = find.widgetWithText(SwitchListTile, 'Mode Surveillance Active');
      expect(switchTileFinder, findsOneWidget);

      SwitchListTile switchTile = tester.widget(switchTileFinder);
      expect(switchTile.value, isFalse);

      // Start surveillance
      await service.startSurveillance();
      await tester.pumpAndSettle();

      switchTile = tester.widget(switchTileFinder);
      expect(switchTile.value, isTrue);

      await service.stopSurveillance();
    });

    testWidgets('Displays Sensor Calibration tile and opens modal dialog', (tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = BackgroundSurveillanceService();
      addTearDown(service.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            surveillanceService: service,
            isFootwearConnected: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Calibration de l\'assiette (Zéro gravité)'),
        500,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('CALIBRATION DU CAPTEUR (ASSIETTE)'), findsOneWidget);
      expect(find.text('Calibration de l\'assiette (Zéro gravité)'), findsOneWidget);

      // Tap on calibration tile
      await tester.tap(find.text('Calibration de l\'assiette (Zéro gravité)'));
      await tester.pumpAndSettle();

      expect(find.text('Calibration de l\'Assiette'), findsOneWidget);
      expect(find.textContaining('Chaussure non connectée'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Démarrer'), findsOneWidget);

      // Start button should be disabled when not connected
      final startBtn = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Démarrer'));
      expect(startBtn.onPressed, isNull);

      // Dismiss dialog
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(find.text('Calibration de l\'Assiette'), findsNothing);
    });

    testWidgets('Executes calibration immediately on Start and shows countdown', (tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = BackgroundSurveillanceService();
      addTearDown(service.dispose);

      bool calibrateCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            surveillanceService: service,
            isFootwearConnected: true,
            onCalibrateSensor: () async {
              calibrateCalled = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Calibration de l\'assiette (Zéro gravité)'),
        500,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('CALIBRATION DU CAPTEUR (ASSIETTE)'), findsOneWidget);
      expect(find.text('Calibration de l\'assiette (Zéro gravité)'), findsOneWidget);

      // Tap calibration tile
      await tester.tap(find.text('Calibration de l\'assiette (Zéro gravité)'));
      await tester.pumpAndSettle();

      expect(find.text('Calibration de l\'Assiette'), findsOneWidget);
      expect(find.textContaining('Chaussure non connectée'), findsNothing);

      // Tap start
      await tester.tap(find.widgetWithText(FilledButton, 'Démarrer'));
      await tester.pump();

      expect(calibrateCalled, isTrue);
      expect(find.textContaining('Mesure de l\'assiette en cours'), findsOneWidget);

      // Advance timer through countdown (4 seconds)
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.textContaining('Calibration réussie !'), findsOneWidget);
      expect(find.text('Terminer'), findsOneWidget);

      await tester.tap(find.text('Terminer'));
      await tester.pumpAndSettle();
      expect(find.text('Calibration de l\'Assiette'), findsNothing);
    });

    testWidgets('Displays Inactivity Reminder section with sliders and updates values', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = BackgroundSurveillanceService();
      addTearDown(service.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            surveillanceService: service,
            isFootwearConnected: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('RAPPEL D\'INACTIVITÉ PROLONGÉE'), findsOneWidget);
      expect(find.text('Alerte de sédentarité'), findsOneWidget);
      expect(find.text('Répéter les alertes'), findsOneWidget);
      expect(find.text('50 min'), findsOneWidget);
      expect(find.text('10 min'), findsOneWidget);
      expect(find.byType(Slider), findsNWidgets(2));
      expect(find.text('Synchronisé en direct avec la chaussure'), findsOneWidget);

      // Toggle repeat alerts off
      await tester.tap(find.widgetWithText(SwitchListTile, 'Répéter les alertes'));
      await tester.pumpAndSettle();

      // Cooldown slider should now be hidden
      expect(find.text('Délai de répétition (Cooldown / Snooze)'), findsNothing);
      expect(find.byType(Slider), findsOneWidget); // Only threshold slider remains
    });

    testWidgets('SettingsScreen dynamically updates BLE status badge and buttons in real time when BleConnectionManager changes', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = BackgroundSurveillanceService();
      addTearDown(service.dispose);

      final bleManager = BleConnectionManager();
      addTearDown(bleManager.dispose);

      final mqttNotifier = ValueNotifier<bool>(true);
      addTearDown(mqttNotifier.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            surveillanceService: service,
            bleManager: bleManager,
            isMqttConnectedNotifier: mqttNotifier,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Initial state: Disconnected
      expect(find.text('Déconnecté'), findsOneWidget);
      expect(find.text('Re-scanner'), findsOneWidget);
      expect(find.text('Déconnecter'), findsNothing);

      // 2. Transition to Scanning
      bleManager.updateStatusForTesting(BleConnectionStatus.scanning);
      await tester.pump();
      expect(find.text('Scan en cours...'), findsOneWidget);
      expect(find.text('Déconnecter'), findsNothing);

      // 3. Transition to Connecting
      bleManager.updateStatusForTesting(BleConnectionStatus.connecting);
      await tester.pump();
      expect(find.text('Connexion en cours...'), findsOneWidget);
      expect(find.text('Déconnecter'), findsNothing);

      // 4. Transition to Ready
      bleManager.updateStatusForTesting(BleConnectionStatus.ready);
      await tester.pump();
      expect(find.text('Connecté (MTU: 23)'), findsOneWidget);
      expect(find.text('Déconnecter'), findsOneWidget);

      // 5. Cloud MQTT transition
      mqttNotifier.value = false;
      await tester.pump();

      // 6. Transition back to Disconnected
      bleManager.updateStatusForTesting(BleConnectionStatus.disconnected);
      await tester.pump();
      expect(find.text('Connecté (MTU: 23)'), findsNothing);
      expect(find.text('Déconnecter'), findsNothing);
      expect(find.text('Re-scanner'), findsOneWidget);
    });

    testWidgets('Renders APPARENCE & THÈME category and toggles theme modes', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final surveillance = BackgroundSurveillanceService();
      addTearDown(surveillance.dispose);

      final themeService = ThemeService();
      addTearDown(themeService.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            surveillanceService: surveillance,
            themeService: themeService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('APPARENCE & THÈME'),
        300,
        scrollable: find.byType(Scrollable),
      );
      await tester.pumpAndSettle();

      expect(find.text('APPARENCE & THÈME'), findsOneWidget);
      expect(find.text('Thème de l\'application'), findsOneWidget);
      expect(find.text('Système'), findsOneWidget);
      expect(find.text('Clair'), findsOneWidget);
      expect(find.text('Sombre'), findsOneWidget);

      // Tap on Light theme
      await tester.tap(find.text('Clair'));
      await tester.pumpAndSettle();
      expect(themeService.currentMode, equals(AppThemeMode.light));

      // Tap on Dark theme
      await tester.tap(find.text('Sombre'));
      await tester.pumpAndSettle();
      expect(themeService.currentMode, equals(AppThemeMode.dark));

      // Tap on System theme
      await tester.tap(find.text('Système'));
      await tester.pumpAndSettle();
      expect(themeService.currentMode, equals(AppThemeMode.system));
    });

    testWidgets('Shows calibration button when disconnected device reconnects', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final service = BackgroundSurveillanceService();
      addTearDown(service.dispose);

      final bleManager = BleConnectionManager();
      addTearDown(bleManager.dispose);

      bool calibrated = false;

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsScreen(
            surveillanceService: service,
            bleManager: bleManager,
            bleStatus: BleConnectionStatus.disconnected,
            onCalibrateSensor: () async {
              calibrated = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially disconnected: calibration button should not be present in Bluetooth card
      expect(find.text("Étalonner l'assiette du capteur (4s)"), findsNothing);

      // Reconnect via bleManager
      bleManager.updateStatusForTesting(BleConnectionStatus.ready);
      await tester.pumpAndSettle();

      // Now connected: calibration button appears
      expect(find.text("Étalonner l'assiette du capteur (4s)"), findsOneWidget);

      await tester.tap(find.text("Étalonner l'assiette du capteur (4s)"));
      expect(calibrated, isTrue);
    });
  });
}
