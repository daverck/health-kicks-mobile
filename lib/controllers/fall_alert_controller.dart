import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../models/activity_detection_model.dart';
import '../models/fall_alert_model.dart';
import '../services/location/fall_location_provider.dart';
import '../services/mqtt/mqtt_gateway_service.dart';
import '../services/sms/fall_sms_sender.dart';

const _uuid = Uuid();

typedef FallAlertLogCallback = void Function(String tag, String message, {bool isError});

/// Controller orchestrating the Fall Alerting lifecycle and native Android SMS relay on the mobile gateway.
/// Contract reference: contracts/fall_alerting.md v1.1 (Sections 2, 3 & 7.B)
class FallAlertController extends ChangeNotifier {
  final String deviceId;
  final FallLocationProvider locationProvider;
  final FallSmsSender smsSender;
  final int initialCountdownSeconds;
  final Future<bool> Function(FallAlertUplinkPayload payload)? onPublishUplink;
  final bool Function()? isMqttConnectedGetter;
  final Future<void> Function()? onCall112;
  final FallAlertLogCallback? onLog;

  MqttGatewayService? _mqttService;
  StreamSubscription<FallAlertStatusModel>? _statusSub;

  bool _isMqttConnected = false;
  String? _activeEventId;
  String? _state;
  bool _isAlertScreenVisible = false;
  int _remainingSeconds = 60;
  int _currentContactRank = 0;
  int _contactsTotal = 0;
  String? _acknowledgedByName;
  FallAlertLocation? _lastLocation;
  bool _isConfirmSent = false;
  Timer? _countdownTimer;
  bool _isDisposed = false;

  final Set<String> _processedSmsCommandKeys = {};
  final List<FallAlertUplinkPayload> _pendingReplayedPayloads = [];
  final List<FallAlertUplinkPayload> _publishedPayloads = [];

  FallAlertController({
    this.deviceId = 'HK-2',
    this.locationProvider = const DefaultFallLocationProvider(),
    this.smsSender = const MethodChannelFallSmsSender(),
    this.initialCountdownSeconds = 60,
    this.onPublishUplink,
    this.isMqttConnectedGetter,
    this.onCall112,
    this.onLog,
    MqttGatewayService? mqttService,
  }) : _remainingSeconds = initialCountdownSeconds {
    if (mqttService != null) {
      attachMqttService(mqttService);
    }
  }

  String? get activeEventId => _activeEventId;
  String? get state => _state;
  bool get isAlertScreenVisible => _isAlertScreenVisible;
  bool get isAlertActive => _state == 'PENDING' || _state == 'ESCALATING';
  int get remainingSeconds => _remainingSeconds;
  int get currentContactRank => _currentContactRank;
  int get contactsTotal => _contactsTotal;
  String? get acknowledgedByName => _acknowledgedByName;
  FallAlertLocation? get lastLocation => _lastLocation;
  bool get isConfirmSent => _isConfirmSent;

  List<FallAlertUplinkPayload> get pendingReplayedPayloads =>
      List.unmodifiable(_pendingReplayedPayloads);

  List<FallAlertUplinkPayload> get publishedPayloads =>
      List.unmodifiable(_publishedPayloads);

  bool get isMqttConnected {
    if (isMqttConnectedGetter != null) {
      return isMqttConnectedGetter!();
    }
    if (_mqttService != null) {
      return _mqttService!.isConnected || _isMqttConnected;
    }
    return _isMqttConnected;
  }

  /// Requests Android `SEND_SMS` runtime permission via [smsSender].
  Future<bool> requestSmsPermission() async {
    try {
      return await smsSender.requestSmsPermission();
    } catch (_) {
      return false;
    }
  }

  /// Binds this controller to an [MqttGatewayService] to publish uplink messages
  /// and subscribe to downlink status updates.
  void attachMqttService(MqttGatewayService? service) {
    _statusSub?.cancel();
    _statusSub = null;
    _mqttService = service;
    if (service != null) {
      _statusSub = service.fallAlertStatusStream.listen(onDownlinkStatusReceived);
      if (service.isConnected) {
        _isMqttConnected = true;
        unawaited(flushPendingReplayedPayloads());
      }
    }
  }

  /// Updates the known MQTT connection state and flushes any buffered replayed alerts.
  void setMqttConnected(bool connected) {
    _isMqttConnected = connected;
    if (connected) {
      unawaited(flushPendingReplayedPayloads());
    }
  }

  /// Flushes any replayed fall alerts buffered while MQTT was disconnected.
  Future<void> flushPendingReplayedPayloads() async {
    if (!isMqttConnected || _pendingReplayedPayloads.isEmpty) return;
    final items = List<FallAlertUplinkPayload>.from(_pendingReplayedPayloads);
    _pendingReplayedPayloads.clear();
    for (final item in items) {
      final ok = await _publishUplink(item);
      if (!ok) {
        _pendingReplayedPayloads.add(item);
      }
    }
  }

  /// Alias for [onActivityDetected].
  Future<void> handleActivityDetection(
    ActivityDetectionModel detection, {
    String? overrideDeviceId,
  }) =>
      onActivityDetected(detection, overrideDeviceId: overrideDeviceId);

  /// Processes a decoded BLE activity notification (`7a5a0002`).
  Future<void> onActivityDetected(
    ActivityDetectionModel detection, {
    String? overrideDeviceId,
  }) async {
    if (_isDisposed) return;

    // 1. Automatic cancellation on fall_recovery (0x13) while an alert is active
    if (detection.isFallRecovery) {
      if (isAlertActive && _activeEventId != null) {
        final eventId = _activeEventId!;
        _countdownTimer?.cancel();
        _state = 'CANCELLED';
        _isAlertScreenVisible = false;
        _activeEventId = null;
        _notifySafely();

        onLog?.call(
          'FALL_ALERT',
          'Relevage détecté (0x13) : annulation automatique de l\'alerte ($eventId).',
        );

        final cancelPayload = FallAlertUplinkPayload.cancel(
          eventId: eventId,
          cancelReason: 'fall_recovery',
        );
        await _publishUplink(cancelPayload);
      }
      return;
    }

    // 2. Check if this event represents a fall (bit 0 of flags or fall state codes)
    final isFallEvent = detection.isFall ||
        detection.stateCode == 0x10 ||
        detection.stateCode == 0x11 ||
        detection.stateCode == 0x12 ||
        detection.stateCode == 0x1F;

    if (!isFallEvent) return;

    final int detectedAtMs = detection.timestampEpochSec > 1000000000
        ? detection.timestampEpochSec * 1000
        : detection.effectiveTimestamp.toUtc().millisecondsSinceEpoch;
    final double confidence = (detection.confidencePercent / 100.0).clamp(0.0, 1.0);
    final String effectiveDeviceId = overrideDeviceId ?? deviceId;

    // 3. Offline-buffered (NVS bit 2) or MQTT disconnected -> delivery="replayed", no emergency UI
    if (detection.isOfflineBuffered || !isMqttConnected) {
      final replayedEventId = _uuid.v4();
      final replayedPayload = FallAlertUplinkPayload.detected(
        eventId: replayedEventId,
        deviceId: effectiveDeviceId,
        eventType: detection.eventType,
        confidence: confidence,
        detectedAt: detectedAtMs,
        delivery: 'replayed',
        location: null,
      );

      onLog?.call(
        'FALL_ALERT',
        'Chute hors-ligne/différée enregistrée en mode replayed ($replayedEventId) sans alerte email.',
      );

      if (isMqttConnected) {
        await _publishUplink(replayedPayload);
      } else {
        _pendingReplayedPayloads.add(replayedPayload);
      }
      _notifySafely();
      return;
    }

    // 4. Live fall in Active Surveillance
    if (isAlertActive && _activeEventId != null) {
      onLog?.call(
        'FALL_ALERT',
        'Chute détectée alors qu\'une alerte ($_activeEventId) est déjà active : ignorée (idempotence).',
      );
      return;
    }

    final liveEventId = _uuid.v4();
    _activeEventId = liveEventId;
    _state = 'PENDING';
    _remainingSeconds = initialCountdownSeconds;
    _isConfirmSent = false;
    _currentContactRank = 0;
    _contactsTotal = 0;
    _acknowledgedByName = null;
    _isAlertScreenVisible = true;
    _startCountdownTimer();
    _notifySafely();

    onLog?.call(
      'FALL_ALERT',
      'Chute détectée en direct ($liveEventId) : ouverture de l\'écran d\'urgence (60 s).',
    );

    final location = await locationProvider.getCurrentLocation(
      timeout: const Duration(seconds: 3),
    );
    _lastLocation = location;

    final livePayload = FallAlertUplinkPayload.detected(
      eventId: liveEventId,
      deviceId: effectiveDeviceId,
      eventType: detection.eventType,
      confidence: confidence,
      detectedAt: detectedAtMs,
      delivery: 'live',
      location: location,
    );

    await _publishUplink(livePayload);
  }

  /// Triggered when the user taps "Je vais bien (Annuler l'alerte)".
  Future<void> cancelByUser() async {
    if (_isDisposed) return;
    _countdownTimer?.cancel();
    final eventId = _activeEventId;
    _state = 'CANCELLED';
    _isAlertScreenVisible = false;
    _activeEventId = null;
    _notifySafely();

    if (eventId != null && eventId.isNotEmpty) {
      onLog?.call(
        'FALL_ALERT',
        'Alerte annulée par l\'utilisateur ($eventId).',
      );
      final payload = FallAlertUplinkPayload.cancel(
        eventId: eventId,
        cancelReason: 'user_cancel',
      );
      await _publishUplink(payload);
    }
  }

  /// Triggered when the user taps "J'ai besoin d'aide maintenant" during `PENDING`.
  Future<void> confirmEmergencyNow() async {
    if (_isDisposed) return;
    final eventId = _activeEventId;
    if (eventId == null || _state != 'PENDING') return;

    _countdownTimer?.cancel();
    _isConfirmSent = true;
    _state = 'ESCALATING';
    _remainingSeconds = 0;
    _notifySafely();

    onLog?.call(
      'FALL_ALERT',
      'Demande d\'aide immédiate confirmée par l\'utilisateur ($eventId).',
    );

    final location = _lastLocation ??
        await locationProvider.getCurrentLocation(
          timeout: const Duration(seconds: 2),
        );
    _lastLocation = location;

    final payload = FallAlertUplinkPayload.confirm(
      eventId: eventId,
      location: location,
    );
    await _publishUplink(payload);
  }

  /// Handles downlink status messages from `healthkicks/v1/users/{user_id}/fall-alert/status`.
  void onDownlinkStatusReceived(FallAlertStatusModel status) {
    if (_isDisposed) return;

    final normalizedState = status.state.toUpperCase();

    // 1. Process embedded SMS command if present and not yet handled (idempotence)
    if (status.smsCommand != null) {
      final cmd = status.smsCommand!;
      final smsKey = cmd.notificationId != null
          ? 'notif:${cmd.notificationId}'
          : 'event:${status.eventId}';
      if (!_processedSmsCommandKeys.contains(smsKey)) {
        _processedSmsCommandKeys.add(smsKey);
        unawaited(_handleSmsCommand(status.eventId, cmd));
      }
    }

    // 2. TEST_SMS downlinks must NEVER modify active alert state or open the emergency screen
    if (normalizedState == 'TEST_SMS' || status.stateEnum == FallAlertState.testSms) {
      return;
    }

    // 3. Ignore stale updates for a different alert when one is currently active
    if (_activeEventId != null &&
        status.eventId.isNotEmpty &&
        status.eventId != _activeEventId) {
      return;
    }

    if (_activeEventId == null && status.eventId.isNotEmpty) {
      _activeEventId = status.eventId;
    }

    onLog?.call(
      'FALL_ALERT',
      'Statut downlink reçu : $normalizedState (rang: ${status.currentContactRank}/${status.contactsTotal})',
    );

    switch (normalizedState) {
      case 'PENDING':
        _state = 'PENDING';
        _isAlertScreenVisible = true;
        if (status.nextActionAt != null) {
          final diffSec = status.nextActionAt!
              .difference(DateTime.now().toUtc())
              .inSeconds;
          if (diffSec > 0 && diffSec <= initialCountdownSeconds) {
            _remainingSeconds = diffSec;
          }
        }
        if (_countdownTimer == null || !_countdownTimer!.isActive) {
          _startCountdownTimer();
        }
        _notifySafely();
        break;

      case 'ESCALATING':
        _countdownTimer?.cancel();
        _state = 'ESCALATING';
        _remainingSeconds = 0;
        if (status.currentContactRank != null) {
          _currentContactRank = status.currentContactRank!;
        }
        if (status.contactsTotal != null) {
          _contactsTotal = status.contactsTotal!;
        }
        _isAlertScreenVisible = true;
        _notifySafely();
        break;

      case 'ACKNOWLEDGED':
        _countdownTimer?.cancel();
        _state = 'ACKNOWLEDGED';
        _remainingSeconds = 0;
        if (status.acknowledgedBy != null &&
            status.acknowledgedBy!.firstName.isNotEmpty) {
          _acknowledgedByName = status.acknowledgedBy!.firstName;
        }
        _isAlertScreenVisible = true;
        _notifySafely();
        break;

      case 'EXHAUSTED':
        _countdownTimer?.cancel();
        _state = 'EXHAUSTED';
        _remainingSeconds = 0;
        if (status.contactsTotal != null) {
          _contactsTotal = status.contactsTotal!;
        }
        _isAlertScreenVisible = true;
        _notifySafely();
        break;

      case 'CANCELLED':
      case 'SUPPRESSED':
        _countdownTimer?.cancel();
        _state = normalizedState;
        _isAlertScreenVisible = false;
        _activeEventId = null;
        _notifySafely();
        break;
    }
  }

  Future<void> _handleSmsCommand(String eventId, FallAlertSmsCommand cmd) async {
    onLog?.call(
      'FALL_ALERT',
      'Envoi SMS (${cmd.isTest ? "TEST" : "URGENCE"}) vers ${cmd.recipientPhone} (${cmd.contactFirstName})...',
    );

    final result = await smsSender.sendSms(
      phone: cmd.recipientPhone,
      message: cmd.message,
    );

    if (result.success) {
      onLog?.call(
        'FALL_ALERT',
        'SMS remis au modem GSM Android pour ${cmd.contactFirstName}.',
      );
    } else {
      onLog?.call(
        'FALL_ALERT',
        'Échec envoi SMS pour ${cmd.contactFirstName} : ${result.errorMessage ?? "erreur inconnue"}',
        isError: true,
      );
    }

    if (!cmd.isTest && cmd.notificationId != null) {
      final statusPayload = FallAlertUplinkPayload.smsStatus(
        eventId: eventId,
        notificationId: cmd.notificationId!,
        sent: result.success,
        errorMessage: result.success ? null : result.errorMessage,
      );
      await _publishUplink(statusPayload);
    }
  }

  /// Dismisses the alert screen once the alert is acknowledged or finished.
  void dismissAlertScreen() {
    if (_isDisposed) return;
    _countdownTimer?.cancel();
    _isAlertScreenVisible = false;
    _activeEventId = null;
    _notifySafely();
  }

  /// Opens the phone dialer to emergency number 112.
  Future<void> callEmergency112() async {
    onLog?.call('FALL_ALERT', 'Ouverture du composeur d\'urgence 112...');
    if (onCall112 != null) {
      await onCall112!();
      return;
    }
    final uri = Uri(scheme: 'tel', path: '112');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isDisposed || _state != 'PENDING') {
        timer.cancel();
        return;
      }
      if (_remainingSeconds > 1) {
        _remainingSeconds--;
        _notifySafely();
      } else {
        // Local safety net after 60s if backend downlink hasn't arrived yet
        _remainingSeconds = 0;
        _state = 'ESCALATING';
        timer.cancel();
        _notifySafely();
      }
    });
  }

  Future<bool> _publishUplink(FallAlertUplinkPayload payload) async {
    _publishedPayloads.add(payload);
    if (onPublishUplink != null) {
      return await onPublishUplink!(payload);
    }
    if (_mqttService != null) {
      return await _mqttService!.publishFallAlertEvent(payload);
    }
    return false;
  }

  void _notifySafely() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _countdownTimer?.cancel();
    _statusSub?.cancel();
    super.dispose();
  }
}
