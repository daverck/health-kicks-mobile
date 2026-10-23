/// Models for the Fall Alerting MQTT Uplink and Downlink contracts (v1.1).
/// Contract reference: contracts/fall_alerting.md (Section 3: Contrats MQTT IoT)
enum FallAlertState {
  pending('PENDING'),
  escalating('ESCALATING'),
  acknowledged('ACKNOWLEDGED'),
  cancelled('CANCELLED'),
  exhausted('EXHAUSTED'),
  suppressed('SUPPRESSED'),
  testSms('TEST_SMS');

  final String value;
  const FallAlertState(this.value);

  static FallAlertState fromString(String raw) {
    final normalized = raw.trim().toUpperCase();
    for (final state in FallAlertState.values) {
      if (state.value == normalized) return state;
    }
    return FallAlertState.pending;
  }
}

enum FallAlertAction {
  detected('DETECTED'),
  confirm('CONFIRM'),
  cancel('CANCEL'),
  smsStatus('SMS_STATUS');

  final String value;
  const FallAlertAction(this.value);

  static FallAlertAction fromString(String raw) {
    final normalized = raw.trim().toUpperCase();
    for (final action in FallAlertAction.values) {
      if (action.value == normalized) return action;
    }
    return FallAlertAction.detected;
  }
}

class FallAlertLocation {
  final double lat;
  final double lon;
  final double accuracyM;
  final int capturedAt;

  const FallAlertLocation({
    required this.lat,
    required this.lon,
    required this.accuracyM,
    required this.capturedAt,
  });

  factory FallAlertLocation.fromJson(Map<String, dynamic> json) {
    final rawCapturedAt = json['captured_at'];
    int capturedAtMs;
    if (rawCapturedAt is int) {
      capturedAtMs = rawCapturedAt;
    } else if (rawCapturedAt is num) {
      capturedAtMs = rawCapturedAt.toInt();
    } else if (rawCapturedAt is String) {
      capturedAtMs = DateTime.tryParse(rawCapturedAt)?.toUtc().millisecondsSinceEpoch ?? 0;
    } else {
      capturedAtMs = 0;
    }

    return FallAlertLocation(
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      accuracyM: (json['accuracy_m'] as num?)?.toDouble() ?? 0.0,
      capturedAt: capturedAtMs,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lat': lat,
      'lon': lon,
      'accuracy_m': accuracyM,
      'captured_at': capturedAt,
    };
  }
}

/// SMS relay command embedded in a Downlink status payload (`sms_command`).
class FallAlertSmsCommand {
  final int? notificationId;
  final int? contactId;
  final String contactFirstName;
  final String recipientPhone;
  final String message;
  final bool isTest;

  const FallAlertSmsCommand({
    this.notificationId,
    this.contactId,
    required this.contactFirstName,
    required this.recipientPhone,
    required this.message,
    this.isTest = false,
  });

  factory FallAlertSmsCommand.fromJson(Map<String, dynamic> json) {
    return FallAlertSmsCommand(
      notificationId: (json['notification_id'] as num?)?.toInt(),
      contactId: (json['contact_id'] as num?)?.toInt(),
      contactFirstName: json['contact_first_name'] as String? ?? '',
      recipientPhone: json['recipient_phone'] as String? ?? '',
      message: json['message'] as String? ?? '',
      isTest: json['is_test'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'notification_id': notificationId,
      'contact_id': contactId,
      'contact_first_name': contactFirstName,
      'recipient_phone': recipientPhone,
      'message': message,
      'is_test': isTest,
    };
  }
}

/// Uplink payload published by mobile on `healthkicks/v1/users/{user_id}/events/fall-alert`.
class FallAlertUplinkPayload {
  final String eventId;
  final String action; // 'DETECTED' | 'CONFIRM' | 'CANCEL' | 'SMS_STATUS'
  final String? deviceId;
  final String? eventType;
  final double? confidence;
  final int? detectedAt;
  final String? delivery; // 'live' | 'replayed'
  final FallAlertLocation? location;
  final String? cancelReason; // 'user_cancel' | 'fall_recovery'
  final int? notificationId;
  final String? smsStatus; // 'SENT' | 'FAILED'
  final String? errorMessage;
  final int sentAt;

  const FallAlertUplinkPayload({
    required this.eventId,
    required this.action,
    this.deviceId,
    this.eventType,
    this.confidence,
    this.detectedAt,
    this.delivery,
    this.location,
    this.cancelReason,
    this.notificationId,
    this.smsStatus,
    this.errorMessage,
    required this.sentAt,
  });

  FallAlertAction get actionEnum => FallAlertAction.fromString(action);

  factory FallAlertUplinkPayload.detected({
    required String eventId,
    required String deviceId,
    required String eventType,
    required double confidence,
    required int detectedAt,
    required String delivery,
    FallAlertLocation? location,
    int? sentAt,
  }) {
    return FallAlertUplinkPayload(
      eventId: eventId,
      action: FallAlertAction.detected.value,
      deviceId: deviceId,
      eventType: eventType,
      confidence: confidence,
      detectedAt: detectedAt,
      delivery: delivery,
      location: location,
      sentAt: sentAt ?? DateTime.now().toUtc().millisecondsSinceEpoch,
    );
  }

  factory FallAlertUplinkPayload.confirm({
    required String eventId,
    FallAlertLocation? location,
    int? sentAt,
  }) {
    return FallAlertUplinkPayload(
      eventId: eventId,
      action: FallAlertAction.confirm.value,
      location: location,
      sentAt: sentAt ?? DateTime.now().toUtc().millisecondsSinceEpoch,
    );
  }

  factory FallAlertUplinkPayload.cancel({
    required String eventId,
    required String cancelReason,
    int? sentAt,
  }) {
    return FallAlertUplinkPayload(
      eventId: eventId,
      action: FallAlertAction.cancel.value,
      cancelReason: cancelReason,
      sentAt: sentAt ?? DateTime.now().toUtc().millisecondsSinceEpoch,
    );
  }

  factory FallAlertUplinkPayload.smsStatus({
    required String eventId,
    required int notificationId,
    required bool sent,
    String? errorMessage,
    int? sentAt,
  }) {
    return FallAlertUplinkPayload(
      eventId: eventId,
      action: FallAlertAction.smsStatus.value,
      notificationId: notificationId,
      smsStatus: sent ? 'SENT' : 'FAILED',
      errorMessage: errorMessage,
      sentAt: sentAt ?? DateTime.now().toUtc().millisecondsSinceEpoch,
    );
  }

  factory FallAlertUplinkPayload.fromJson(Map<String, dynamic> json) {
    final locRaw = json['location'];
    return FallAlertUplinkPayload(
      eventId: json['event_id'] as String? ?? '',
      action: json['action'] as String? ?? 'DETECTED',
      deviceId: json['device_id'] as String?,
      eventType: json['event_type'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble(),
      detectedAt: (json['detected_at'] as num?)?.toInt(),
      delivery: json['delivery'] as String?,
      location: locRaw is Map<String, dynamic> ? FallAlertLocation.fromJson(locRaw) : null,
      cancelReason: json['cancel_reason'] as String?,
      notificationId: (json['notification_id'] as num?)?.toInt(),
      smsStatus: json['sms_status'] as String?,
      errorMessage: json['error_message'] as String?,
      sentAt: (json['sent_at'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'event_id': eventId,
      'action': action,
    };
    if (deviceId != null) {
      map['device_id'] = deviceId;
    }
    if (eventType != null) {
      map['event_type'] = eventType;
    }
    if (confidence != null) {
      map['confidence'] = confidence;
    }
    if (detectedAt != null) {
      map['detected_at'] = detectedAt;
    }
    if (delivery != null) {
      map['delivery'] = delivery;
    }
    if (action == 'DETECTED' || location != null) {
      map['location'] = location?.toJson();
    }
    if (cancelReason != null) {
      map['cancel_reason'] = cancelReason;
    }
    if (action == 'SMS_STATUS' || notificationId != null || smsStatus != null) {
      map['notification_id'] = notificationId;
      map['sms_status'] = smsStatus;
      map['error_message'] = errorMessage;
    }
    map['sent_at'] = sentAt;
    return map;
  }
}

/// Information about the emergency contact who acknowledged the fall alert.
class FallAlertAcknowledgedBy {
  final String firstName;
  final String? lastName;

  const FallAlertAcknowledgedBy({
    required this.firstName,
    this.lastName,
  });

  factory FallAlertAcknowledgedBy.fromJson(Map<String, dynamic> json) {
    return FallAlertAcknowledgedBy(
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'first_name': firstName,
      if (lastName != null) 'last_name': lastName,
    };
  }

  @override
  String toString() => firstName;
}

/// Downlink status payload received on `healthkicks/v1/users/{user_id}/fall-alert/status`.
class FallAlertStatusModel {
  final String eventId;
  final int? alertId;
  final String state; // 'PENDING' | 'ESCALATING' | 'ACKNOWLEDGED' | 'CANCELLED' | 'EXHAUSTED' | 'SUPPRESSED' | 'TEST_SMS'
  final int? currentContactRank;
  final int? contactsTotal;
  final FallAlertAcknowledgedBy? acknowledgedBy;
  final String? cancelReason;
  final DateTime? nextActionAt;
  final DateTime? updatedAt;
  final FallAlertSmsCommand? smsCommand;

  const FallAlertStatusModel({
    required this.eventId,
    this.alertId,
    required this.state,
    this.currentContactRank,
    this.contactsTotal,
    this.acknowledgedBy,
    this.cancelReason,
    this.nextActionAt,
    this.updatedAt,
    this.smsCommand,
  });

  FallAlertState get stateEnum => FallAlertState.fromString(state);

  bool get isPending => state == 'PENDING';
  bool get isEscalating => state == 'ESCALATING';
  bool get isAcknowledged => state == 'ACKNOWLEDGED';
  bool get isCancelled => state == 'CANCELLED';
  bool get isExhausted => state == 'EXHAUSTED';
  bool get isSuppressed => state == 'SUPPRESSED';
  bool get isTestSms => state == 'TEST_SMS';

  factory FallAlertStatusModel.fromJson(Map<String, dynamic> json) {
    FallAlertAcknowledgedBy? ackBy;
    final rawAck = json['acknowledged_by'];
    if (rawAck is Map<String, dynamic>) {
      ackBy = FallAlertAcknowledgedBy.fromJson(rawAck);
    } else if (rawAck is String && rawAck.isNotEmpty) {
      ackBy = FallAlertAcknowledgedBy(firstName: rawAck);
    }

    FallAlertSmsCommand? parsedSmsCmd;
    final rawSmsCmd = json['sms_command'];
    if (rawSmsCmd is Map<String, dynamic>) {
      parsedSmsCmd = FallAlertSmsCommand.fromJson(rawSmsCmd);
    }

    DateTime? parseDate(dynamic raw) {
      if (raw is String && raw.isNotEmpty) {
        return DateTime.tryParse(raw)?.toUtc();
      }
      if (raw is int) {
        return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
      }
      return null;
    }

    return FallAlertStatusModel(
      eventId: json['event_id'] as String? ?? '',
      alertId: (json['alert_id'] as num?)?.toInt(),
      state: (json['state'] as String? ?? 'PENDING').toUpperCase(),
      currentContactRank: (json['current_contact_rank'] as num?)?.toInt(),
      contactsTotal: (json['contacts_total'] as num?)?.toInt(),
      acknowledgedBy: ackBy,
      cancelReason: json['cancel_reason'] as String?,
      nextActionAt: parseDate(json['next_action_at']),
      updatedAt: parseDate(json['updated_at']),
      smsCommand: parsedSmsCmd,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'event_id': eventId,
      'alert_id': alertId,
      'state': state,
      'current_contact_rank': currentContactRank,
      'contacts_total': contactsTotal,
      'acknowledged_by': acknowledgedBy?.toJson(),
      'cancel_reason': cancelReason,
      'next_action_at': nextActionAt?.toUtc().toIso8601String(),
      'updated_at': updatedAt?.toUtc().toIso8601String(),
      if (smsCommand != null) 'sms_command': smsCommand!.toJson(),
    };
  }
}

typedef FallAlertDownlinkStatus = FallAlertStatusModel;
