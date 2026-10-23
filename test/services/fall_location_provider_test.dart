import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/services/location/fall_location_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bounds the complete location lookup by the requested timeout', () async {
    final provider = DefaultFallLocationProvider(
      checkPermission: () async => true,
      fetchRawLocation: (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return {
          'lat': 50.8466,
          'lon': 4.3528,
          'accuracy_m': 10.0,
          'captured_at': 1792745941000,
        };
      },
    );
    final stopwatch = Stopwatch()..start();

    final location = await provider.getCurrentLocation(
      timeout: const Duration(milliseconds: 30),
    );

    expect(location, isNull);
    expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 150)));
  });
}
