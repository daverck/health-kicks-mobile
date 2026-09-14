/// Modèle de données représentant les identifiants temporaires AWS STS
/// obtenus auprès du backend HealthKicks (`POST /api/v1/auth/iot-credentials`).
class IoTCredentials {
  final String accessKeyId;
  final String secretAccessKey;
  final String sessionToken;
  final DateTime expiration;
  final String iotEndpoint;
  final String region;

  const IoTCredentials({
    required this.accessKeyId,
    required this.secretAccessKey,
    required this.sessionToken,
    required this.expiration,
    required this.iotEndpoint,
    required this.region,
  });

  /// Indique si les identifiants sont expirés ou sur le point de l'être.
  /// Une marge de sécurité de 5 minutes (300 secondes) est appliquée pour anticiper
  /// le renouvellement avant coupure du socket WebSocket.
  bool get isExpired {
    final threshold = DateTime.now().toUtc().add(const Duration(minutes: 5));
    return expiration.toUtc().isBefore(threshold);
  }

  /// Instancie les identifiants depuis la réponse JSON du backend.
  factory IoTCredentials.fromJson(Map<String, dynamic> json) {
    return IoTCredentials(
      accessKeyId: json['access_key_id'] as String,
      secretAccessKey: json['secret_access_key'] as String,
      sessionToken: json['session_token'] as String,
      expiration: DateTime.parse(json['expiration'] as String),
      iotEndpoint: json['iot_endpoint'] as String,
      region: json['region'] as String,
    );
  }

  /// Sérialise le modèle en JSON (utile pour les tests et la sérialisation).
  Map<String, dynamic> toJson() {
    return {
      'access_key_id': accessKeyId,
      'secret_access_key': secretAccessKey,
      'session_token': sessionToken,
      'expiration': expiration.toUtc().toIso8601String(),
      'iot_endpoint': iotEndpoint,
      'region': region,
    };
  }

  @override
  String toString() {
    return 'IoTCredentials(accessKeyId: $accessKeyId, endpoint: $iotEndpoint, region: $region, expiration: $expiration, isExpired: $isExpired)';
  }
}
