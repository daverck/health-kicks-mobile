import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../models/fall_alert_model.dart';

/// Abstraction for retrieving the user's current or last known GPS position
/// during a fall alert without ever blocking the alert dispatch.
abstract class FallLocationProvider {
  /// Attempts to retrieve the current or last known GPS position within [timeout].
  /// Returns `null` if location permission is denied, GPS is disabled, or the lookup times out.
  Future<FallAlertLocation?> getCurrentLocation({
    Duration timeout = const Duration(seconds: 3),
  });
}

/// Default implementation of [FallLocationProvider] backed by permission checks
/// and the native Android location channel (`com.healthkicks.mobile/location`).
class DefaultFallLocationProvider implements FallLocationProvider {
  static const MethodChannel _channel = MethodChannel('com.healthkicks.mobile/location');

  final Future<bool> Function()? _checkPermission;
  final Future<Map<String, dynamic>?> Function(Duration timeout)? _fetchRawLocation;

  const DefaultFallLocationProvider({
    Future<bool> Function()? checkPermission,
    Future<Map<String, dynamic>?> Function(Duration timeout)? fetchRawLocation,
  })  : _checkPermission = checkPermission,
        _fetchRawLocation = fetchRawLocation;

  @override
  Future<FallAlertLocation?> getCurrentLocation({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      final hasPermission = _checkPermission != null
          ? await _checkPermission().timeout(const Duration(seconds: 1), onTimeout: () => false)
          : await _defaultPermissionCheck();

      if (!hasPermission) {
        return null;
      }

      final Map<String, dynamic>? rawMap;
      if (_fetchRawLocation != null) {
        rawMap = await _fetchRawLocation(timeout).timeout(timeout, onTimeout: () => null);
      } else {
        rawMap = await _channel
            .invokeMapMethod<String, dynamic>('getCurrentLocation', {
              'timeoutMs': timeout.inMilliseconds,
            })
            .timeout(timeout, onTimeout: () => null);
      }

      if (rawMap == null) return null;

      final lat = (rawMap['lat'] as num?)?.toDouble();
      final lon = (rawMap['lon'] as num?)?.toDouble();
      if (lat == null || lon == null) return null;
      if (lat < -90.0 || lat > 90.0 || lon < -180.0 || lon > 180.0) return null;

      final accuracy = (rawMap['accuracy_m'] as num?)?.toDouble() ?? 0.0;
      final capturedAt = (rawMap['captured_at'] as num?)?.toInt() ??
          DateTime.now().toUtc().millisecondsSinceEpoch;

      return FallAlertLocation(
        lat: lat,
        lon: lon,
        accuracyM: accuracy < 0 ? 0.0 : accuracy,
        capturedAt: capturedAt,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> _defaultPermissionCheck() async {
    try {
      if (!Platform.isAndroid && !Platform.isIOS) {
        return false;
      }
      final status = await Permission.locationWhenInUse
          .status
          .timeout(const Duration(seconds: 1));
      if (status.isGranted) return true;
      final coarseOrAlways = await Permission.location
          .status
          .timeout(const Duration(seconds: 1));
      return coarseOrAlways.isGranted;
    } catch (_) {
      return false;
    }
  }
}

/// Static/Mock provider for unit and widget tests.
class StaticFallLocationProvider implements FallLocationProvider {
  final FallAlertLocation? location;
  final Duration delay;

  const StaticFallLocationProvider({
    this.location,
    this.delay = Duration.zero,
  });

  @override
  Future<FallAlertLocation?> getCurrentLocation({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (delay > Duration.zero) {
      if (delay > timeout) {
        await Future<void>.delayed(timeout);
        return null;
      }
      await Future<void>.delayed(delay);
    }
    return location;
  }
}
