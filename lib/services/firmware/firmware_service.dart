import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/config/app_config.dart';
import '../../core/constants/ble_constants.dart';
import '../../models/firmware_release_model.dart';

/// Hardware device firmware info retrieved over BLE GATT standard DIS (0x180A).
class DeviceFirmwareInfo {
  final String? version;
  final DateTime? buildDate;
  final String? rawBuildString;

  const DeviceFirmwareInfo({
    this.version,
    this.buildDate,
    this.rawBuildString,
  });
}

/// Service managing firmware release discovery, date verification, and SHA-256 integrity validation.
class FirmwareService {
  static const String keyInstalledDate = 'hk_installed_firmware_date';
  static const String keyInstalledVersion = 'hk_installed_firmware_version';

  final http.Client _httpClient;
  final SharedPreferences? _prefs;

  FirmwareService({
    http.Client? httpClient,
    SharedPreferences? prefs,
  })  : _httpClient = httpClient ?? http.Client(),
        _prefs = prefs;

  /// Fetches the latest published firmware metadata from backend REST API
  /// or falls back to an HTTP HEAD request against the direct S3 URL.
  Future<FirmwareReleaseModel> fetchLatestRelease({
    String? backendUrl,
    String? token,
    String? fallbackS3Url,
  }) async {
    final base = (backendUrl ?? AppConfig.backendBaseUrl).trim().replaceAll(RegExp(r'/+$'), '');
    final endpoint = '$base/api/v1/firmware/latest';

    try {
      final headers = <String, String>{
        'Accept': 'application/json',
      };
      if (token != null && token.trim().isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await _httpClient.get(
        Uri.parse(endpoint),
        headers: headers,
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return FirmwareReleaseModel.fromJson(data);
      }
    } catch (_) {
      // Fallback to direct HEAD request below
    }

    // Direct HTTP HEAD fallback against AWS S3
    final s3Url = fallbackS3Url ??
        'https://healthkicks-firmware-releases.s3.eu-north-1.amazonaws.com/firmware/esp32s3/latest/firmware.bin';
    try {
      final headRes = await _httpClient.head(
        Uri.parse(s3Url),
      ).timeout(const Duration(seconds: 8));

      final lastModHeader = headRes.headers['last-modified'];
      final metaBuiltAt = headRes.headers['x-amz-meta-built_at'];
      DateTime releaseDate = DateTime.now().toUtc();

      if (metaBuiltAt != null && metaBuiltAt.trim().isNotEmpty) {
        releaseDate = FirmwareReleaseModel.parseUtcDateTime(metaBuiltAt);
      } else if (lastModHeader != null) {
        try {
          releaseDate = HttpDate.parse(lastModHeader).toUtc();
        } catch (_) {}
      }

      final contentLength = int.tryParse(headRes.headers['content-length'] ?? '') ?? 0;
      final metaSha256 = headRes.headers['x-amz-meta-sha256'] ?? '';
      final metaVersion = headRes.headers['x-amz-meta-version'] ?? 'v1.2.1-esp32s3';

      return FirmwareReleaseModel(
        version: metaVersion,
        downloadUrl: s3Url,
        sha256: metaSha256,
        sizeBytes: contentLength,
        expiresInSeconds: 3600,
        releaseDate: releaseDate,
      );
    } catch (e) {
      throw Exception('Unable to fetch firmware release information: $e');
    }
  }

  /// Reads firmware version and build date from connected BLE footwear via DIS (0x180A).
  Future<DeviceFirmwareInfo> readDeviceFirmwareInfo(BluetoothDevice device) async {
    String? version;
    DateTime? buildDate;
    String? rawBuildStr;

    try {
      final services = device.servicesList.isNotEmpty
          ? device.servicesList
          : await device.discoverServices();
      for (final service in services) {
        final sUuid = service.uuid.toString().toLowerCase();
        if (sUuid == BleConstants.disServiceUuid || sUuid.contains('180a')) {
          for (final char in service.characteristics) {
            final cUuid = char.uuid.toString().toLowerCase();
            if (cUuid == BleConstants.firmwareRevisionCharUuid || cUuid.contains('2a26')) {
              try {
                final bytes = await char.read();
                version = utf8.decode(bytes).trim();
              } catch (_) {}
            } else if (cUuid == BleConstants.softwareRevisionCharUuid || cUuid.contains('2a28')) {
              try {
                final bytes = await char.read();
                rawBuildStr = utf8.decode(bytes).trim();
                buildDate = parseBuildTimestamp(rawBuildStr);
              } catch (_) {}
            }
          }
        }
      }
    } catch (_) {}

    return DeviceFirmwareInfo(
      version: version,
      buildDate: buildDate,
      rawBuildString: rawBuildStr,
    );
  }

  /// Parses compilation string (ex: "Oct 11 2026 10:40:00" or ISO "2026-10-11T10:40:00Z").
  static DateTime? parseBuildTimestamp(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final iso = DateTime.tryParse(raw.trim());
    if (iso != null) return iso.toUtc();

    // Parse standard C __DATE__ " " __TIME__ format: "Mmm dd yyyy HH:mm:ss"
    final regex = RegExp(r'^([A-Za-z]{3})\s+(\d{1,2})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})$');
    final match = regex.firstMatch(raw.trim());
    if (match != null) {
      const months = {
        'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
        'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
      };
      final mStr = match.group(1)!;
      final month = months[mStr] ?? 1;
      final day = int.parse(match.group(2)!);
      final year = int.parse(match.group(3)!);
      final hour = int.parse(match.group(4)!);
      final min = int.parse(match.group(5)!);
      final sec = int.parse(match.group(6)!);
      // __DATE__ and __TIME__ is compilation time generated on the host machine in local wall-clock time
      return DateTime(year, month, day, hour, min, sec).toUtc();
    }
    return null;
  }

  /// Loads the persisted installation date from SharedPreferences.
  Future<DateTime?> getLocalInstalledDate() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final raw = prefs.getString(keyInstalledDate);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  /// Loads the persisted installed version from SharedPreferences.
  Future<String?> getLocalInstalledVersion() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    return prefs.getString(keyInstalledVersion);
  }

  /// Persists newly flashed firmware date and version.
  Future<void> saveLocalInstalledFirmware({
    required DateTime installedDate,
    required String version,
  }) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setString(keyInstalledDate, installedDate.toUtc().toIso8601String());
    await prefs.setString(keyInstalledVersion, version);
  }

  /// Compares cloud release publication date with installed firmware date.
  /// Returns `true` if the cloud release is strictly more recent than the installed version.
  bool isCloudReleaseNewer({
    required DateTime cloudReleaseDate,
    DateTime? installedDate,
  }) {
    if (installedDate == null) {
      // No local/device date found: assume update is available
      return true;
    }
    // Return true only if cloud release is after installed date (ignoring sub-second drift)
    return cloudReleaseDate.difference(installedDate).inSeconds > 2;
  }

  /// Verifies SHA-256 cryptographic digest of downloaded binary bytes.
  bool verifySha256({
    required Uint8List binaryBytes,
    required String expectedSha256,
  }) {
    if (expectedSha256.trim().isEmpty) {
      return true; // No hash provided to check against
    }
    final computed = sha256.convert(binaryBytes).toString().toLowerCase();
    return computed == expectedSha256.trim().toLowerCase();
  }

  /// Computes SHA-256 lowercase hex string.
  String computeSha256(Uint8List binaryBytes) {
    return sha256.convert(binaryBytes).toString().toLowerCase();
  }
}

