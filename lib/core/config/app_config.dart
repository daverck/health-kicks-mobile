/// Global configuration for the HealthKicks Mobile application.
class AppConfig {
  /// Base URL of the HealthKicks FastAPI backend API.
  /// Defaults to production HTTPS endpoint on api.healthkicks.eu.
  static const String backendBaseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: 'https://api.healthkicks.eu',
  );

  /// Default AWS IoT Core ATS endpoint.
  static const String awsIotEndpoint = String.fromEnvironment(
    'AWS_IOT_ENDPOINT',
    defaultValue: 'a2k10w7ebf2tx9-ats.iot.eu-west-1.amazonaws.com',
  );

  /// Default AWS region for IoT Core and STS.
  static const String awsRegion = String.fromEnvironment(
    'AWS_REGION',
    defaultValue: 'eu-west-1',
  );

  /// Sentry DSN for mobile crash reporting and error diagnostics.
  static const String sentryDsn = String.fromEnvironment(
    'SENTRY_DSN',
    defaultValue:
        'https://a42586aa0336c6835c99a921e62d987f@o4512458563780608.ingest.de.sentry.io/4512459295948880',
  );

  /// Inactivity timeout before automatically shutting down the background surveillance service (5 minutes).
  static const Duration bleDisconnectTimeout = Duration(minutes: 5);
}
