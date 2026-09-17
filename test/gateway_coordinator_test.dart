import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/models/activity_detection_model.dart';
import 'package:healthkicks_mobile/models/haptic_command_model.dart';
import 'package:healthkicks_mobile/models/imu_reading_model.dart';
import 'package:healthkicks_mobile/models/studio_command_model.dart';
import 'package:healthkicks_mobile/models/studio_session_model.dart';
import 'package:healthkicks_mobile/services/ble/ble_footwear_client.dart';
import 'package:healthkicks_mobile/services/ble/burst_reassembler.dart';
import 'package:healthkicks_mobile/services/gateway_coordinator.dart';
import 'package:healthkicks_mobile/services/mqtt/mqtt_gateway_service.dart';
import 'package:healthkicks_mobile/services/studio/studio_api_service.dart';

class FakeBleFootwearClient implements BleFootwearClient {
  final _activityCtrl = StreamController<ActivityDetectionModel>.broadcast();
  final _statusCtrl = StreamController<String>.broadcast();
  final _burstCtrl = StreamController<BurstReassemblyResult>.broadcast();

  final List<HapticCommandModel> sentHapticCommands = [];
  String? lastStartedStudioSessionId;
  int startStudioSessionCallCount = 0;

  @override
  Stream<ActivityDetectionModel> get activityStream => _activityCtrl.stream;

  @override
  Stream<String> get studioStatusStream => _statusCtrl.stream;

  @override
  Stream<BurstReassemblyResult> get burstResultStream => _burstCtrl.stream;

  void emitActivity(ActivityDetectionModel model) => _activityCtrl.add(model);
  void emitBurst(BurstReassemblyResult result) => _burstCtrl.add(result);

  @override
  Future<void> sendHapticCommand(HapticCommandModel command) async {
    sentHapticCommands.add(command);
  }

  @override
  Future<void> startStudioSession({
    required String label,
    required double durationSec,
    required String sessionId,
  }) async {
    lastStartedStudioSessionId = sessionId;
    startStudioSessionCallCount++;
  }

  @override
  Future<void> cancelStudioSession() async {}

  @override
  Future<void> initializeServices() async {}

  @override
  void dispose() {
    _activityCtrl.close();
    _statusCtrl.close();
    _burstCtrl.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMqttGatewayService implements MqttGatewayService {
  final _hapticCtrl = StreamController<HapticCommandModel>.broadcast();
  final _studioCommandCtrl = StreamController<StudioCommandModel>.broadcast();

  final List<ActivityDetectionModel> publishedDetections = [];
  final List<StudioSessionModel> publishedStudioSessions = [];

  @override
  bool get isConnected => true;

  @override
  Stream<HapticCommandModel> get hapticCommandStream => _hapticCtrl.stream;

  @override
  Stream<StudioCommandModel> get studioCommandStream => _studioCommandCtrl.stream;

  void emitHapticCommand(HapticCommandModel cmd) => _hapticCtrl.add(cmd);
  void emitStudioCommand(StudioCommandModel cmd) => _studioCommandCtrl.add(cmd);

  @override
  Future<void> publishActivityDetection(ActivityDetectionModel detection) async {
    publishedDetections.add(detection);
  }

  @override
  Future<void> publishStudioSession(StudioSessionModel session) async {
    publishedStudioSessions.add(session);
  }

  final List<bool> publishedGatewayStatuses = [];

  @override
  Future<void> publishGatewayStatus({required bool online}) async {
    publishedGatewayStatuses.add(online);
  }

  @override
  Future<bool> connect({MqttLogCallback? onLog}) async => true;

  @override
  void disconnect() {
    _hapticCtrl.close();
    _studioCommandCtrl.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeStudioApiService implements StudioApiService {
  final List<Map<String, dynamic>> startedSessions = [];
  String nextSessionId = '77777777-8888-9999-aaaa-bbbbbbbbbbbb';

  @override
  Future<StudioStartResponse> startStudioSession({
    required String deviceId,
    required String label,
    double durationSec = 5.0,
    int? pulseCount,
    int? pulseDurationMs,
    int? pulsePauseMs,
    int? pulseIntensity,
  }) async {
    startedSessions.add({
      'device_id': deviceId,
      'label': label,
      'duration_sec': durationSec,
    });
    return StudioStartResponse(
      status: 'command_dispatched',
      deviceId: deviceId,
      sessionId: nextSessionId,
      label: label,
      durationSec: durationSec,
      topic: 'healthkicks/v1/$deviceId/commands/studio',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('GatewayCoordinator - Routage bidirectionnel BLE <-> MQTT & Synchronisation REST Studio', () {
    late FakeBleFootwearClient fakeBle;
    late FakeMqttGatewayService fakeMqtt;
    late FakeStudioApiService fakeStudioApi;
    late GatewayCoordinator coordinator;

    setUp(() {
      fakeBle = FakeBleFootwearClient();
      fakeMqtt = FakeMqttGatewayService();
      fakeStudioApi = FakeStudioApiService();
      coordinator = GatewayCoordinator(
        bleClient: fakeBle,
        mqttService: fakeMqtt,
        studioApiService: fakeStudioApi,
        deviceId: 'HK-SHOE-TEST-001',
      );
      coordinator.startRouting();
    });

    tearDown(() {
      coordinator.stopRouting();
      fakeBle.dispose();
      fakeMqtt.disconnect();
    });

    test('Relais montant : Détection d\'activité BLE transmise à MQTT', () async {
      const detection = ActivityDetectionModel(
        stateCode: 0x02,
        eventType: 'run',
        confidencePercent: 92,
        timestampEpochSec: 1718000000,
        isFall: false,
        isHapticTriggered: false,
      );

      fakeBle.emitActivity(detection);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fakeMqtt.publishedDetections.length, equals(1));
      expect(fakeMqtt.publishedDetections.first.eventType, equals('run'));
      expect(fakeMqtt.publishedDetections.first.confidencePercent, equals(92));
    });

    test('Relais descendant : Commande haptique MQTT répercutée en BLE', () async {
      const command = HapticCommandModel(
        commandId: 'cmd-haptic-test',
        patternId: 1,
        intensity: 80,
        durationMs: 300,
      );

      fakeMqtt.emitHapticCommand(command);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fakeBle.sentHapticCommands.length, equals(1));
      expect(fakeBle.sentHapticCommands.first.patternId, equals(1));
      expect(fakeBle.sentHapticCommands.first.intensity, equals(80));
      expect(fakeBle.sentHapticCommands.first.durationMs, equals(300));
    });

    test('Relais Studio Burst : Réserve la session en REST (/commands/studio/start) puis publie en MQTT avec le même UUID', () async {
      StudioSessionModel? savedNotifiedSession;
      final sub = coordinator.studioSessionSavedStream.listen((sess) {
        savedNotifiedSession = sess;
      });

      fakeStudioApi.nextSessionId = '88888888-9999-aaaa-bbbb-cccccccccccc';

      // 1. Déclenchement : appel REST backend automatique pour réserver la session
      await coordinator.triggerStudioSession(
        label: 'course_fractionne',
        durationSec: 30.0,
      );

      // Validation que le backend a été sollicité dès l'ordre START
      expect(fakeStudioApi.startedSessions.length, equals(1));
      expect(fakeStudioApi.startedSessions.first['device_id'], equals('HK-SHOE-TEST-001'));
      expect(fakeStudioApi.startedSessions.first['label'], equals('course_fractionne'));
      expect(fakeStudioApi.startedSessions.first['duration_sec'], equals(30.0));

      // Validation que le sessionId retourné par l'API REST a été envoyé à la chaussure
      expect(fakeBle.lastStartedStudioSessionId, equals('88888888-9999-aaaa-bbbb-cccccccccccc'));

      // 2. Réception du flux Burst BLE
      final frames = [
        const ImuReadingModel(deltaMs: 0, ax: 0.1, ay: 0.9, az: -0.2, gx: 10, gy: -5, gz: 0),
        const ImuReadingModel(deltaMs: 20, ax: 0.12, ay: 0.88, az: -0.19, gx: 12, gy: -4, gz: 1),
      ];

      final burstResult = BurstReassemblyResult(
        isCompleted: true,
        isCrcValid: true,
        totalAnnounced: 2,
        framesRecovered: 2,
        readings: frames,
      );

      fakeBle.emitBurst(burstResult);
      await Future<void>.delayed(const Duration(milliseconds: 15));

      // 3. Validation publication MQTT avec l'UUID officiel réservé
      expect(fakeMqtt.publishedStudioSessions.length, equals(1));
      final publishedSession = fakeMqtt.publishedStudioSessions.first;
      expect(publishedSession.sessionId, equals('88888888-9999-aaaa-bbbb-cccccccccccc'));
      expect(publishedSession.label, equals('course_fractionne'));
      expect(publishedSession.deviceId, equals('HK-SHOE-TEST-001'));
      expect(publishedSession.readings.length, equals(2));

      // 4. Validation Stream UI Toast / SnackBar
      expect(savedNotifiedSession, isNotNull);
      expect(savedNotifiedSession!.sessionId, equals('88888888-9999-aaaa-bbbb-cccccccccccc'));

      await sub.cancel();
    });

    test('Commande Studio distante MQTT : Déclenche la capture BLE avec le session_id officiel sans appel REST', () async {
      StudioSessionModel? savedNotifiedSession;
      final sub = coordinator.studioSessionSavedStream.listen((sess) {
        savedNotifiedSession = sess;
      });

      const remoteCmd = StudioCommandModel(
        sessionId: '99999999-aaaa-bbbb-cccc-dddddddddddd',
        label: 'test_web_remote',
        durationSec: 5.0,
      );

      // 1. Réception de la commande Studio distante via MQTT (Web -> AWS IoT Core -> Mobile)
      fakeMqtt.emitStudioCommand(remoteCmd);
      await Future<void>.delayed(const Duration(milliseconds: 15));

      // Vérification qu'AUCUN appel REST n'a été fait (la session étant déjà persistée par le backend)
      expect(fakeStudioApi.startedSessions.isEmpty, isTrue);

      // Vérification que l'ordre START BLE a été envoyé avec le sessionId officiel reçu du backend
      expect(fakeBle.lastStartedStudioSessionId, equals('99999999-aaaa-bbbb-cccc-dddddddddddd'));

      // 2. Réception du flux Burst BLE
      final frames = [
        const ImuReadingModel(deltaMs: 0, ax: 0.2, ay: 0.8, az: -0.1, gx: 5, gy: -2, gz: 3),
      ];

      final burstResult = BurstReassemblyResult(
        isCompleted: true,
        isCrcValid: true,
        totalAnnounced: 1,
        framesRecovered: 1,
        readings: frames,
      );

      fakeBle.emitBurst(burstResult);
      await Future<void>.delayed(const Duration(milliseconds: 15));

      // 3. Validation de la publication MQTT avec le même UUID reçu dans la commande
      expect(fakeMqtt.publishedStudioSessions.length, equals(1));
      final published = fakeMqtt.publishedStudioSessions.first;
      expect(published.sessionId, equals('99999999-aaaa-bbbb-cccc-dddddddddddd'));
      expect(published.label, equals('test_web_remote'));
      expect(published.deviceId, equals('HK-SHOE-TEST-001'));
      expect(published.readings.length, equals(1));

      // 4. Notification UI
      expect(savedNotifiedSession, isNotNull);
      expect(savedNotifiedSession!.sessionId, equals('99999999-aaaa-bbbb-cccc-dddddddddddd'));

      await sub.cancel();
    });

    test('triggerStudioSession génère un UUID v4 valide si aucun service REST n\'est configuré', () async {
      final standaloneCoordinator = GatewayCoordinator(
        bleClient: fakeBle,
        mqttService: fakeMqtt,
        deviceId: 'HK-SHOE-TEST-001',
      );
      standaloneCoordinator.startRouting();

      await standaloneCoordinator.triggerStudioSession(
        label: 'auto_uuid_test',
        durationSec: 5.0,
      );

      expect(fakeBle.lastStartedStudioSessionId, isNotNull);
      final uuidRegex = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      );
      expect(uuidRegex.hasMatch(fakeBle.lastStartedStudioSessionId!), isTrue);

      standaloneCoordinator.stopRouting();
    });

    test('Relais Studio Burst : Transmet les trames même si CRC32 présente une anomalie pour éviter la perte de données', () async {
      final List<String> logs = [];
      final testBle = FakeBleFootwearClient();
      final testMqtt = FakeMqttGatewayService();
      final loggedCoordinator = GatewayCoordinator(
        bleClient: testBle,
        mqttService: testMqtt,
        deviceId: 'HK-SHOE-TEST-001',
        onLog: (msg, {bool isError = false}) => logs.add(msg),
      );
      loggedCoordinator.startRouting();

      final frames = [
        const ImuReadingModel(deltaMs: 0, ax: 0.1, ay: 0.9, az: -0.2, gx: 10, gy: -5, gz: 0),
      ];

      // Burst complété avec CRC invalide
      final burstResult = BurstReassemblyResult(
        isCompleted: true,
        isCrcValid: false,
        totalAnnounced: 2,
        framesRecovered: 1,
        readings: frames,
      );

      testBle.emitBurst(burstResult);
      await Future<void>.delayed(const Duration(milliseconds: 15));

      expect(testMqtt.publishedStudioSessions.length, equals(1));
      expect(logs.any((l) => l.contains('CRC32 non concordant')), isTrue);

      loggedCoordinator.stopRouting();
      testBle.dispose();
      testMqtt.disconnect();
    });

    test('Relais Studio Burst : Ignore la publication si le burst ne contient aucun échantillon IMU', () async {
      final List<String> logs = [];
      final testBle = FakeBleFootwearClient();
      final testMqtt = FakeMqttGatewayService();
      final loggedCoordinator = GatewayCoordinator(
        bleClient: testBle,
        mqttService: testMqtt,
        deviceId: 'HK-SHOE-TEST-001',
        onLog: (msg, {bool isError = false}) => logs.add(msg),
      );
      loggedCoordinator.startRouting();

      const burstResult = BurstReassemblyResult(
        isCompleted: true,
        isCrcValid: true,
        totalAnnounced: 0,
        framesRecovered: 0,
        readings: [],
      );

      testBle.emitBurst(burstResult);
      await Future<void>.delayed(const Duration(milliseconds: 15));

      expect(testMqtt.publishedStudioSessions.isEmpty, isTrue);
      expect(logs.any((l) => l.contains('Aucun échantillon IMU')), isTrue);

      loggedCoordinator.stopRouting();
      testBle.dispose();
      testMqtt.disconnect();
    });

    test('Présence unitaire BLE : startRouting et stopRouting émettent online et offline sur status', () async {
      final localBle = FakeBleFootwearClient();
      final localMqtt = FakeMqttGatewayService();
      final localCoordinator = GatewayCoordinator(
        bleClient: localBle,
        mqttService: localMqtt,
        deviceId: 'HK-TEST-PRESENCE',
      );

      // 1. Démarrage du routage -> présence "online"
      localCoordinator.startRouting();
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(localMqtt.publishedGatewayStatuses, contains(true));

      // 2. Arrêt du routage (déconnexion BLE) -> présence "offline"
      localCoordinator.stopRouting();
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(localMqtt.publishedGatewayStatuses.last, equals(false));

      // 3. Reconfiguration (notifyOffline: false) n'émet pas offline
      localMqtt.publishedGatewayStatuses.clear();
      localCoordinator.stopRouting(notifyOffline: false);
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(localMqtt.publishedGatewayStatuses.contains(false), isFalse);

      localBle.dispose();
      localMqtt.disconnect();
    });

    test('Déduplication Studio : Ignore l\'écho distant MQTT si la session est déjà en cours localement', () async {
      final List<String> logs = [];
      final testBle = FakeBleFootwearClient();
      final testMqtt = FakeMqttGatewayService();
      final testStudioApi = FakeStudioApiService();
      testStudioApi.nextSessionId = 'sess-dedup-1234';

      final loggedCoordinator = GatewayCoordinator(
        bleClient: testBle,
        mqttService: testMqtt,
        studioApiService: testStudioApi,
        deviceId: 'HK-SHOE-TEST-001',
        onLog: (msg, {bool isError = false}) => logs.add(msg),
      );
      loggedCoordinator.startRouting();

      // 1. Déclenchement local d'une session Studio
      await loggedCoordinator.triggerStudioSession(
        label: 'course_test',
        durationSec: 10.0,
      );

      expect(testBle.startStudioSessionCallCount, equals(1));
      expect(testBle.lastStartedStudioSessionId, equals('sess-dedup-1234'));

      // 2. Réception de l'écho MQTT avec le même sessionId
      testMqtt.emitStudioCommand(const StudioCommandModel(
        sessionId: 'sess-dedup-1234',
        label: 'course_test',
        durationSec: 10.0,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 15));

      // Vérification que le client BLE n'a pas reçu un deuxième appel START
      expect(testBle.startStudioSessionCallCount, equals(1));
      expect(logs.any((l) => l.contains('Écho de session Studio ignoré')), isTrue);

      loggedCoordinator.stopRouting();
      testBle.dispose();
      testMqtt.disconnect();
    });

    test('Déduplication Studio : Ignore toute commande distante MQTT lorsqu\'une capture est active', () async {
      final List<String> logs = [];
      final testBle = FakeBleFootwearClient();
      final testMqtt = FakeMqttGatewayService();
      final testStudioApi = FakeStudioApiService();
      testStudioApi.nextSessionId = 'sess-local-init';

      final loggedCoordinator = GatewayCoordinator(
        bleClient: testBle,
        mqttService: testMqtt,
        studioApiService: testStudioApi,
        deviceId: 'HK-SHOE-TEST-001',
        onLog: (msg, {bool isError = false}) => logs.add(msg),
      );
      loggedCoordinator.startRouting();

      // 1. Déclenchement local
      await loggedCoordinator.triggerStudioSession(
        label: 'course_test',
        durationSec: 5.0,
      );

      expect(testBle.startStudioSessionCallCount, equals(1));

      // 2. Réception d'une commande distante concurrente pendant que la capture est active
      testMqtt.emitStudioCommand(const StudioCommandModel(
        sessionId: 'sess-remote-echo-diff-uuid',
        label: 'course_test',
        durationSec: 5.0,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 15));

      // Vérification que le deuxième appel BLE est bloqué par _isStudioRecordingActive
      expect(testBle.startStudioSessionCallCount, equals(1));
      expect(logs.any((l) => l.contains('Écho de session Studio ignoré')), isTrue);

      loggedCoordinator.stopRouting();
      testBle.dispose();
      testMqtt.disconnect();
    });

    test('Statut Studio BLE : Libère l\'état de capture si le firmware notifie ERROR ou CANCELLED', () async {
      final List<String> logs = [];
      final testBle = FakeBleFootwearClient();
      final testMqtt = FakeMqttGatewayService();
      final loggedCoordinator = GatewayCoordinator(
        bleClient: testBle,
        mqttService: testMqtt,
        deviceId: 'HK-SHOE-TEST-001',
        onLog: (msg, {bool isError = false}) => logs.add(msg),
      );
      loggedCoordinator.startRouting();

      // 1. Déclenchement local d'une session Studio
      await loggedCoordinator.triggerStudioSession(
        label: 'test_error_recovery',
        durationSec: 5.0,
      );
      expect(loggedCoordinator.isStudioRecordingActive, isTrue);

      // 2. Réception d'une notification d'erreur du firmware BLE ("ERROR busy")
      testBle._statusCtrl.add('ERROR busy');
      await Future<void>.delayed(const Duration(milliseconds: 15));

      // Vérification que l'état interne est bien réinitialisé
      expect(loggedCoordinator.isStudioRecordingActive, isFalse);
      expect(logs.any((l) => l.contains('Libération de l\'état de capture')), isTrue);

      loggedCoordinator.stopRouting();
      testBle.dispose();
      testMqtt.disconnect();
    });
  });
}
