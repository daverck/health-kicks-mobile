import 'dart:async';
import 'package:uuid/uuid.dart';
import 'ble/ble_footwear_client.dart';
import 'ble/burst_reassembler.dart';
import 'mqtt/mqtt_gateway_service.dart';
import 'studio/studio_api_service.dart';
import '../models/activity_detection_model.dart';
import '../models/haptic_command_model.dart';
import '../models/studio_command_model.dart';
import '../models/studio_session_model.dart';

const _uuid = Uuid();

typedef CoordinatorLogCallback = void Function(String message, {bool isError});

/// Coordinateur central assurant le routage transparent bidirectionnel BLE <-> MQTT
/// et l'initiation des sessions Studio auprès du Backend FastAPI.
class GatewayCoordinator {
  final BleFootwearClient bleClient;
  final MqttGatewayService mqttService;
  final StudioApiService? studioApiService;
  final String deviceId;
  final CoordinatorLogCallback? onLog;

  StreamSubscription<ActivityDetectionModel>? _activitySub;
  StreamSubscription<HapticCommandModel>? _hapticSub;
  StreamSubscription<BurstReassemblyResult>? _burstSub;
  StreamSubscription<StudioCommandModel>? _studioCommandSub;

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
    this.onLog,
  });

  /// Démarre le routage bidirectionnel entre le BLE et le MQTT
  /// et notifie le statut "online" de l'équipement BLE sur AWS IoT Core si connecté.
  void startRouting() {
    if (mqttService.isConnected) {
      unawaited(publishBleStatus(online: true));
    }

    // 1. Relais montant : BLE Activity Detection -> Cloud MQTT
    _activitySub = bleClient.activityStream.listen((detection) async {
      await mqttService.publishActivityDetection(detection);
    });

    // 2. Relais descendant : Cloud MQTT Haptic Command -> BLE Footwear
    _hapticSub = mqttService.hapticCommandStream.listen((command) async {
      await bleClient.sendHapticCommand(command);
    });

    // 3. Relais descendant : Cloud MQTT Studio Start Command -> BLE Footwear
    _studioCommandSub = mqttService.studioCommandStream.listen((command) async {
      onLog?.call(
        '[GATEWAY] Commande Studio distante reçue (session_id: ${command.sessionId}, label: ${command.label}, durée: ${command.durationSec}s)',
        isError: false,
      );
      await handleRemoteStudioCommand(command);
    });

    // 4. Relais batch : BLE Studio Data Burst reassemblé -> Cloud MQTT DynamoDB
    _burstSub = bleClient.burstResultStream.listen((result) async {
      onLog?.call(
        '[GATEWAY] Paquet fin de burst reçu : complété=${result.isCompleted}, '
        'CRC valide=${result.isCrcValid}, trames=${result.framesRecovered}/${result.totalAnnounced}',
        isError: !result.isSuccess,
      );

      if (result.readings.isEmpty) {
        onLog?.call(
          '[GATEWAY] Aucun échantillon IMU contenu dans le burst reçu.',
          isError: true,
        );
        return;
      }

      if (!result.isCrcValid) {
        onLog?.call(
          '[GATEWAY] Avertissement CRC32 non concordant. Les ${result.readings.length} trames reçues sont tout de même transmises.',
          isError: true,
        );
      }

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
      try {
        onLog?.call(
          '[GATEWAY] Publication de la session ${session.sessionId} (${session.readings.length} trames) vers MQTT...',
          isError: false,
        );
        await mqttService.publishStudioSession(session);
        _studioSessionSavedController.add(session);
        onLog?.call(
          '[GATEWAY] Session ${session.sessionId} publiée avec succès via MQTT.',
          isError: false,
        );
      } catch (e) {
        onLog?.call(
          '[GATEWAY] Erreur lors de la publication MQTT : $e',
          isError: true,
        );
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
    // 1. Sécuriser la connexion MQTT avant de lancer la session d'enregistrement
    if (!mqttService.isConnected) {
      onLog?.call(
        '[GATEWAY] MQTT non connecté. Connexion préventive avant de déclencher la capture Studio...',
        isError: false,
      );
      try {
        await mqttService.connect();
      } catch (e) {
        onLog?.call(
          '[GATEWAY] Avertissement : échec connexion MQTT préalable ($e). Poursuite du flux.',
          isError: true,
        );
      }
    }

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

  /// Traite une commande Studio déclenchée à distance depuis le Web / Backend via MQTT.
  /// Réutilise strictement le [session_id] déjà alloué et persisté par le backend dans PostgreSQL,
  /// sans ré-effectuer d'appel REST de réservation redondant.
  Future<void> handleRemoteStudioCommand(StudioCommandModel command) async {
    _currentStudioSessionId = command.sessionId;
    _currentStudioLabel = command.label;
    _currentStudioDurationSec = command.durationSec;
    _currentStudioStartTimestamp =
        DateTime.now().millisecondsSinceEpoch / 1000.0;

    onLog?.call(
      '[GATEWAY] Déclenchement de la capture BLE pour la commande distante (session: ${command.sessionId})...',
      isError: false,
    );

    await bleClient.startStudioSession(
      label: command.label,
      durationSec: command.durationSec,
      sessionId: command.sessionId,
    );
  }

  /// Interrompt le routage et notifie optionnellement le statut "offline" de l'équipement BLE sur AWS IoT Core.
  void stopRouting({bool notifyOffline = true}) {
    if (notifyOffline) {
      unawaited(publishBleStatus(online: false));
    }
    _activitySub?.cancel();
    _activitySub = null;
    _hapticSub?.cancel();
    _hapticSub = null;
    _studioCommandSub?.cancel();
    _studioCommandSub = null;
    _burstSub?.cancel();
    _burstSub = null;
  }

  /// Publie le statut de présence de la chaussure BLE sur le topic de statut de l'équipement.
  Future<void> publishBleStatus({required bool online}) async {
    if (!mqttService.isConnected) {
      onLog?.call(
        '[GATEWAY] Publication présence ($deviceId -> ${online ? "online" : "offline"}) différée : MQTT non connecté.',
        isError: false,
      );
      return;
    }

    try {
      await mqttService.publishGatewayStatus(online: online);
      onLog?.call(
        '[GATEWAY] Statut présence équipement ($deviceId) : ${online ? "online" : "offline"}',
        isError: false,
      );
    } catch (e) {
      onLog?.call(
        '[GATEWAY] Erreur publication présence équipement ($deviceId) : $e',
        isError: false,
      );
    }
  }

  void dispose() {
    stopRouting();
    _studioSessionSavedController.close();
  }
}
