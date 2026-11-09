import 'dart:async';

import '../models/fall_alert_model.dart';
import '../services/sms/fall_sms_sender.dart';

typedef FallAlertLogCallback = void Function(String tag, String message, {bool isError});

/// Coordinator orchestrating native Android SMS relay, deduplication, and uplink status reporting.
/// Contract reference: contracts/fall_alerting.md v1.1 (Section 7.B)
class FallSmsRelayCoordinator {
  final FallSmsSender smsSender;
  final FallAlertLogCallback? onLog;
  final Future<void> Function(int notificationId, bool sent, String? errorMessage)? onSmsStatusReported;

  final Set<String> _processedSmsCommandKeys = {};

  FallSmsRelayCoordinator({
    this.smsSender = const MethodChannelFallSmsSender(),
    this.onLog,
    this.onSmsStatusReported,
  });

  Set<String> get processedSmsCommandKeys => Set.unmodifiable(_processedSmsCommandKeys);

  /// Requests Android `SEND_SMS` runtime permission via [smsSender].
  Future<bool> requestSmsPermission() async {
    try {
      return await smsSender.requestSmsPermission();
    } catch (_) {
      return false;
    }
  }

  /// Processes downlink SMS command if not already executed (ensuring idempotency).
  void handleDownlinkSmsCommand({
    required String eventId,
    required FallAlertSmsCommand cmd,
    required Future<bool> Function(FallAlertUplinkPayload payload) publishUplink,
    required void Function(FallAlertUplinkPayload payload) enqueuePendingPayload,
  }) {
    final smsKey = cmd.notificationId != null
        ? 'notif:${cmd.notificationId}'
        : 'event:$eventId';

    if (_processedSmsCommandKeys.contains(smsKey)) {
      return;
    }

    _processedSmsCommandKeys.add(smsKey);
    unawaited(_executeSmsCommand(
      eventId: eventId,
      cmd: cmd,
      publishUplink: publishUplink,
      enqueuePendingPayload: enqueuePendingPayload,
    ));
  }

  Future<void> _executeSmsCommand({
    required String eventId,
    required FallAlertSmsCommand cmd,
    required Future<bool> Function(FallAlertUplinkPayload payload) publishUplink,
    required void Function(FallAlertUplinkPayload payload) enqueuePendingPayload,
  }) async {
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

      final ok = await publishUplink(statusPayload);
      if (!ok) {
        onLog?.call(
          'FALL_ALERT',
          'Échec publication MQTT SMS_STATUS (notif #${cmd.notificationId}), mise en file d\'attente.',
          isError: true,
        );
        enqueuePendingPayload(statusPayload);
      } else {
        onLog?.call(
          'FALL_ALERT',
          'Rapport SMS_STATUS (${result.success ? "SENT" : "FAILED"}) notif #${cmd.notificationId} publié avec succès via MQTT.',
        );
      }

      if (onSmsStatusReported != null) {
        try {
          await onSmsStatusReported!(
            cmd.notificationId!,
            result.success,
            result.errorMessage,
          );
        } catch (e) {
          onLog?.call(
            'FALL_ALERT',
            'Échec du signalement REST direct de l\'état SMS : $e',
            isError: true,
          );
        }
      }
    }
  }

  void reset() {
    _processedSmsCommandKeys.clear();
  }
}
