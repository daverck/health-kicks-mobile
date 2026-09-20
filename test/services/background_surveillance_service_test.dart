import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:healthkicks_mobile/services/background_surveillance_service.dart';
import 'package:healthkicks_mobile/services/ble/ble_connection_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('BackgroundSurveillanceService - Inactivity Timeout & Lifecycle', () {
    test('Initializes with surveillance disabled by default', () {
      final service = BackgroundSurveillanceService();
      addTearDown(service.dispose);
      expect(service.isSurveillanceActive, isFalse);
      expect(service.currentBleStatus, BleConnectionStatus.disconnected);
    });

    test('Inactivity timer triggers stopSurveillance when timeout expires', () async {
      final logs = <String>[];
      final service = BackgroundSurveillanceService(
        disconnectTimeout: const Duration(milliseconds: 50),
        onLog: (tag, msg, {isError = false}) {
          logs.add('[$tag] $msg');
        },
      );
      addTearDown(service.dispose);

      // Start surveillance manually (simulate active state)
      await service.startSurveillance();
      expect(service.isSurveillanceActive, isTrue);

      // Signal BLE disconnected
      service.onBleStatusChanged(BleConnectionStatus.disconnected);
      expect(service.isSurveillanceActive, isTrue);

      // Wait for the short timeout to expire
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(service.isSurveillanceActive, isFalse);
      expect(
        logs.any((l) => l.contains('Timeout d\'inactivité BLE')),
        isTrue,
      );
    });

    test('Reconnection cancels pending inactivity timer', () async {
      final logs = <String>[];
      final service = BackgroundSurveillanceService(
        disconnectTimeout: const Duration(milliseconds: 100),
        onLog: (tag, msg, {isError = false}) {
          logs.add('[$tag] $msg');
        },
      );
      addTearDown(service.dispose);

      await service.startSurveillance();
      expect(service.isSurveillanceActive, isTrue);

      // Disconnect starts timer
      service.onBleStatusChanged(BleConnectionStatus.disconnected);

      // Reconnect after 30ms (< 100ms timeout)
      await Future<void>.delayed(const Duration(milliseconds: 30));
      service.onBleStatusChanged(BleConnectionStatus.ready, deviceName: 'HK-2');

      // Wait past original 100ms mark
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Service should still be active because reconnection canceled timer
      expect(service.isSurveillanceActive, isTrue);
      expect(
        logs.any((l) => l.contains('annulation du timer d\'inactivité')),
        isTrue,
      );
    });

    test('stopSurveillance cancels timer and updates state', () async {
      final service = BackgroundSurveillanceService(
        disconnectTimeout: const Duration(minutes: 5),
      );
      addTearDown(service.dispose);

      await service.startSurveillance();
      expect(service.isSurveillanceActive, isTrue);

      await service.stopSurveillance(reason: 'Test stop');
      expect(service.isSurveillanceActive, isFalse);
    });
  });
}
