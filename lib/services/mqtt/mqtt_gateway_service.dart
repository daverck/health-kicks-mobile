import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../../core/aws/sigv4_signer.dart';
import '../../models/activity_detection_model.dart';
import '../../models/haptic_command_model.dart';
import '../../models/studio_session_model.dart';
import '../auth/iot_credentials_repository.dart';

typedef MqttLogCallback = void Function(String message, {bool isError});

enum MqttConnectionMode {
  localTcp,
  cloudAwsWebSockets,
}

/// Service de passerelle MQTT vers AWS IoT Core (WSS SigV4 Port 443) ou Mosquitto local (Port 1883).
/// Référence contractuelle : contracts/README.md (Section 3 : Contrats MQTT IoT)
class MqttGatewayService {
  final String brokerHost;
  final int brokerPort;
  final String deviceId;
  final String clientId;
  final SecurityContext? securityContext;
  final MqttLogCallback? onLog;

  final MqttConnectionMode connectionMode;
  final IotCredentialsRepository? credentialsRepository;

  MqttServerClient? _client;
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  final _hapticCommandsController = StreamController<HapticCommandModel>.broadcast();
  Stream<HapticCommandModel> get hapticCommandStream => _hapticCommandsController.stream;

  MqttGatewayService({
    required this.brokerHost,
    this.brokerPort = 1883,
    required this.deviceId,
    String? clientId,
    this.securityContext,
    this.onLog,
    this.connectionMode = MqttConnectionMode.localTcp,
    this.credentialsRepository,
  }) : clientId = clientId ?? 'healthkicks-session-$deviceId';

  /// Établit la liaison MQTT selon le mode configuré :
  /// 1. Local (Mosquitto) : TCP direct sans TLS sur port 1883
  /// 2. Cloud (AWS IoT Core) : WebSockets signés SigV4 sur port 443 via STS
  Future<bool> connect({MqttLogCallback? onLog}) async {
    final log = onLog ?? this.onLog;

    if (connectionMode == MqttConnectionMode.cloudAwsWebSockets) {
      return _connectCloudAwsSigV4(log);
    } else {
      return _connectLocalTcp(log);
    }
  }

  Future<bool> _connectCloudAwsSigV4(MqttLogCallback? log) async {
    if (credentialsRepository == null) {
      log?.call(
        '[MQTT] Impossible de se connecter en mode Cloud : IotCredentialsRepository non configuré.',
        isError: true,
      );
      return false;
    }

    log?.call('[MQTT] Récupération des identifiants STS backend...', isError: false);

    try {
      final creds = await credentialsRepository!.fetchCredentials(deviceId: deviceId);
      log?.call(
        '[MQTT] Identifiants STS valides (Expire à : ${creds.expiration.toIso8601String()}, Région : ${creds.region})',
        isError: false,
      );

      final signedWssUrl = SigV4Signer.buildSignedWebSocketUrl(credentials: creds);
      log?.call('[MQTT] Signature SigV4 générée, connexion WSS 443...', isError: false);

      final effectiveClientId = clientId.isNotEmpty ? clientId : 'healthkicks-session-$deviceId';

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

      // Configuration Last Will & Testament (LWT)
      final lwtPayload = jsonEncode({
        'device_id': deviceId,
        'state': 'offline',
        'gateway': 'mobile',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      final connMessage = MqttConnectMessage()
          .withClientIdentifier(effectiveClientId)
          .startClean()
          .withWillTopic('healthkicks/v1/$deviceId/status')
          .withWillMessage(lwtPayload)
          .withWillQos(MqttQos.atLeastOnce);

      _client!.connectionMessage = connMessage;

      final status = await _client!.connect();
      _isConnected = status?.state == MqttConnectionState.connected;

      if (_isConnected) {
        log?.call('[MQTT] Connecté avec succès à AWS IoT Core en WebSockets.', isError: false);
        _subscribeToHapticCommands();
        await publishGatewayStatus(online: true);
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

  Future<bool> _connectLocalTcp(MqttLogCallback? log) async {
    log?.call('Tentative de connexion vers $brokerHost:$brokerPort (Client: $clientId)...', isError: false);

    _client = MqttServerClient.withPort(brokerHost, clientId, brokerPort);
    _client!.secure = (brokerPort == 8883);
    if (_client!.secure) {
      _client!.securityContext = securityContext ?? SecurityContext.defaultContext;
    }
    _client!.keepAlivePeriod = 30;
    _client!.autoReconnect = true;
    _client!.logging(on: false);

    final lwtPayload = jsonEncode({
      'device_id': deviceId,
      'state': 'offline',
      'gateway': 'mobile',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .withWillTopic('healthkicks/v1/$deviceId/status')
        .withWillMessage(lwtPayload)
        .withWillQos(MqttQos.atLeastOnce);

    _client!.connectionMessage = connMessage;

    try {
      final status = await _client!.connect();
      _isConnected = status?.state == MqttConnectionState.connected;

      if (_isConnected) {
        log?.call('Connecté avec succès au broker $brokerHost:$brokerPort.', isError: false);
        _subscribeToHapticCommands();
        await publishGatewayStatus(online: true);
      } else {
        log?.call(
          'Échec connexion broker $brokerHost:$brokerPort : statut ${status?.state}.',
          isError: true,
        );
      }
      return _isConnected;
    } catch (e) {
      _isConnected = false;
      String errorMsg = e.toString();
      if (e is SocketException) {
        final osErr = e.osError?.message ?? e.message;
        if (brokerPort == 1883) {
          errorMsg = 'SocketException: $osErr vers $brokerHost:$brokerPort. Vérifiez que Mosquitto est démarré sur le PC hôte avec listener 1883 0.0.0.0 (et pare-feu Windows ouvert).';
        } else {
          errorMsg = 'SocketException: $osErr vers $brokerHost:$brokerPort. Hôte inaccessible ou port fermé.';
        }
      } else if (e is HandshakeException) {
        errorMsg = 'HandshakeException: Échec négociation TLS/SSL sur port $brokerPort ($e). Vérifiez les certificats mTLS ou le SecurityContext pour AWS IoT Core.';
      } else {
        final str = e.toString();
        if (brokerPort == 1883 && (str.contains('refused') || str.contains('failed') || str.contains('OS Error'))) {
          errorMsg = 'Échec de connexion vers $brokerHost:$brokerPort : Vérifiez que Mosquitto est démarré sur le PC hôte avec listener 1883 0.0.0.0 ($str)';
        }
      }
      log?.call('Erreur MQTT : $errorMsg', isError: true);
      return false;
    }
  }

  void _subscribeToHapticCommands() {
    final topic = 'healthkicks/v1/$deviceId/commands/haptic';
    _client?.subscribe(topic, MqttQos.atLeastOnce);

    _client?.updates?.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      for (final msg in messages) {
        if (msg.topic == topic) {
          final recMessage = msg.payload as MqttPublishMessage;
          final payloadStr = MqttPublishPayload.bytesToStringAsString(
            recMessage.payload.message,
          );

          try {
            final jsonMap = jsonDecode(payloadStr) as Map<String, dynamic>;
            final command = HapticCommandModel.fromJson(jsonMap);
            _hapticCommandsController.add(command);
          } catch (_) {}
        }
      }
    });
  }

  /// Publie un événement de détection d'activité vers AWS IoT Core (QoS 1).
  Future<void> publishActivityDetection(ActivityDetectionModel detection) async {
    if (!_isConnected || _client == null) return;

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
    if (!_isConnected || _client == null) return;

    final topic = 'healthkicks/v1/$deviceId/telemetry/raw';
    final chunks = session.toMqttBatchPayloads(maxReadingsPerChunk: 500);

    for (final chunk in chunks) {
      final jsonString = jsonEncode(chunk);
      final builder = MqttClientPayloadBuilder();
      builder.addString(jsonString);

      _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    }
  }

  /// Publie le statut en ligne de la passerelle.
  Future<void> publishGatewayStatus({required bool online}) async {
    if (!_isConnected || _client == null) return;

    final topic = 'healthkicks/v1/$deviceId/status';
    final payload = jsonEncode({
      'device_id': deviceId,
      'state': online ? 'online' : 'offline',
      'gateway': 'mobile',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    final builder = MqttClientPayloadBuilder();
    builder.addString(payload);

    _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  void disconnect() {
    publishGatewayStatus(online: false);
    _client?.disconnect();
    _isConnected = false;
    _hapticCommandsController.close();
  }
}
