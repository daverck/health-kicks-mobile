import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/services/ble/ble_ota_service.dart';

void main() {
  group('BleOtaService Unit Tests', () {
    late BleOtaService otaService;

    setUp(() {
      otaService = BleOtaService();
    });

    tearDown(() {
      otaService.dispose();
    });

    test('Initial state is idle', () {
      expect(otaService.currentProgress.status, equals(BleOtaStatus.idle));
      expect(otaService.currentProgress.bytesSent, equals(0));
      expect(otaService.currentProgress.totalBytes, equals(0));
      expect(otaService.currentProgress.progress, equals(0.0));
      expect(otaService.isUpdating, isFalse);
    });

    test('formatErrorCode translates all specification codes accurately', () {
      expect(BleOtaService.formatErrorCode(0x01), contains('No inactive OTA partition'));
      expect(BleOtaService.formatErrorCode(0x02), contains('esp_ota_begin'));
      expect(BleOtaService.formatErrorCode(0x03), contains('esp_ota_write'));
      expect(BleOtaService.formatErrorCode(0x04), contains('byte count mismatch'));
      expect(BleOtaService.formatErrorCode(0x05), contains('esp_ota_end'));
      expect(BleOtaService.formatErrorCode(0x06), contains('Switch active boot partition failed'));
      expect(BleOtaService.formatErrorCode(0x07), contains('SHA-256'));
      expect(BleOtaService.formatErrorCode(0x99), contains('0x99'));
    });

    test('abort() updates state to aborted with user message', () async {
      final progressList = <BleOtaProgress>[];
      final sub = otaService.progressStream.listen(progressList.add);

      otaService.abort();

      await Future.delayed(const Duration(milliseconds: 10));
      expect(otaService.currentProgress.status, equals(BleOtaStatus.aborted));
      expect(otaService.currentProgress.message, contains('annulée'));
      expect(progressList.any((p) => p.status == BleOtaStatus.aborted), isTrue);

      await sub.cancel();
    });

    test('BleOtaProgress copyWith preserves or overrides properties correctly', () {
      const original = BleOtaProgress(
        status: BleOtaStatus.transferring,
        bytesSent: 100,
        totalBytes: 500,
        progress: 0.2,
        speedKbps: 45.5,
        estimatedTimeRemaining: Duration(seconds: 8),
        message: 'Uploading...',
        errorCode: null,
      );

      final updated = original.copyWith(
        bytesSent: 250,
        progress: 0.5,
        speedKbps: 50.0,
      );

      expect(updated.status, equals(BleOtaStatus.transferring));
      expect(updated.bytesSent, equals(250));
      expect(updated.totalBytes, equals(500));
      expect(updated.progress, equals(0.5));
      expect(updated.speedKbps, equals(50.0));
      expect(updated.estimatedTimeRemaining, equals(const Duration(seconds: 8)));
      expect(updated.message, equals('Uploading...'));
    });
  });
}
