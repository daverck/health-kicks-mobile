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

/// Central coordinator ensuring transparent bidirectional routing BLE <-> MQTT
/// and initiating Studio sessions with the FastAPI Backend.
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
  StreamSubscription<String>? _studioStatusSub;

  final _studioSessionSavedController =
      StreamController<StudioSessionModel>.broadcast();

  /// Stream notifying the end of recording and synchronization of a Studio session.
  Stream<StudioSessionModel> get studioSessionSavedStream =>
      _studioSessionSavedController.stream;

  String? _currentStudioSessionId;
  String? _activeLocalSessionId;
  bool _isStudioRecordingActive = false;
  String? _currentStudioLabel;
  double _currentStudioStartTimestamp = 0;
  double _currentStudioDurationSec = 5.0;

  bool get isStudioRecordingActive => _isStudioRecordingActive;

  GatewayCoordinator({
    required this.bleClient,
    required this.mqttService,
    this.studioApiService,
    required this.deviceId,
    this.onLog,
  });

  /// Starts bidirectional routing between BLE and MQTT
  /// and notifies "online" presence status of the BLE device on AWS IoT Core if connected.
  void startRouting() {
    if (mqttService.isConnected) {
      unawaited(publishBleStatus(online: true));
    }

    // 1. Upstream relay: BLE Activity Detection -> Cloud MQTT
    _activitySub = bleClient.activityStream.listen((detection) async {
      await mqttService.publishActivityDetection(detection);
    });

    // 2. Downstream relay: Cloud MQTT Haptic Command -> BLE Footwear
    _hapticSub = mqttService.hapticCommandStream.listen((command) async {
      await bleClient.sendHapticCommand(command);
    });

    // 3. Downstream relay: Cloud MQTT Studio Start Command -> BLE Footwear
    _studioCommandSub = mqttService.studioCommandStream.listen((command) async {
      onLog?.call(
        '[GATEWAY] Remote Studio command received (session_id: ${command.sessionId}, label: ${command.label}, duration: ${command.durationSec}s)',
        isError: false,
      );
      await handleRemoteStudioCommand(command);
    });

    // 4. Listen to BLE Studio status (to release state on cancellation or error)
    _studioStatusSub = bleClient.studioStatusStream.listen((status) {
      if (status.startsWith('ERROR') || status == 'CANCELLED') {
        onLog?.call(
          '[GATEWAY] BLE Studio status received: $status -> Releasing capture state.',
          isError: status.startsWith('ERROR'),
        );
        _isStudioRecordingActive = false;
        _activeLocalSessionId = null;
        _currentStudioSessionId = null;
      }
    });

    // 5. Batch relay: Reassembled BLE Studio Data Burst -> Cloud MQTT DynamoDB
    _burstSub = bleClient.burstResultStream.listen((result) async {
      onLog?.call(
        '[GATEWAY] End-of-burst packet received: completed=${result.isCompleted}, '
        'CRC valid=${result.isCrcValid}, frames=${result.framesRecovered}/${result.totalAnnounced}',
        isError: !result.isSuccess,
      );

      if (result.readings.isEmpty) {
        onLog?.call(
          '[GATEWAY] No IMU samples contained in received burst.',
          isError: true,
        );
        return;
      }

      if (!result.isCrcValid) {
        onLog?.call(
          '[GATEWAY] CRC32 mismatch warning. The ${result.readings.length} received frames are still forwarded.',
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

      // MQTT publish towards DynamoDB
      try {
        onLog?.call(
          '[GATEWAY] Publishing session ${session.sessionId} (${session.readings.length} frames) to MQTT...',
          isError: false,
        );
        await mqttService.publishStudioSession(session);
        _studioSessionSavedController.add(session);
        onLog?.call(
          '[GATEWAY] Session ${session.sessionId} published successfully via MQTT.',
          isError: false,
        );
      } catch (e) {
        onLog?.call(
          '[GATEWAY] Error publishing to MQTT: $e',
          isError: true,
        );
      } finally {
        _currentStudioSessionId = null;
        _activeLocalSessionId = null;
        _isStudioRecordingActive = false;
      }
    });
  }

  /// Triggers a Studio session, reserves the session in PostgreSQL via the FastAPI backend
  /// REST API to obtain official UUID [sessionId], then commands footwear over BLE.
  Future<void> triggerStudioSession({
    required String label,
    required double durationSec,
    String? sessionId,
  }) async {
    if (_isStudioRecordingActive) {
      onLog?.call(
        '[GATEWAY] Studio session already recording. Local trigger ignored.',
        isError: false,
      );
      return;
    }

    _isStudioRecordingActive = true;
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

    _activeLocalSessionId = effectiveSessionId;
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

  /// Handles a Studio command triggered remotely from Web / Backend via MQTT.
  /// Strictly reuses the [session_id] already allocated and persisted by the backend in PostgreSQL,
  /// without issuing a redundant reservation REST call.
  Future<void> handleRemoteStudioCommand(StudioCommandModel command) async {
    // Check if capture is already active or if session ID matches locally started session
    if (_activeLocalSessionId == command.sessionId || _isStudioRecordingActive) {
      onLog?.call(
        '[GATEWAY] Studio session echo ignored (active session: ${command.sessionId})',
        isError: false,
      );
      return;
    }

    _isStudioRecordingActive = true;
    _currentStudioSessionId = command.sessionId;
    _currentStudioLabel = command.label;
    _currentStudioDurationSec = command.durationSec;
    _currentStudioStartTimestamp =
        DateTime.now().millisecondsSinceEpoch / 1000.0;

    onLog?.call(
      '[GATEWAY] Triggering BLE capture for remote command (session: ${command.sessionId})...',
      isError: false,
    );

    await bleClient.startStudioSession(
      label: command.label,
      durationSec: command.durationSec,
      sessionId: command.sessionId,
    );
  }

  /// Stops routing and optionally notifies "offline" status of BLE device on AWS IoT Core.
  void stopRouting({bool notifyOffline = true}) {
    _isStudioRecordingActive = false;
    if (notifyOffline) {
      unawaited(publishBleStatus(online: false));
    }
    _activitySub?.cancel();
    _activitySub = null;
    _hapticSub?.cancel();
    _hapticSub = null;
    _studioCommandSub?.cancel();
    _studioCommandSub = null;
    _studioStatusSub?.cancel();
    _studioStatusSub = null;
    _burstSub?.cancel();
    _burstSub = null;
  }

  /// Publishes BLE footwear presence status to device status topic.
  Future<void> publishBleStatus({required bool online}) async {
    if (!mqttService.isConnected) {
      onLog?.call(
        '[GATEWAY] Presence publishing ($deviceId -> ${online ? "online" : "offline"}) deferred: MQTT not connected.',
        isError: false,
      );
      return;
    }

    try {
      await mqttService.publishGatewayStatus(online: online);
      onLog?.call(
        '[GATEWAY] Device presence status ($deviceId): ${online ? "online" : "offline"}',
        isError: false,
      );
    } catch (e) {
      onLog?.call(
        '[GATEWAY] Error publishing device presence ($deviceId): $e',
        isError: false,
      );
    }
  }

  void dispose() {
    stopRouting();
    _studioSessionSavedController.close();
  }
}
