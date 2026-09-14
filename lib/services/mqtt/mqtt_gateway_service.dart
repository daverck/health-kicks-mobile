import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../../models/activity_detection_model.dart';
import '../../models/haptic_command_model.dart';
import '../../models/studio_session_model.dart';

/// Service de passerelle MQTT vers AWS IoT Core.
/// Référence contractuelle : contracts/README.md (Section 3 : Contrats MQTT IoT)
class MqttGatewayService {
  final String brokerHost;
  final int brokerPort;
  final String deviceId;
  final String clientId;
  final SecurityContext? securityContext;

  MqttServerClient? _client;
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  final _hapticCommandsController = StreamController<HapticCommandModel>.broadcast();
  Stream<HapticCommandModel> get hapticCommandStream => _hapticCommandsController.stream;

  MqttGatewayService({
    required this.brokerHost,
    this.brokerPort = 8883,
    required this.deviceId,
    String? clientId,
    this.securityContext,
  }) : clientId = clientId ?? 'HealthKicks-Mobile-GW-$deviceId';

  /// Établit la liaison MQTT over TLS avec AWS IoT Core.
  Future<bool> connect() async {
    _client = MqttServerClient.withPort(brokerHost, clientId, brokerPort);
    _client!.secure = (brokerPort == 8883);
    if (_client!.secure) {
      _client!.securityContext = securityContext ?? SecurityContext.defaultContext;
    }
    _client!.keepAlivePeriod = 30;
    _client!.autoReconnect = true;
    _client!.logging(on: false);

    // Configuration du Last Will and Testament (LWT)
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
        _subscribeToHapticCommands();
        await publishGatewayStatus(online: true);
      }
      return _isConnected;
    } catch (e) {
      _isConnected = false;
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
