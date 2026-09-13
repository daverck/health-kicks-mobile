import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/models/activity_detection_model.dart';
import 'package:healthkicks_mobile/models/haptic_command_model.dart';
import 'package:healthkicks_mobile/models/imu_reading_model.dart';
import 'package:healthkicks_mobile/models/studio_session_model.dart';
import 'package:healthkicks_mobile/services/ble/ble_footwear_client.dart';
import 'package:healthkicks_mobile/services/ble/burst_reassembler.dart';
import 'package:healthkicks_mobile/services/gateway_coordinator.dart';
import 'package:healthkicks_mobile/services/mqtt/mqtt_gateway_service.dart';

class FakeBleFootwearClient implements BleFootwearClient {
  final _activityCtrl = StreamController<ActivityDetectionModel>.broadcast();
  final _statusCtrl = StreamController<String>.broadcast();
  final _burstCtrl = StreamController<BurstReassemblyResult>.broadcast();

  final List<HapticCommandModel> sentHapticCommands = [];
  String? lastStartedStudioSessionId;

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

  final List<ActivityDetectionModel> publishedDetections = [];
  final List<StudioSessionModel> publishedStudioSessions = [];

  @override
  Stream<HapticCommandModel> get hapticCommandStream => _hapticCtrl.stream;

  void emitHapticCommand(HapticCommandModel cmd) => _hapticCtrl.add(cmd);

  @override
  Future<void> publishActivityDetection(ActivityDetectionModel detection) async {
    publishedDetections.add(detection);
  }

  @override
  Future<void> publishStudioSession(StudioSessionModel session) async {
    publishedStudioSessions.add(session);
  }

  @override
  Future<void> publishGatewayStatus({required bool online}) async {}

  @override
  Future<bool> connect() async => true;

  @override
  void disconnect() {
    _hapticCtrl.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('GatewayCoordinator - Routage bidirectionnel BLE <-> MQTT', () {
    late FakeBleFootwearClient fakeBle;
    late FakeMqttGatewayService fakeMqtt;
    late GatewayCoordinator coordinator;

    setUp(() {
      fakeBle = FakeBleFootwearClient();
      fakeMqtt = FakeMqttGatewayService();
      coordinator = GatewayCoordinator(
        bleClient: fakeBle,
        mqttService: fakeMqtt,
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
      final detection = ActivityDetectionModel(
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
      final command = HapticCommandModel(
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

    test('Relais Studio Burst : Réassemblage validé publié en session batch MQTT', () async {
      await coordinator.triggerStudioSession(
        label: 'course_fractionne',
        durationSec: 30.0,
        sessionId: 'session_abc_123',
      );

      final frames = [
        ImuReadingModel(deltaMs: 0, ax: 0.1, ay: 0.9, az: -0.2, gx: 10, gy: -5, gz: 0),
        ImuReadingModel(deltaMs: 20, ax: 0.12, ay: 0.88, az: -0.19, gx: 12, gy: -4, gz: 1),
      ];

      final burstResult = BurstReassemblyResult(
        isCompleted: true,
        isCrcValid: true,
        totalAnnounced: 2,
        framesRecovered: 2,
        readings: frames,
      );

      fakeBle.emitBurst(burstResult);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(fakeMqtt.publishedStudioSessions.length, equals(1));
      final publishedSession = fakeMqtt.publishedStudioSessions.first;
      expect(publishedSession.sessionId, equals('session_abc_123'));
      expect(publishedSession.label, equals('course_fractionne'));
      expect(publishedSession.deviceId, equals('HK-SHOE-TEST-001'));
      expect(publishedSession.readings.length, equals(2));
    });
  });
}
