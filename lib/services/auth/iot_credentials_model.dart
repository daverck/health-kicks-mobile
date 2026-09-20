import '../../core/config/app_config.dart';

/// Data model representing temporary AWS STS credentials
/// obtained from the HealthKicks backend (`POST /api/v1/auth/iot-credentials`).
class IoTCredentials {
  final String accessKeyId;
  final String secretAccessKey;
  final String sessionToken;
  final DateTime expiration;
  final String iotEndpoint;
  final String region;
  final String? userId;

  const IoTCredentials({
    required this.accessKeyId,
    required this.secretAccessKey,
    required this.sessionToken,
    required this.expiration,
    required this.iotEndpoint,
    required this.region,
    this.userId,
  });

  /// Indicates whether credentials are expired or about to expire.
  /// A 5-minute (300 seconds) safety margin is applied to anticipate
  /// renewal before WebSocket disconnect.
  bool get isExpired {
    final threshold = DateTime.now().toUtc().add(const Duration(minutes: 5));
    return expiration.toUtc().isBefore(threshold);
  }

  /// Instantiates credentials from backend JSON response.
  /// If the backend omits endpoint or region, production AppConfig defaults are applied.
  factory IoTCredentials.fromJson(Map<String, dynamic> json) {
    final rawEndpoint = (json['iot_endpoint'] as String?)?.trim() ?? '';
    final rawRegion = (json['region'] as String?)?.trim() ?? '';
    final rawUserId = (json['user_id'] != null) ? json['user_id'].toString() : null;

    return IoTCredentials(
      accessKeyId: json['access_key_id'] as String,
      secretAccessKey: json['secret_access_key'] as String,
      sessionToken: json['session_token'] as String,
      expiration: DateTime.parse(json['expiration'] as String),
      iotEndpoint: rawEndpoint.isNotEmpty ? rawEndpoint : AppConfig.awsIotEndpoint,
      region: rawRegion.isNotEmpty ? rawRegion : AppConfig.awsRegion,
      userId: rawUserId,
    );
  }

  /// Serializes model to JSON (useful for testing and serialization).
  Map<String, dynamic> toJson() {
    return {
      'access_key_id': accessKeyId,
      'secret_access_key': secretAccessKey,
      'session_token': sessionToken,
      'expiration': expiration.toUtc().toIso8601String(),
      'iot_endpoint': iotEndpoint,
      'region': region,
      if (userId != null) 'user_id': userId,
    };
  }

  @override
  String toString() {
    return 'IoTCredentials(accessKeyId: $accessKeyId, endpoint: $iotEndpoint, region: $region, expiration: $expiration, isExpired: $isExpired, userId: $userId)';
  }
}
