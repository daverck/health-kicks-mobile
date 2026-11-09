import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/controllers/dashboard_mqtt_coordinator.dart';

void main() {
  group('DashboardMqttCoordinator tests', () {
    test('initializes with default disconnected state', () {
      final coordinator = DashboardMqttCoordinator(
        deviceId: 'HK-2',
      );

      expect(coordinator.deviceId, 'HK-2');
      expect(coordinator.isMqttConnected, isFalse);
      expect(coordinator.mqttConnectedNotifier.value, isFalse);
      expect(coordinator.mqttService, isNull);

      coordinator.dispose();
    });

    test('disconnect clears connection state', () {
      final coordinator = DashboardMqttCoordinator(
        deviceId: 'HK-2',
      );

      coordinator.disconnect();

      expect(coordinator.isMqttConnected, isFalse);
      expect(coordinator.mqttConnectedNotifier.value, isFalse);

      coordinator.dispose();
    });
  });
}
