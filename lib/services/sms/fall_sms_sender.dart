import 'package:flutter/services.dart';

/// Result of an Android GSM SMS dispatch attempt.
class SmsSendResult {
  final bool success;
  final String? errorMessage;

  const SmsSendResult({
    required this.success,
    this.errorMessage,
  });
}

/// Injectable interface for sending native SMS alerts on Android.
abstract class FallSmsSender {
  /// Requests the Android `SEND_SMS` runtime permission if not already granted.
  Future<bool> requestSmsPermission();

  /// Sends an SMS to [phone] with the given [message] via Android `SmsManager`.
  Future<SmsSendResult> sendSms({
    required String phone,
    required String message,
  });
}

/// Default implementation of [FallSmsSender] backed by the `"healthkicks/sms"` MethodChannel.
class MethodChannelFallSmsSender implements FallSmsSender {
  static const MethodChannel _channel = MethodChannel('healthkicks/sms');

  const MethodChannelFallSmsSender();

  @override
  Future<bool> requestSmsPermission() async {
    try {
      final granted = await _channel.invokeMethod<bool>('requestSmsPermission');
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<SmsSendResult> sendSms({
    required String phone,
    required String message,
  }) async {
    try {
      final sent = await _channel.invokeMethod<bool>('sendSms', {
        'phone': phone,
        'message': message,
      });
      if (sent == true) {
        return const SmsSendResult(success: true);
      }
      return const SmsSendResult(
        success: false,
        errorMessage: 'SMS send returned false',
      );
    } on PlatformException catch (e) {
      return SmsSendResult(
        success: false,
        errorMessage: e.message ?? e.code,
      );
    } catch (e) {
      return SmsSendResult(
        success: false,
        errorMessage: e.toString(),
      );
    }
  }
}
