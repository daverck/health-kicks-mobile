import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../../core/aws/sigv4_signer.dart';
import '../../models/activity_detection_model.dart';
import '../../models/haptic_command_model.dart';
import '../../models/studio_command_model.dart';
import '../../models/studio_session_model.dart';
import '../auth/iot_credentials_repository.dart';

typedef MqttLogCallback = void Function(String message, {bool isError});

/// Service de passerelle MQTT exclusif vers AWS IoT Core (WSS SigV4 Port 443).
/// Référence contractuelle : contracts/README.md (Section 3 : Contrats MQTT IoT)
class MqttGatewayService {
  final String deviceId;
  final String? userId;
  final String clientId;
  final IotCredentialsRepository credentialsRepository;
  final MqttLogCallback? onLog;

  MqttServerClient? _client;
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  final _hapticCommandsController = StreamController<HapticCommandModel>.broadcast();
  Stream<HapticCommandModel> get hapticCommandStream => _hapticCommandsController.stream;

  final _studioCommandsController = StreamController<StudioCommandModel>.broadcast();
  Stream<StudioCommandModel> get studioCommandStream => _studioCommandsController.stream;

  MqttGatewayService({
    required this.deviceId,
    this.userId,
    required this.credentialsRepository,
    String? clientId,
    this.onLog,
  }) : clientId = clientId ?? 'healthkicks-session-$deviceId';

  /// Établit la liaison MQTT sécurisée vers AWS IoT Core via WebSockets SigV4 sur le port 443.
  Future<bool> connect({MqttLogCallback? onLog}) async {
    final log = onLog ?? this.onLog;

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

      final effectiveClientId = clientId.isNotEmpty ? clientId : 'healthkicks-session-$deviceId';
      final effectiveUserId = (userId != null && userId!.isNotEmpty) ? userId! : 'unknown';
      final lwtTopic = 'healthkicks/v1/users/$effectiveUserId/gateway-status';
      final lwtPayload = jsonEncode({
        'user_id': effectiveUserId,
        'state': 'offline',
        'gateway': 'mobile',
      });

      // Dans mqtt_client 10.11.11 :
      // MqttServerWsConnection.connect(server, port) valide que server débute impérativement par 'ws://' ou 'wss://'.
      // L'URL WSS pré-signée SigV4 complète (sans fragment #) est transmise comme paramètre 'server'.
      _client = MqttServerClient.withPort(
        signedWssUrl,
        effectiveClientId,
        443,
      );

      // AWS IoT Core exige strictement le sous-protocole WebSocket unique 'mqtt'.
      // Le défaut multi-protocoles de mqtt_client ('mqtt', 'mqttv3.1', 'mqttv3.11') provoque une erreur HTTP 403.
      _client!.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
      _client!.setProtocolV311();
      _client!.useWebSocket = true;
      _client!.secure = false; // Le chiffrement TLS est géré au niveau du protocole wss://
      _client!.keepAlivePeriod = 30;
      _client!.autoReconnect = true;
      _client!.logging(on: false);

      _client!.onConnected = () {
        _isConnected = true;
        log?.call('[MQTT] WebSocket connecté à AWS IoT Core.', isError: false);
      };
      _client!.onDisconnected = () {
        _isConnected = false;
        log?.call('[MQTT] WebSocket déconnecté d\'AWS IoT Core.', isError: true);
      };
      _client!.onAutoReconnect = () {
        log?.call('[MQTT] Reconnexion automatique MQTT en cours...', isError: false);
      };
      _client!.onAutoReconnected = () {
        _isConnected = true;
        log?.call('[MQTT] Reconnexion automatique MQTT réussie.', isError: false);
      };

      // Configuration Last Will & Testament (LWT) basée strictement sur user_id (rupture passerelle)
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

  void _subscribeToCommands() {
    final log = onLog;
    final hapticTopic = 'healthkicks/v1/$deviceId/commands/haptic';
    final studioStartTopic = 'healthkicks/v1/$deviceId/commands/studio/start';

    _client?.subscribe(hapticTopic, MqttQos.atLeastOnce);
    _client?.subscribe(studioStartTopic, MqttQos.atLeastOnce);

    log?.call('[MQTT] Souscriptions actives : $hapticTopic & $studioStartTopic', isError: false);

    _client?.updates?.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
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
    final isClientConnected = _client != null &&
        _client!.connectionStatus?.state == MqttConnectionState.connected;

    if (!_isConnected || !isClientConnected) {
      log?.call('[MQTT] Impossible de publier la détection : MQTT non connecté.', isError: true);
      return;
    }

    final topic = 'healthkicks/v1/$deviceId/events/detection';
    final payload = detection.toMqttPayload(deviceId);
    final jsonString = jsonEncode(payload);

    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonString);

    _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  /// Publie les sessions Studio réassemblées vers DynamoDB via AWS IoT Core (QoS 1).
  /// S'assure que chaque lot reste bien sous la limite AWS de 128 Ko.
  Future<void> publishStudioSession(StudioSessionModel session) async {
    final log = onLog;

    // 1. Vérifier la connexion et tenter une reconnexion automatique si besoin
    final isClientConnected = _client != null &&
        _client!.connectionStatus?.state == MqttConnectionState.connected;

    if (!_isConnected || !isClientConnected) {
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
    if (!_isConnected || _client == null) return;

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
  }

  /// Publie le statut en ligne de la passerelle / équipement (alias).
  Future<void> publishGatewayStatus({required bool online}) =>
      publishDeviceStatus(online: online);

  void disconnect() {
    publishGatewayStatus(online: false);
    _client?.disconnect();
    _isConnected = false;
    _hapticCommandsController.close();
    _studioCommandsController.close();
  }
}
