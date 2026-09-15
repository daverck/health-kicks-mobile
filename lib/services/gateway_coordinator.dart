import 'dart:async';
import 'package:uuid/uuid.dart';
import 'ble/ble_footwear_client.dart';
import 'ble/burst_reassembler.dart';
import 'mqtt/mqtt_gateway_service.dart';
import 'studio/studio_api_service.dart';
import '../models/activity_detection_model.dart';
import '../models/haptic_command_model.dart';
import '../models/studio_session_model.dart';

const _uuid = Uuid();

/// Coordinateur central assurant le routage transparent bidirectionnel BLE <-> MQTT
/// et l'initiation des sessions Studio auprès du Backend FastAPI.
class GatewayCoordinator {
  final BleFootwearClient bleClient;
  final MqttGatewayService mqttService;
  final StudioApiService? studioApiService;
  final String deviceId;

  StreamSubscription<ActivityDetectionModel>? _activitySub;
  StreamSubscription<HapticCommandModel>? _hapticSub;
  StreamSubscription<BurstReassemblyResult>? _burstSub;

  final _studioSessionSavedController =
      StreamController<StudioSessionModel>.broadcast();

  /// Flux notifiant la fin d'enregistrement et la synchronisation d'une session Studio.
  Stream<StudioSessionModel> get studioSessionSavedStream =>
      _studioSessionSavedController.stream;

  String? _currentStudioSessionId;
  String? _currentStudioLabel;
  double _currentStudioStartTimestamp = 0;
  double _currentStudioDurationSec = 5.0;

  GatewayCoordinator({
    required this.bleClient,
    required this.mqttService,
    this.studioApiService,
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
          sessionId: _currentStudioSessionId ?? _uuid.v4(),
          label: _currentStudioLabel ?? 'unlabeled',
          deviceId: deviceId,
          startTimestampEpoch: _currentStudioStartTimestamp > 0
              ? _currentStudioStartTimestamp
              : DateTime.now().millisecondsSinceEpoch / 1000.0,
          durationSec: _currentStudioDurationSec,
          readings: result.readings,
        );

        // Publication MQTT vers DynamoDB
        await mqttService.publishStudioSession(session);

        _studioSessionSavedController.add(session);
      }
    });
  }

  /// Déclenche une session Studio, réserve la session dans PostgreSQL via l'API REST
  /// du backend FastAPI pour obtenir l'UUID officiel [sessionId], puis commande la chaussure en BLE.
  Future<void> triggerStudioSession({
    required String label,
    required double durationSec,
    String? sessionId,
  }) async {
    String effectiveSessionId;

    if (studioApiService != null) {
      try {
        final response = await studioApiService!.startStudioSession(
          deviceId: deviceId,
          label: label,
          durationSec: durationSec,
        );
        effectiveSessionId = response.sessionId;
      } catch (_) {
        effectiveSessionId = (sessionId != null && sessionId.isNotEmpty)
            ? sessionId
            : _uuid.v4();
      }
    } else if (sessionId != null && sessionId.isNotEmpty) {
      effectiveSessionId = sessionId;
    } else {
      effectiveSessionId = _uuid.v4();
    }

    _currentStudioSessionId = effectiveSessionId;
    _currentStudioLabel = label;
    _currentStudioDurationSec = durationSec;
    _currentStudioStartTimestamp =
        DateTime.now().millisecondsSinceEpoch / 1000.0;

    await bleClient.startStudioSession(
      label: label,
      durationSec: durationSec,
      sessionId: effectiveSessionId,
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

  void dispose() {
    stopRouting();
    _studioSessionSavedController.close();
  }
}
