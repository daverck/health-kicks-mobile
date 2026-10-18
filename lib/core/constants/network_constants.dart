/// Centralized network timeouts, retry configurations, and connection durations
/// for the HealthKicks Mobile Edge Gateway.
class NetworkConstants {
  NetworkConstants._();

  /// Default timeout for initiating HTTP connections to the REST API.
  static const Duration apiConnectTimeout = Duration(seconds: 10);

  /// Default timeout for waiting on HTTP responses from the backend.
  static const Duration apiReceiveTimeout = Duration(seconds: 15);

  /// Default timeout for OAuth SSO authentication web flows.
  static const Duration authFlowTimeout = Duration(minutes: 2);

  /// AWS IoT Core MQTT keep-alive ping interval in seconds.
  static const int mqttKeepAliveSeconds = 60;

  /// Default timeout for establishing the MQTT WebSockets SigV4 connection.
  static const Duration mqttConnectTimeout = Duration(seconds: 10);

  /// Duration to scan for footwear devices before stopping automatically.
  static const Duration bleScanTimeout = Duration(seconds: 15);

  /// Timeout for negotiating GATT connection with the ESP32-S3 shoe.
  static const Duration bleConnectTimeout = Duration(seconds: 15);

  /// Default maximum duration for auto-reconnection procedures (e.g. post-OTA reboot).
  static const Duration bleAutoReconnectTimeout = Duration(seconds: 45);
}

