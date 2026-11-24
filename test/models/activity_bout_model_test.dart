import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/models/activity_bout_model.dart';

void main() {
  group('ActivityBoutModel', () {
    test('correctly decodes 8-byte big-endian binary payload', () {
      // 8 bytes:
      // start_uptime_sec = 600 (0x0258)
      // duration_sec = 300 (0x012C)
      // step_count = 450 (0x01C2)
      // activity_type = 0x01 (walk)
      // avg_cadence = 90 (0x5A)
      final raw = Uint8List.fromList([
        0x02, 0x58, // 600
        0x01, 0x2C, // 300
        0x01, 0xC2, // 450
        0x01,       // walk
        0x5A,       // 90
      ]);

      final bout = ActivityBoutModel.fromBytes(raw, 0);

      expect(bout.startUptimeSec, equals(600));
      expect(bout.durationSec, equals(300));
      expect(bout.stepCount, equals(450));
      expect(bout.activityType, equals(0x01));
      expect(bout.avgCadence, equals(90));
    });

    test('throws ArgumentError on truncated payload', () {
      final truncated = Uint8List.fromList([0x01, 0x02, 0x03]);
      expect(() => ActivityBoutModel.fromBytes(truncated, 0), throwsArgumentError);
    });

    test('computes single-hour step ventilation accurately', () {
      final sessionStart = DateTime(2026, 11, 24, 14, 0, 0);
      final bout = ActivityBoutModel(
        startUptimeSec: 600, // 14:10:00
        durationSec: 900,   // 15 minutes -> ends 14:25:00
        stepCount: 1200,
        activityType: 0x01,
        avgCadence: 80,
      );

      final ventilation = bout.computeHourlyVentilation(sessionStart);

      expect(ventilation, equals({14: 1200}));
    });

    test('splits steps proportionally when crossing an hour boundary', () {
      // Session starts at 14:00:00.
      // Bout starts at T = 3000s (14:50:00).
      // Bout duration = 1800s (30 minutes) -> ends at T = 4800s (15:20:00).
      // 10 minutes (600s) in Hour 14, 20 minutes (1200s) in Hour 15.
      // Total steps = 3000.
      // Proportional steps:
      // Hour 14: 3000 * 600 / 1800 = 1000 steps.
      // Hour 15: 3000 * 1200 / 1800 = 2000 steps.
      final sessionStart = DateTime(2026, 11, 24, 14, 0, 0);
      final bout = ActivityBoutModel(
        startUptimeSec: 3000,
        durationSec: 1800,
        stepCount: 3000,
        activityType: 0x02, // run
        avgCadence: 160,
      );

      final ventilation = bout.computeHourlyVentilation(sessionStart);

      expect(ventilation.length, equals(2));
      expect(ventilation[14], equals(1000));
      expect(ventilation[15], equals(2000));
      expect(ventilation.values.fold<int>(0, (sum, v) => sum + v), equals(3000));
    });

    test('reconciles rounding differences strictly to match stepCount', () {
      // 100 steps over 1800s: 700s in Hour 10 (38.88%), 1100s in Hour 11 (61.11%)
      final sessionStart = DateTime(2026, 11, 24, 10, 0, 0);
      final bout = ActivityBoutModel(
        startUptimeSec: 2900, // 10:48:20
        durationSec: 1800,   // Ends 11:18:20
        stepCount: 100,
        activityType: 0x01,
        avgCadence: 65,
      );

      final ventilation = bout.computeHourlyVentilation(sessionStart);

      final totalVentilated = ventilation.values.fold<int>(0, (sum, v) => sum + v);
      expect(totalVentilated, equals(100));
    });
  });
}
