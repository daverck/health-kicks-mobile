/// Model representing a firmware release metadata fetched from backend or S3.
class FirmwareReleaseModel {
  final String version;
  final String downloadUrl;
  final String sha256;
  final int sizeBytes;
  final int expiresInSeconds;
  final DateTime releaseDate;

  const FirmwareReleaseModel({
    required this.version,
    required this.downloadUrl,
    required this.sha256,
    required this.sizeBytes,
    required this.expiresInSeconds,
    required this.releaseDate,
  });

  factory FirmwareReleaseModel.fromJson(Map<String, dynamic> json) {
    DateTime parsedDate;
    final rawDate = json['release_date'];
    if (rawDate is String) {
      parsedDate = DateTime.tryParse(rawDate)?.toUtc() ?? DateTime.now().toUtc();
    } else {
      parsedDate = DateTime.now().toUtc();
    }

    return FirmwareReleaseModel(
      version: json['version'] as String? ?? 'v1.2.1-esp32s3',
      downloadUrl: json['download_url'] as String? ?? '',
      sha256: json['sha256'] as String? ?? '',
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      expiresInSeconds: (json['expires_in_seconds'] as num?)?.toInt() ?? 900,
      releaseDate: parsedDate,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'download_url': downloadUrl,
      'sha256': sha256,
      'size_bytes': sizeBytes,
      'expires_in_seconds': expiresInSeconds,
      'release_date': releaseDate.toIso8601String(),
    };
  }
}

