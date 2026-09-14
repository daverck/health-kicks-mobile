/// Configuration globale de l'application HealthKicks Mobile.
class AppConfig {
  /// URL de base de l'API backend FastAPI HealthKicks.
  /// Par défaut en production / HTTPS sur le port 8443.
  static const String backendBaseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: 'https://healthkicks.duckdns.org:8443',
  );

  /// Endpoint ATS AWS IoT Core par défaut.
  static const String awsIotEndpoint = String.fromEnvironment(
    'AWS_IOT_ENDPOINT',
    defaultValue: 'a2k10w7ebf2tx9-ats.iot.eu-north-1.amazonaws.com',
  );

  /// Région AWS par défaut pour IoT Core et STS.
  static const String awsRegion = String.fromEnvironment(
    'AWS_REGION',
    defaultValue: 'eu-north-1',
  );
}
