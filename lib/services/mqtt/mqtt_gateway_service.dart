import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../../core/aws/sigv4_signer.dart';
import '../../models/activity_detection_model.dart';
import '../../models/fall_alert_model.dart';
import '../../models/haptic_command_model.dart';
import '../../models/studio_command_model.dart';
import '../../models/studio_session_model.dart';
import '../auth/iot_credentials_repository.dart';
import '../auth/token_storage_service.dart';

typedef MqttLogCallback = void Function(String message, {bool isError});

/// Dedicated MQTT gateway service to AWS IoT Core (WSS SigV4 Port 443).
/// Contract reference: contracts/README.md (Section 3: IoT MQTT Contracts) & contracts/fall_alerting.md
class MqttGatewayService {
  final String deviceId;
  final String? userId;
  final String clientId;
  final IotCredentialsRepository credentialsRepository;
  final MqttLogCallback? onLog;
  final VoidCallback? onConnectionRestored;

  MqttServerClient? _client;
  String? _effectiveUserId;
  bool _isConnected = false;
  bool get isConnected =>
      _isConnected &&
      _client != null &&
      _client!.connectionStatus?.state == MqttConnectionState.connected;

  String? get effectiveUserId =>
      (_effectiveUserId != null && _effectiveUserId!.isNotEmpty)
          ? _effectiveUserId
          : userId;

  final _hapticCommandsController = StreamController<HapticCommandModel>.broadcast();
  Stream<HapticCommandModel> get hapticCommandStream => _hapticCommandsController.stream;

  final _studioCommandsController = StreamController<StudioCommandModel>.broadcast();
  Stream<StudioCommandModel> get studioCommandStream => _studioCommandsController.stream;

  final _fallAlertStatusController = StreamController<FallAlertStatusModel>.broadcast();
  Stream<FallAlertStatusModel> get fallAlertStatusStream => _fallAlertStatusController.stream;

  StreamSubscription? _updatesSub;

  /// Generates a cryptographically random 8-character hexadecimal nonce for MQTT session scoping.
  static String generateSessionNonce() {
    final rand = Random.secure();
    final bytes = List<int>.generate(4, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  MqttGatewayService({
    required this.deviceId,
    this.userId,
    required this.credentialsRepository,
    String? clientId,
    this.onLog,
    this.onConnectionRestored,
  }) : clientId = clientId ??
            (userId != null && userId.isNotEmpty
                ? 'healthkicks-mobile-$userId-${generateSessionNonce()}'
                : '');

  /// Establishes secure MQTT connection to AWS IoT Core via WebSockets SigV4 on port 443.
  Future<bool> connect({MqttLogCallback? onLog}) async {
    final log = onLog ?? this.onLog;

    // 1. Clean up cleanly before any new connect() invocation
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

    log?.call('Fetching STS credentials from backend...', isError: false);

    try {
      final creds = await credentialsRepository.fetchCredentials(deviceId: deviceId);
      log?.call(
        'Valid STS credentials obtained (Expires at: ${creds.expiration.toIso8601String()}, Region: ${creds.region})',
        isError: false,
      );

      final signedWssUrl = SigV4Signer.buildSignedWebSocketUrl(credentials: creds);
      log?.call(
        'SigV4 signature generated, connecting via WSS 443 to AWS IoT Core (${creds.iotEndpoint})...',
        isError: false,
      );

      var resolvedUserId = (userId != null && userId!.isNotEmpty) ? userId! : '';
      if (resolvedUserId.isEmpty && creds.userId != null && creds.userId!.isNotEmpty) {
        resolvedUserId = creds.userId!;
      }
      if (resolvedUserId.isEmpty) {
        try {
          final tokenStorage = credentialsRepository.tokenStorage ?? TokenStorageService();
          final tokenUserId = await tokenStorage.getUserIdFromToken();
          if (tokenUserId != null && tokenUserId.isNotEmpty) {
            resolvedUserId = tokenUserId;
          }
        } catch (_) {}
      }
      if (resolvedUserId.isEmpty || resolvedUserId == 'unknown') {
        log?.call(
          'Connection rejected: no valid userId or session unresolved. Aborting to preserve multi-tenant isolation.',
          isError: true,
        );
        return false;
      }

      _effectiveUserId = resolvedUserId;

      final effectiveClientId = (clientId.isNotEmpty &&
              (clientId.startsWith('healthkicks-mobile-$resolvedUserId') ||
                  clientId.startsWith('healthkicks-session-$resolvedUserId')))
          ? clientId
          : 'healthkicks-mobile-$resolvedUserId-${generateSessionNonce()}';

      final lwtTopic = 'healthkicks/v1/users/$resolvedUserId/gateway-status';
      final lwtPayload = jsonEncode({
        'user_id': resolvedUserId,
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
        log?.call('WebSocket connected to AWS IoT Core.', isError: false);
        onConnectionRestored?.call();
      };
      _client!.onDisconnected = () {
        _isConnected = false;
        log?.call('WebSocket disconnected from AWS IoT Core.', isError: true);
      };
      _client!.onAutoReconnect = () {
        _isConnected = false;
        log?.call('Automatic MQTT reconnection in progress...', isError: false);
      };
      _client!.onAutoReconnected = () {
        _isConnected = true;
        log?.call('Automatic MQTT reconnection succeeded.', isError: false);
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
        log?.call('Connected successfully to AWS IoT Core via SigV4 WebSockets.', isError: false);
        _subscribeToCommands();
      } else {
        log?.call(
          'AWS IoT Core WSS connection failed: status ${status?.state}.',
          isError: true,
        );
      }
      return _isConnected;
    } catch (e) {
      _isConnected = false;
      log?.call('WebSocket error: $e', isError: true);
      return false;
    }
  }

  void _resubscribeTopics() {
    final log = onLog;
    final hapticTopic = 'healthkicks/v1/$deviceId/commands/haptic';
    final studioStartTopic = 'healthkicks/v1/$deviceId/commands/studio/start';
    final uid = effectiveUserId;

    _client?.subscribe(hapticTopic, MqttQos.atLeastOnce);
    _client?.subscribe(studioStartTopic, MqttQos.atLeastOnce);
    if (uid != null && uid.isNotEmpty) {
      final fallStatusTopic = 'healthkicks/v1/users/$uid/fall-alert/status';
      _client?.subscribe(fallStatusTopic, MqttQos.atLeastOnce);
      log?.call(
        'Subscriptions renewed after auto-reconnect: $hapticTopic, $studioStartTopic & $fallStatusTopic',
        isError: false,
      );
    } else {
      log?.call('Subscriptions renewed after auto-reconnect: $hapticTopic & $studioStartTopic', isError: false);
    }
  }

  void _subscribeToCommands() {
    final log = onLog;
    final hapticTopic = 'healthkicks/v1/$deviceId/commands/haptic';
    final studioStartTopic = 'healthkicks/v1/$deviceId/commands/studio/start';
    final uid = effectiveUserId;

    _client?.subscribe(hapticTopic, MqttQos.atLeastOnce);
    _client?.subscribe(studioStartTopic, MqttQos.atLeastOnce);
    if (uid != null && uid.isNotEmpty) {
      final fallStatusTopic = 'healthkicks/v1/users/$uid/fall-alert/status';
      _client?.subscribe(fallStatusTopic, MqttQos.atLeastOnce);
      log?.call('Active subscriptions: $hapticTopic, $studioStartTopic & $fallStatusTopic', isError: false);
    } else {
      log?.call('Active subscriptions: $hapticTopic & $studioStartTopic', isError: false);
    }

    _updatesSub?.cancel();
    _updatesSub = _client?.updates?.listen((List<MqttReceivedMessage<MqttMessage>> messages) {
      for (final msg in messages) {
        final recMessage = msg.payload as MqttPublishMessage;
        final payloadStr = MqttPublishPayload.bytesToStringAsString(
          recMessage.payload.message,
        );
        handleIncomingPayload(msg.topic, payloadStr);
      }
    });
  }

  /// Processes an incoming MQTT message payload on [topic] and dispatches to the corresponding stream.
  @visibleForTesting
  void handleIncomingPayload(String topic, String payloadStr) {
    final log = onLog;
    final hapticTopic = 'healthkicks/v1/$deviceId/commands/haptic';
    final studioStartTopic = 'healthkicks/v1/$deviceId/commands/studio/start';
    final uid = effectiveUserId;
    final fallStatusTopic = (uid != null && uid.isNotEmpty)
        ? 'healthkicks/v1/users/$uid/fall-alert/status'
        : null;

    if (topic == hapticTopic) {
      try {
        final jsonMap = jsonDecode(payloadStr) as Map<String, dynamic>;
        final command = HapticCommandModel.fromJson(jsonMap);
        _hapticCommandsController.add(command);
      } catch (e) {
        log?.call('Error decoding haptic command: $e', isError: true);
      }
    } else if (topic == studioStartTopic || topic.endsWith('/commands/studio/start')) {
      try {
        final jsonMap = jsonDecode(payloadStr) as Map<String, dynamic>;
        final command = StudioCommandModel.fromJson(jsonMap);
        log?.call(
          'Remote Studio command received (session: ${command.sessionId}, label: ${command.label}, duration: ${command.durationSec}s)',
          isError: false,
        );
        _studioCommandsController.add(command);
      } catch (e) {
        log?.call('Error decoding remote Studio command: $e', isError: true);
      }
    } else if ((fallStatusTopic != null && topic == fallStatusTopic) ||
        topic.endsWith('/fall-alert/status')) {
      try {
        final jsonMap = jsonDecode(payloadStr) as Map<String, dynamic>;
        final statusModel = FallAlertStatusModel.fromJson(jsonMap);
        log?.call(
          'Fall alert status received (event: ${statusModel.eventId}, state: ${statusModel.state})',
          isError: false,
        );
        _fallAlertStatusController.add(statusModel);
      } catch (e) {
        log?.call('Error decoding fall alert status: $e', isError: true);
      }
    }
  }

  /// Publishes a fall alert lifecycle event (`DETECTED`, `CONFIRM`, `CANCEL`) to AWS IoT Core (QoS 1).
  /// Topic: `healthkicks/v1/users/{user_id}/events/fall-alert`
  Future<bool> publishFallAlert(
    FallAlertUplinkPayload payload, {
    String? targetUserId,
  }) async {
    final log = onLog;
    final uid = targetUserId ?? effectiveUserId;

    if (!isConnected || _client == null || uid == null || uid.isEmpty) {
      log?.call(
        'Unable to publish fall alert (${payload.action}): MQTT not connected or userId missing.',
        isError: false,
      );
      return false;
    }

    try {
      final topic = 'healthkicks/v1/users/$uid/events/fall-alert';
      final jsonString = jsonEncode(payload.toJson());

      final builder = MqttClientPayloadBuilder();
      builder.addString(jsonString);

      _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
      log?.call(
        'Fall alert published to $topic: ${payload.action} (event_id: ${payload.eventId})',
        isError: false,
      );
      return true;
    } catch (e) {
      log?.call('Error publishing fall alert: $e', isError: true);
      return false;
    }
  }

  /// Publishes an activity detection event to AWS IoT Core (QoS 1).
  Future<void> publishActivityDetection(ActivityDetectionModel detection) async {
    final log = onLog;

    if (!isConnected || _client == null) {
      log?.call('Unable to publish detection: MQTT not connected.', isError: false);
      return;
    }

    try {
      final topic = 'healthkicks/v1/$deviceId/events/detection';
      final payload = detection.toMqttPayload(deviceId);
      final jsonString = jsonEncode(payload);

      final builder = MqttClientPayloadBuilder();
      builder.addString(jsonString);

      _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
      log?.call(
        'Activity detection published to $topic: ${detection.eventType.toUpperCase()} (${detection.confidencePercent}%)',
        isError: false,
      );
    } catch (e) {
      log?.call('Error publishing detection: $e', isError: true);
    }
  }

  /// Publishes reassembled Studio sessions to DynamoDB via AWS IoT Core (QoS 1).
  /// Ensures each batch stays under the 128 KB AWS limit.
  Future<void> publishStudioSession(StudioSessionModel session) async {
    final log = onLog;

    // 1. Check connection and attempt automatic reconnection if needed
    if (!isConnected || _client == null) {
      log?.call(
        'Client disconnected during Studio publish. Attempting auto-reconnect...',
        isError: false,
      );
      final connected = await connect(onLog: log);
      if (!connected) {
        log?.call(
          'MQTT reconnection failed: unable to publish Studio data.',
          isError: true,
        );
        return;
      }
    }

    if (session.readings.isEmpty) {
      log?.call(
        'Warning: empty Studio session (0 samples). No batches to publish.',
        isError: true,
      );
      return;
    }

    final topic = 'healthkicks/v1/$deviceId/telemetry/raw';
    final chunks = session.toMqttBatchPayloads(maxReadingsPerChunk: 500);

    log?.call(
      'Starting Studio publish (${session.readings.length} frames on $topic across ${chunks.length} batch(es))...',
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
          'Batch ${i + 1}/${chunks.length} published successfully ($readingCount frames)',
          isError: false,
        );
      } catch (e) {
        log?.call(
          'Error publishing batch ${i + 1}/${chunks.length}: $e',
          isError: true,
        );
      }
    }
  }

  /// Publishes single BLE device presence status to AWS IoT Core.
  Future<void> publishDeviceStatus({required bool online, String? targetDeviceId}) async {
    final effectiveDeviceId = targetDeviceId ?? deviceId;
    final log = onLog;

    if (!isConnected || _client == null) {
      log?.call(
        'Device presence status ($effectiveDeviceId -> ${online ? "online" : "offline"}) ignored: MQTT client not connected (state: ${_client?.connectionStatus?.state}).',
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
        'Device presence status ($effectiveDeviceId -> ${online ? "online" : "offline"}) published successfully to $topic',
        isError: false,
      );
    } catch (e) {
      log?.call(
        'Error publishing device presence ($effectiveDeviceId): $e',
        isError: false,
      );
    }
  }

  /// Publishes online status of gateway / device (alias).
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
    _fallAlertStatusController.close();
  }
}
