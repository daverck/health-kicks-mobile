/// Global configuration for the HealthKicks Mobile application.
class AppConfig {
  /// Base URL of the HealthKicks FastAPI backend API.
  /// Defaults to production / HTTPS on port 8443.
  static const String backendBaseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: 'https://healthkicks.duckdns.org:8443',
  );

  /// Default AWS IoT Core ATS endpoint.
  static const String awsIotEndpoint = String.fromEnvironment(
    'AWS_IOT_ENDPOINT',
    defaultValue: 'a2k10w7ebf2tx9-ats.iot.eu-north-1.amazonaws.com',
  );

  /// Default AWS region for IoT Core and STS.
  static const String awsRegion = String.fromEnvironment(
    'AWS_REGION',
    defaultValue: 'eu-north-1',
  );

  /// Inactivity timeout before automatically shutting down the background surveillance service (5 minutes).
  static const Duration bleDisconnectTimeout = Duration(minutes: 5);
}
