import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/core/constants/ble_constants.dart';
import 'package:healthkicks_mobile/core/permissions/permission_service.dart';
import 'package:healthkicks_mobile/services/ble/ble_connection_manager.dart';
import 'package:permission_handler/permission_handler.dart';

class FakePermissionService extends PermissionService {
  final bool granted;

  FakePermissionService({this.granted = true});

  @override
  Future<BlePermissionResult> requestDetailedBlePermissions({PermissionLogCallback? onLog}) async {
    return BlePermissionResult(
      isGranted: granted,
      isPermanentlyDenied: !granted,
      scanStatus: granted ? PermissionStatus.granted : PermissionStatus.permanentlyDenied,
      connectStatus: granted ? PermissionStatus.granted : PermissionStatus.permanentlyDenied,
      details: 'Mocked permissions (granted: $granted)',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BleConnectionManager - Scan timeout management', () {
    test('BleConstants.defaultScanTimeout is 3 minutes', () {
      expect(BleConstants.defaultScanTimeout, equals(const Duration(minutes: 3)));
      expect(BleConstants.defaultScanTimeout.inSeconds, equals(180));
    });

    test('BleConnectionManager initializes status to disconnected', () {
      final manager = BleConnectionManager(
        permissionService: FakePermissionService(granted: true),
      );

      expect(manager.status, equals(BleConnectionStatus.disconnected));
      expect(manager.connectedDevice, isNull);
    });

    test('disconnect() and dispose() cleanly release resources and remain disconnected', () async {
      final manager = BleConnectionManager(
        permissionService: FakePermissionService(granted: true),
      );

      await manager.disconnect();
      expect(manager.status, equals(BleConnectionStatus.disconnected));

      manager.dispose();
      expect(manager.status, equals(BleConnectionStatus.disconnected));
    });

    test('startAutoConnect rejects if permissions are not granted', () async {
      final manager = BleConnectionManager(
        permissionService: FakePermissionService(granted: false),
      );

      expect(
        () => manager.startAutoConnect(),
        throwsA(isA<Exception>()),
      );
      expect(manager.status, equals(BleConnectionStatus.disconnected));
    });

    test('BleConnectionManager notifies ChangeNotifier listeners and statusStream on transitions', () async {
      final manager = BleConnectionManager(
        permissionService: FakePermissionService(granted: true),
      );
      addTearDown(manager.dispose);

      int listenerNotificationCount = 0;
      manager.addListener(() {
        listenerNotificationCount++;
      });

      final receivedStatuses = <BleConnectionStatus>[];
      final sub = manager.statusStream.listen(receivedStatuses.add);
      addTearDown(sub.cancel);

      manager.updateStatusForTesting(BleConnectionStatus.scanning);
      expect(manager.status, equals(BleConnectionStatus.scanning));
      expect(listenerNotificationCount, equals(1));

      manager.updateStatusForTesting(BleConnectionStatus.connecting);
      expect(manager.status, equals(BleConnectionStatus.connecting));
      expect(listenerNotificationCount, equals(2));

      manager.updateStatusForTesting(BleConnectionStatus.connected);
      expect(manager.status, equals(BleConnectionStatus.connected));
      expect(listenerNotificationCount, equals(3));

      manager.updateStatusForTesting(BleConnectionStatus.ready);
      expect(manager.status, equals(BleConnectionStatus.ready));
      expect(listenerNotificationCount, equals(4));

      manager.updateStatusForTesting(BleConnectionStatus.disconnected);
      expect(manager.status, equals(BleConnectionStatus.disconnected));
      expect(listenerNotificationCount, equals(5));

      await pumpEventQueue();

      expect(receivedStatuses, equals([
        BleConnectionStatus.scanning,
        BleConnectionStatus.connecting,
        BleConnectionStatus.connected,
        BleConnectionStatus.ready,
        BleConnectionStatus.disconnected,
      ]));
    });
  });
}

