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

  /// Robust UTC parser that prevents naive ISO strings from being misinterpreted as local time by Dart.
  static DateTime parseUtcDateTime(dynamic raw) {
    if (raw == null) return DateTime.now().toUtc();
    if (raw is DateTime) return raw.toUtc();
    var s = raw.toString().trim();
    if (s.isEmpty) return DateTime.now().toUtc();

    // If string has no timezone offset (ends with no Z and no +/-HH:mm), treat it as UTC!
    if (!s.endsWith('Z') && !RegExp(r'[+-]\d{2}(:\d{2})?$').hasMatch(s)) {
      if (s.contains('T')) {
        s = '${s}Z';
      } else if (s.contains(' ')) {
        s = '${s.replaceFirst(' ', 'T')}Z';
      } else {
        s = '${s}T00:00:00Z';
      }
    }
    return DateTime.tryParse(s)?.toUtc() ?? DateTime.now().toUtc();
  }

  factory FirmwareReleaseModel.fromJson(Map<String, dynamic> json) {
    return FirmwareReleaseModel(
      version: json['version'] as String? ?? 'v1.2.1-esp32s3',
      downloadUrl: json['download_url'] as String? ?? '',
      sha256: json['sha256'] as String? ?? '',
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      expiresInSeconds: (json['expires_in_seconds'] as num?)?.toInt() ?? 900,
      releaseDate: parseUtcDateTime(json['release_date']),
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
