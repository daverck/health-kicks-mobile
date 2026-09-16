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
      final effectiveUserId = userId;
      final bool hasUserId = effectiveUserId != null && effectiveUserId.isNotEmpty;

      bool connected = false;

      // 1. Tenter la connexion avec le LWT passerelle utilisateur (healthkicks/v1/users/{user_id}/gateway-status)
      // si l'identifiant utilisateur est renseigné.
      if (hasUserId) {
        final userLwtTopic = 'healthkicks/v1/users/$effectiveUserId/gateway-status';
        final userLwtPayload = jsonEncode({
          'user_id': effectiveUserId,
          'state': 'offline',
          'gateway': 'mobile',
        });

        log?.call(
          '[MQTT] Tentative de connexion avec LWT utilisateur ($userLwtTopic)...',
          isError: false,
        );

        connected = await _tryConnectWithLwt(
          signedWssUrl: signedWssUrl,
          effectiveClientId: effectiveClientId,
          lwtTopic: userLwtTopic,
          lwtPayload: userLwtPayload,
        );

        if (!connected) {
          log?.call(
            '[MQTT] Connexion avec LWT utilisateur non aboutie (broker non répondant ou politique STS restrictive). Bascule automatique vers LWT équipement...',
            isError: true,
          );
        }
      }

      // 2. Repli / Fallback vers LWT équipement (healthkicks/v1/{device_id}/status)
      // si aucun utilisateur n'est configuré ou si la politique STS distante restreint encore l'accès aux topics d'équipement.
      if (!connected) {
        final deviceLwtTopic = 'healthkicks/v1/$deviceId/status';
        final deviceLwtPayload = jsonEncode({
          'device_id': deviceId,
          'state': 'offline',
          'gateway': 'mobile',
        });

        log?.call(
          '[MQTT] Connexion avec LWT équipement ($deviceLwtTopic)...',
          isError: false,
        );

        connected = await _tryConnectWithLwt(
          signedWssUrl: signedWssUrl,
          effectiveClientId: effectiveClientId,
          lwtTopic: deviceLwtTopic,
          lwtPayload: deviceLwtPayload,
        );
      }

      _isConnected = connected;

      if (_isConnected) {
        log?.call('[MQTT] Connecté avec succès à AWS IoT Core en WebSockets SigV4.', isError: false);
        _subscribeToCommands();
      } else {
        log?.call(
          '[MQTT] Échec définitif de connexion AWS IoT Core WSS.',
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

  MqttServerClient _createMqttClient(String signedWssUrl, String effectiveClientId) {
    final client = MqttServerClient.withPort(
      signedWssUrl,
      effectiveClientId,
      443,
    );

    // AWS IoT Core exige strictement le sous-protocole WebSocket unique 'mqtt'.
    // Le défaut multi-protocoles de mqtt_client ('mqtt', 'mqttv3.1', 'mqttv3.11') provoque une erreur HTTP 403.
    client.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
    client.setProtocolV311();
    client.useWebSocket = true;
    client.secure = false; // Le chiffrement TLS est géré au niveau du protocole wss://
    client.keepAlivePeriod = 30;
    client.autoReconnect = true;
    client.logging(on: false);

    client.onConnected = () {
      _isConnected = true;
      onLog?.call('[MQTT] WebSocket connecté à AWS IoT Core.', isError: false);
    };
    client.onDisconnected = () {
      _isConnected = false;
      onLog?.call('[MQTT] WebSocket déconnecté d\'AWS IoT Core.', isError: true);
    };
    client.onAutoReconnect = () {
      onLog?.call('[MQTT] Reconnexion automatique MQTT en cours...', isError: false);
    };
    client.onAutoReconnected = () {
      _isConnected = true;
      onLog?.call('[MQTT] Reconnexion automatique MQTT réussie.', isError: false);
    };

    return client;
  }

  Future<bool> _tryConnectWithLwt({
    required String signedWssUrl,
    required String effectiveClientId,
    required String lwtTopic,
    required String lwtPayload,
  }) async {
    try {
      _client?.disconnect();
    } catch (_) {}

    _client = _createMqttClient(signedWssUrl, effectiveClientId);

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(effectiveClientId)
        .startClean()
        .withWillTopic(lwtTopic)
        .withWillMessage(lwtPayload)
        .withWillQos(MqttQos.atLeastOnce);

    _client!.connectionMessage = connMessage;

    try {
      final status = await _client!.connect();
      return status?.state == MqttConnectionState.connected;
    } catch (e) {
      onLog?.call('[MQTT] Tentative connect avec LWT ($lwtTopic) a échoué: $e', isError: true);
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
