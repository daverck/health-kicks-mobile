import 'dart:async';
import '../../models/fall_alert_model.dart';
import 'fall_location_provider.dart';

/// Helper service responsible for acquiring high-accuracy GPS coordinates during fall alerting.
class FallLocationResolver {
  final FallLocationProvider locationProvider;
  final void Function(String tag, String message, {bool isError})? onLog;

  const FallLocationResolver({
    this.locationProvider = const DefaultFallLocationProvider(),
    this.onLog,
  });

  /// Resolves current GPS coordinates, respecting timeout and returning null if permissions/hardware fail.
  Future<FallAlertLocation?> resolveCurrentLocation({Duration timeout = const Duration(seconds: 3)}) async {
    try {
      final loc = await locationProvider.getCurrentLocation(timeout: timeout);
      if (loc == null) {
        onLog?.call('LOCATION', 'GPS position timed out; proceeding without fix');
        return null;
      }

      final accStr = loc.accuracyM.toStringAsFixed(1);
      onLog?.call(
        'LOCATION',
        'Acquired location: lat=${loc.lat.toStringAsFixed(5)}, lon=${loc.lon.toStringAsFixed(5)}, acc=${accStr}m',
      );
      return loc;
    } catch (e) {
      onLog?.call('LOCATION', 'Failed to retrieve location: $e', isError: true);
      return null;
    }
  }
}
