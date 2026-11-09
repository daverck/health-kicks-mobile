import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/controllers/fall_sms_relay_coordinator.dart';
import 'package:healthkicks_mobile/models/fall_alert_model.dart';
import 'package:healthkicks_mobile/services/sms/fall_sms_sender.dart';

class MockFallSmsSender implements FallSmsSender {
  bool permissionGranted = true;
  bool shouldSucceed = true;
  String? failureErrorMessage;
  final List<Map<String, String>> sentMessages = [];

  @override
  Future<bool> requestSmsPermission() async => permissionGranted;

  @override
  Future<SmsSendResult> sendSms({
    required String phone,
    required String message,
  }) async {
    sentMessages.add({'phone': phone, 'message': message});
    if (shouldSucceed) {
      return const SmsSendResult(success: true);
    }
    return SmsSendResult(
      success: false,
      errorMessage: failureErrorMessage ?? 'Failed to send SMS',
    );
  }
}

void main() {
  group('FallSmsRelayCoordinator', () {
    late MockFallSmsSender mockSender;
    late List<String> logs;

    setUp(() {
      mockSender = MockFallSmsSender();
      logs = [];
    });

    test('requestSmsPermission delegates to smsSender', () async {
      final coordinator = FallSmsRelayCoordinator(
        smsSender: mockSender,
      );

      mockSender.permissionGranted = true;
      expect(await coordinator.requestSmsPermission(), isTrue);

      mockSender.permissionGranted = false;
      expect(await coordinator.requestSmsPermission(), isFalse);
    });

    test('handleDownlinkSmsCommand sends SMS and publishes status uplink on success', () async {
      final published = <FallAlertUplinkPayload>[];
      final pending = <FallAlertUplinkPayload>[];
      int? reportedNotifId;
      bool? reportedSuccess;

      final coordinator = FallSmsRelayCoordinator(
        smsSender: mockSender,
        onLog: (tag, msg, {isError = false}) => logs.add('[$tag] $msg'),
        onSmsStatusReported: (notifId, sent, error) async {
          reportedNotifId = notifId;
          reportedSuccess = sent;
        },
      );

      const cmd = FallAlertSmsCommand(
        notificationId: 42,
        recipientPhone: '+33612345678',
        contactFirstName: 'Alice',
        message: 'Alerte chute!',
        isTest: false,
      );

      coordinator.handleDownlinkSmsCommand(
        eventId: 'evt-1',
        cmd: cmd,
        publishUplink: (payload) async {
          published.add(payload);
          return true;
        },
        enqueuePendingPayload: (payload) => pending.add(payload),
      );

      // Wait for async execution
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(mockSender.sentMessages.length, equals(1));
      expect(mockSender.sentMessages.first['phone'], equals('+33612345678'));
      expect(published.length, equals(1));
      expect(published.first.action, equals(FallAlertAction.smsStatus.value));
      expect(published.first.notificationId, equals(42));
      expect(published.first.smsStatus, equals('SENT'));
      expect(pending, isEmpty);
      expect(reportedNotifId, equals(42));
      expect(reportedSuccess, isTrue);
      expect(coordinator.processedSmsCommandKeys, contains('notif:42'));
    });

    test('handleDownlinkSmsCommand enforces idempotency and ignores duplicated keys', () async {
      final published = <FallAlertUplinkPayload>[];
      final pending = <FallAlertUplinkPayload>[];

      final coordinator = FallSmsRelayCoordinator(
        smsSender: mockSender,
      );

      const cmd = FallAlertSmsCommand(
        notificationId: 99,
        recipientPhone: '+33600000000',
        contactFirstName: 'Bob',
        message: 'Alerte test',
        isTest: false,
      );

      coordinator.handleDownlinkSmsCommand(
        eventId: 'evt-dup',
        cmd: cmd,
        publishUplink: (payload) async {
          published.add(payload);
          return true;
        },
        enqueuePendingPayload: (payload) => pending.add(payload),
      );

      // Trigger second time with same command
      coordinator.handleDownlinkSmsCommand(
        eventId: 'evt-dup',
        cmd: cmd,
        publishUplink: (payload) async {
          published.add(payload);
          return true;
        },
        enqueuePendingPayload: (payload) => pending.add(payload),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(mockSender.sentMessages.length, equals(1));
      expect(published.length, equals(1));
    });

    test('enqueues pending payload when MQTT publish fails', () async {
      final published = <FallAlertUplinkPayload>[];
      final pending = <FallAlertUplinkPayload>[];

      final coordinator = FallSmsRelayCoordinator(
        smsSender: mockSender,
      );

      const cmd = FallAlertSmsCommand(
        notificationId: 77,
        recipientPhone: '+33611111111',
        contactFirstName: 'Charlie',
        message: 'Alerte',
        isTest: false,
      );

      coordinator.handleDownlinkSmsCommand(
        eventId: 'evt-fail',
        cmd: cmd,
        publishUplink: (payload) async {
          published.add(payload);
          return false; // MQTT publish failed
        },
        enqueuePendingPayload: (payload) => pending.add(payload),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(published.length, equals(1));
      expect(pending.length, equals(1));
      expect(pending.first.notificationId, equals(77));
    });

    test('test SMS does not publish status payload to MQTT', () async {
      final published = <FallAlertUplinkPayload>[];
      final pending = <FallAlertUplinkPayload>[];

      final coordinator = FallSmsRelayCoordinator(
        smsSender: mockSender,
      );

      const cmd = FallAlertSmsCommand(
        notificationId: 101,
        recipientPhone: '+33622222222',
        contactFirstName: 'David',
        message: 'Test SMS',
        isTest: true,
      );

      coordinator.handleDownlinkSmsCommand(
        eventId: 'evt-test',
        cmd: cmd,
        publishUplink: (payload) async {
          published.add(payload);
          return true;
        },
        enqueuePendingPayload: (payload) => pending.add(payload),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(mockSender.sentMessages.length, equals(1));
      expect(published, isEmpty);
      expect(pending, isEmpty);
    });
  });
}
