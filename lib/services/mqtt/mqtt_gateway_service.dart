import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../../core/aws/sigv4_signer.dart';
import '../../models/activity_detection_model.dart';
import '../../models/haptic_command_model.dart';
import '../../models/studio_command_model.dart';
import '../../models/studio_session_model.dart';
import '../auth/iot_credentials_repository.dart';
import '../auth/token_storage_service.dart';

typedef MqttLogCallback = void Function(String message, {bool isError});

/// Service de passerelle MQTT exclusif vers AWS IoT Core (WSS SigV4 Port 443).
/// Référence contractuelle : contracts/README.md (Section 3 : Contrats MQTT IoT)
class MqttGatewayService {
  final String deviceId;
  final String? userId;
  final String clientId;
  final IotCredentialsRepository credentialsRepository;
  final MqttLogCallback? onLog;
  final VoidCallback? onConnectionRestored;

  MqttServerClient? _client;
  bool _isConnected = false;
  bool get isConnected =>
      _isConnected &&
      _client != null &&
      _client!.connectionStatus?.state == MqttConnectionState.connected;

  final _hapticCommandsController = StreamController<HapticCommandModel>.broadcast();
  Stream<HapticCommandModel> get hapticCommandStream => _hapticCommandsController.stream;

  final _studioCommandsController = StreamController<StudioCommandModel>.broadcast();
  Stream<StudioCommandModel> get studioCommandStream => _studioCommandsController.stream;

  StreamSubscription? _updatesSub;

  MqttGatewayService({
    required this.deviceId,
    this.userId,
    required this.credentialsRepository,
    String? clientId,
    this.onLog,
    this.onConnectionRestored,
  }) : clientId = clientId ??
            (userId != null && userId.isNotEmpty
                ? 'healthkicks-mobile-$userId'
                : '');

  /// Établit la liaison MQTT sécurisée vers AWS IoT Core via WebSockets SigV4 sur le port 443.
  Future<bool> connect({MqttLogCallback? onLog}) async {
    final log = onLog ?? this.onLog;

    // 1. Nettoyage préventif propre avant tout nouvel appel connect()
    if (_client != null) {
      try {
        _client!.onDisconnected = null;
        _client!.onAutoReconnect = null;
        _client!.onAutoReconnected = null;
        _client!.disconnect();
      } catch (_) {}
      _client = null;
      await Future.delayed(const Duration(milliseconds: 300));
    }

    log?.call('[MQTT] Récupération des identifiants STS backend...', isError: false);

    try {
      final creds = await credentialsRepository.fetchCredentials(deviceId: deviceId);
      log?.call(
        '[MQTT] Identifiants STS valides (Expire à : ${creds.expiration.toIso8601String()}, Région : ${creds.region})',
        isError: false,
      );

      final signedWssUrl = SigV4Signer.buildSignedWebSocketUrl(credentials: creds);
      log?.call(
        '[MQTT] Signature SigV4 générée, connexion WSS 443 vers AWS IoT Core (${creds.iotEndpoint})...',
        isError: false,
      );

      var effectiveUserId = (userId != null && userId!.isNotEmpty) ? userId! : '';
      if (effectiveUserId.isEmpty && creds.userId != null && creds.userId!.isNotEmpty) {
        effectiveUserId = creds.userId!;
      }
      if (effectiveUserId.isEmpty) {
        try {
          final tokenStorage = credentialsRepository.tokenStorage ?? TokenStorageService();
          final tokenUserId = await tokenStorage.getUserIdFromToken();
          if (tokenUserId != null && tokenUserId.isNotEmpty) {
            effectiveUserId = tokenUserId;
          }
        } catch (_) {}
      }
      if (effectiveUserId.isEmpty || effectiveUserId == 'unknown') {
        log?.call(
          '[MQTT] Connexion refusée : aucun identifiant utilisateur (userId) valide ou session non résolue. Annulation pour préserver l\'isolation multi-tenant.',
          isError: true,
        );
        return false;
      }

      final effectiveClientId = (clientId.isNotEmpty &&
              (clientId == 'healthkicks-mobile-$effectiveUserId' ||
                  clientId == 'healthkicks-session-$effectiveUserId'))
          ? clientId
          : 'healthkicks-mobile-$effectiveUserId';

      final lwtTopic = 'healthkicks/v1/users/$effectiveUserId/gateway-status';
      final lwtPayload = jsonEncode({
        'user_id': effectiveUserId,
        'state': 'offline',
        'gateway': 'mobile',
      });

      _client = MqttServerClient.withPort(
        signedWssUrl,
        effectiveClientId,
        443,
      );

      _client!.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
      _client!.setProtocolV311();
      _client!.useWebSocket = true;
      _client!.secure = false;
      _client!.keepAlivePeriod = 30;
      _client!.autoReconnect = true;
      _client!.logging(on: false);

      _client!.onConnected = () {
        _isConnected = true;
        log?.call('[MQTT] WebSocket connecté à AWS IoT Core.', isError: false);
        onConnectionRestored?.call();
      };
      _client!.onDisconnected = () {
        _isConnected = false;
        log?.call('[MQTT] WebSocket déconnecté d\'AWS IoT Core.', isError: true);
      };
      _client!.onAutoReconnect = () {
        _isConnected = false;
        log?.call('[MQTT] Reconnexion automatique MQTT en cours...', isError: false);
      };
      _client!.onAutoReconnected = () {
        _isConnected = true;
        log?.call('[MQTT] Reconnexion automatique MQTT réussie.', isError: false);
        _resubscribeTopics();
        onConnectionRestored?.call();
      };

      final connMessage = MqttConnectMessage()
          .withClientIdentifier(effectiveClientId)
          .startClean()
          .withWillTopic(lwtTopic)
          .withWillMessage(lwtPayload)
          .withWillQos(MqttQos.atLeastOnce);

      _client!.connectionMessage = connMessage;

      final status = await _client!.connect();
      _isConnected = status?.state == MqttConnectionState.connected;

      if (_isConnected) {
        log?.call('[MQTT] Connecté avec succès à AWS IoT Core en WebSockets SigV4.', isError: false);
        _subscribeToCommands();
      } else {
        log?.call(
          '[MQTT] Échec connexion AWS IoT Core WSS : statut ${status?.state}.',
          isError: true,
        );
      }
      return _isConnected;
    } catch (e) {
      _isConnected = false;
      log?.call('[MQTT] WebSocket error: $e', isError: true);
      return false;
    }
  }

  void _resubscribeTopics() {
    final log = onLog;
    final hapticTopic = 'healthkicks/v1/$deviceId/commands/haptic';
    final studioStartTopic = 'healthkicks/v1/$deviceId/commands/studio/start';

    _client?.subscribe(hapticTopic, MqttQos.atLeastOnce);
    _client?.subscribe(studioStartTopic, MqttQos.atLeastOnce);

    log?.call('[MQTT] Souscriptions renouvelées après reconnexion automatique : $hapticTopic & $studioStartTopic', isError: false);
  }

  void _subscribeToCommands() {
    final log = onLog;
    final hapticTopic = 'healthkicks/v1/$deviceId/commands/haptic';
    final studioStartTopic = 'healthkicks/v1/$deviceId/commands/studio/start';

    _client?.subscribe(hapticTopic, MqttQos.atLeastOnce);
    _client?.subscribe(studioStartTopic, MqttQos.atLeastOnce);

    log?.call('[MQTT] Souscriptions actives : $hapticTopic & $studioStartTopic', isError: false);

    _updatesSub?.cancel();
    _updatesSub = _client?.updates?.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      for (final msg in messages) {
        final recMessage = msg.payload as MqttPublishMessage;
        final payloadStr = MqttPublishPayload.bytesToStringAsString(
          recMessage.payload.message,
        );

        if (msg.topic == hapticTopic) {
          try {
            final jsonMap = jsonDecode(payloadStr) as Map<String, dynamic>;
            final command = HapticCommandModel.fromJson(jsonMap);
            _hapticCommandsController.add(command);
          } catch (e) {
            log?.call('[MQTT] Erreur décodage commande haptique : $e', isError: true);
          }
        } else if (msg.topic == studioStartTopic || msg.topic.endsWith('/commands/studio/start')) {
          try {
            final jsonMap = jsonDecode(payloadStr) as Map<String, dynamic>;
            final command = StudioCommandModel.fromJson(jsonMap);
            log?.call(
              '[MQTT] Commande Studio distante reçue (session: ${command.sessionId}, label: ${command.label}, durée: ${command.durationSec}s)',
              isError: false,
            );
            _studioCommandsController.add(command);
          } catch (e) {
            log?.call('[MQTT] Erreur décodage commande Studio distante : $e', isError: true);
          }
        }
      }
    });
  }

  /// Publie un événement de détection d'activité vers AWS IoT Core (QoS 1).
  Future<void> publishActivityDetection(ActivityDetectionModel detection) async {
    final log = onLog;

    if (!isConnected || _client == null) {
      log?.call('[MQTT] Impossible de publier la détection : MQTT non connecté.', isError: false);
      return;
    }

    try {
      final topic = 'healthkicks/v1/$deviceId/events/detection';
      final payload = detection.toMqttPayload(deviceId);
      final jsonString = jsonEncode(payload);

      final builder = MqttClientPayloadBuilder();
      builder.addString(jsonString);

      _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    } catch (e) {
      log?.call('[MQTT] Erreur lors de la publication détection : $e', isError: true);
    }
  }

  /// Publie les sessions Studio réassemblées vers DynamoDB via AWS IoT Core (QoS 1).
  /// S'assure que chaque lot reste bien sous la limite AWS de 128 Ko.
  Future<void> publishStudioSession(StudioSessionModel session) async {
    final log = onLog;

    // 1. Vérifier la connexion et tenter une reconnexion automatique si besoin
    if (!isConnected || _client == null) {
      log?.call(
        '[MQTT] Client non connecté lors de la publication Studio. Reconnexion automatique...',
        isError: false,
      );
      final connected = await connect(onLog: log);
      if (!connected) {
        log?.call(
          '[MQTT] Échec de reconnexion MQTT : impossible de publier les données Studio.',
          isError: true,
        );
        return;
      }
    }

    if (session.readings.isEmpty) {
      log?.call(
        '[MQTT] Avertissement : session Studio vide (0 échantillon). Aucun lot à publier.',
        isError: true,
      );
      return;
    }

    final topic = 'healthkicks/v1/$deviceId/telemetry/raw';
    final chunks = session.toMqttBatchPayloads(maxReadingsPerChunk: 500);

    log?.call(
      '[MQTT] Début publication Studio (${session.readings.length} trames sur $topic en ${chunks.length} lot(s))...',
      isError: false,
    );

    for (int i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      try {
        final jsonString = jsonEncode(chunk);
        final builder = MqttClientPayloadBuilder();
        builder.addString(jsonString);

        _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
        final readingCount = (chunk['readings'] as List?)?.length ?? 0;
        log?.call(
          '[MQTT] Lot ${i + 1}/${chunks.length} publié avec succès ($readingCount trames)',
          isError: false,
        );
      } catch (e) {
        log?.call(
          '[MQTT] Erreur lors de la publication du lot ${i + 1}/${chunks.length} : $e',
          isError: true,
        );
      }
    }
  }

  /// Publie le statut unitaire de présence d'un équipement BLE sur AWS IoT Core.
  Future<void> publishDeviceStatus({required bool online, String? targetDeviceId}) async {
    final effectiveDeviceId = targetDeviceId ?? deviceId;
    final log = onLog;

    if (!isConnected || _client == null) {
      log?.call(
        '[MQTT] Statut présence équipement ($effectiveDeviceId -> ${online ? "online" : "offline"}) ignoré : client MQTT non connecté (état: ${_client?.connectionStatus?.state}).',
        isError: false,
      );
      return;
    }

    try {
      final topic = 'healthkicks/v1/$effectiveDeviceId/status';
      final payload = jsonEncode({
        'device_id': effectiveDeviceId,
        'state': online ? 'online' : 'offline',
        'gateway': 'mobile',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      final builder = MqttClientPayloadBuilder();
      builder.addString(payload);

      _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
      log?.call(
        '[MQTT] Statut présence équipement ($effectiveDeviceId -> ${online ? "online" : "offline"}) publié avec succès sur $topic',
        isError: false,
      );
    } catch (e) {
      log?.call(
        '[MQTT] Erreur publication présence équipement ($effectiveDeviceId) : $e',
        isError: false,
      );
    }
  }

  /// Publie le statut en ligne de la passerelle / équipement (alias).
  Future<void> publishGatewayStatus({required bool online}) =>
      publishDeviceStatus(online: online);

  void disconnect() {
    publishGatewayStatus(online: false);
    _updatesSub?.cancel();
    _updatesSub = null;
    if (_client != null) {
      try {
        _client!.onDisconnected = null;
        _client!.onAutoReconnect = null;
        _client!.onAutoReconnected = null;
        _client!.disconnect();
      } catch (_) {}
      _client = null;
    }
    _isConnected = false;
    _hapticCommandsController.close();
    _studioCommandsController.close();
  }
}
