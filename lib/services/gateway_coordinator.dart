import 'dart:async';
import 'ble/ble_footwear_client.dart';
import 'ble/burst_reassembler.dart';
import 'mqtt/mqtt_gateway_service.dart';
import '../models/activity_detection_model.dart';
import '../models/haptic_command_model.dart';
import '../models/studio_session_model.dart';

/// Coordinateur central assurant le routage transparent bidirectionnel BLE <-> MQTT.
class GatewayCoordinator {
  final BleFootwearClient bleClient;
  final MqttGatewayService mqttService;
  final String deviceId;

  StreamSubscription<ActivityDetectionModel>? _activitySub;
  StreamSubscription<HapticCommandModel>? _hapticSub;
  StreamSubscription<BurstReassemblyResult>? _burstSub;

  String? _currentStudioSessionId;
  String? _currentStudioLabel;
  double _currentStudioStartTimestamp = 0;

  GatewayCoordinator({
    required this.bleClient,
    required this.mqttService,
    required this.deviceId,
  });

  /// Démarre le routage bidirectionnel entre le BLE et le MQTT.
  void startRouting() {
    // 1. Relais montant : BLE Activity Detection -> Cloud MQTT
    _activitySub = bleClient.activityStream.listen((detection) async {
      await mqttService.publishActivityDetection(detection);
    });

    // 2. Relais descendant : Cloud MQTT Haptic Command -> BLE Footwear
    _hapticSub = mqttService.hapticCommandStream.listen((command) async {
      await bleClient.sendHapticCommand(command);
    });

    // 3. Relais batch : BLE Studio Data Burst reassemblé -> Cloud MQTT DynamoDB
    _burstSub = bleClient.burstResultStream.listen((result) async {
      if (result.isSuccess) {
        final session = StudioSessionModel(
          sessionId: _currentStudioSessionId ?? 'unknown_session',
          label: _currentStudioLabel ?? 'unlabeled',
          deviceId: deviceId,
          startTimestampEpoch: _currentStudioStartTimestamp > 0
              ? _currentStudioStartTimestamp
              : DateTime.now().millisecondsSinceEpoch / 1000.0,
          readings: result.readings,
        );

        await mqttService.publishStudioSession(session);
      }
    });
  }

  /// Déclenche une session Studio et mémorise le contexte pour la sérialisation du burst.
  Future<void> triggerStudioSession({
    required String label,
    required double durationSec,
    required String sessionId,
  }) async {
    _currentStudioSessionId = sessionId;
    _currentStudioLabel = label;
    _currentStudioStartTimestamp = DateTime.now().millisecondsSinceEpoch / 1000.0;

    await bleClient.startStudioSession(
      label: label,
      durationSec: durationSec,
      sessionId: sessionId,
    );
  }

  void stopRouting() {
    _activitySub?.cancel();
    _activitySub = null;
    _hapticSub?.cancel();
    _hapticSub = null;
    _burstSub?.cancel();
    _burstSub = null;
  }
}
