import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:healthkicks_mobile/services/integrations/health_connect_service.dart';

class FakeHealth extends Health {
  bool available = true;
  bool? hasPerms = true;
  bool authResult = true;
  bool writeResult = true;
  bool installPrompted = false;
  final List<Map<String, dynamic>> writeCalls = [];

  @override
  Future<void> configure() async {}

  @override
  Future<bool> isHealthConnectAvailable() async => available;

  @override
  Future<bool?> hasPermissions(List<HealthDataType> types, {List<HealthDataAccess>? permissions}) async =>
      hasPerms;

  @override
  Future<bool> requestAuthorization(List<HealthDataType> types, {List<HealthDataAccess>? permissions}) async =>
      authResult;

  @override
  Future<void> installHealthConnect() async {
    installPrompted = true;
  }

  @override
  Future<bool> writeHealthData({
    required double value,
    HealthDataUnit? unit,
    required HealthDataType type,
    required DateTime startTime,
    String? clientRecordId,
    double? clientRecordVersion,
    DateTime? endTime,
    RecordingMethod recordingMethod = RecordingMethod.automatic,
  }) async {
    writeCalls.add({
      'value': value,
      'type': type,
      'startTime': startTime,
      'endTime': endTime,
      'clientRecordId': clientRecordId,
    });
    return writeResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HealthConnectService - Export Integration Tests', () {
    late FakeHealth fakeHealth;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      fakeHealth = FakeHealth();
    });

    test('Initializes disabled by default', () async {
      final service = HealthConnectService(health: fakeHealth);
      await service.init();

      expect(service.isEnabled, isFalse);
      expect(service.lastSyncTime, isNull);
    });

    test('Loads enabled status and last sync time from SharedPreferences', () async {
      final now = DateTime.utc(2026, 10, 18, 14, 30, 0);
      SharedPreferences.setMockInitialValues({
        HealthConnectService.keyEnabled: true,
        HealthConnectService.keyLastSync: now.toIso8601String(),
      });

      final service = HealthConnectService(health: fakeHealth);
      await service.init();

      expect(service.isEnabled, isTrue);
      expect(service.lastSyncTime, equals(now));
    });

    test('setEnabled persists flag to SharedPreferences and notifies listeners', () async {
      final service = HealthConnectService(health: fakeHealth);
      await service.init();

      bool notified = false;
      service.addListener(() => notified = true);

      await service.setEnabled(true);

      expect(service.isEnabled, isTrue);
      expect(notified, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(HealthConnectService.keyEnabled), isTrue);
    });

    test('syncDailySteps skips sync when disabled or steps <= 0', () async {
      final service = HealthConnectService(health: fakeHealth);
      await service.init(); // disabled by default

      final res1 = await service.syncDailySteps(
        steps: 500,
        date: DateTime.now(),
      );
      expect(res1, isFalse);
      expect(fakeHealth.writeCalls, isEmpty);

      await service.setEnabled(true);
      final res2 = await service.syncDailySteps(
        steps: 0,
        date: DateTime.now(),
      );
      expect(res2, isFalse);
      expect(fakeHealth.writeCalls, isEmpty);
    });

    test('syncDailySteps writes deduplicated steps with clientRecordId and updates lastSyncTime', () async {
      final service = HealthConnectService(health: fakeHealth);
      await service.init();
      await service.setEnabled(true);

      final syncDate = DateTime.utc(2026, 10, 18);
      final success = await service.syncDailySteps(
        steps: 4200,
        date: syncDate,
        deviceId: 'HK-S3-01',
      );

      expect(success, isTrue);
      expect(fakeHealth.writeCalls.length, equals(1));

      final call = fakeHealth.writeCalls.first;
      expect(call['value'], equals(4200.0));
      expect(call['type'], equals(HealthDataType.STEPS));
      expect(call['clientRecordId'], equals('hk_steps_HK-S3-01_2026_10_18'));
      expect(service.lastSyncTime, isNotNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(HealthConnectService.keyLastSync), isNotNull);
    });
  });
}
