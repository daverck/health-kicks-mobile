import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:http/http.dart' as http;
import '../../models/firmware_release_model.dart';
import '../../services/api/api_headers.dart';
import '../../services/auth/auth_service.dart';
import '../../services/ble/ble_connection_manager.dart';
import '../../services/ble/ble_ota_service.dart';
import '../../services/firmware/firmware_service.dart';
import '../widgets/firmware/firmware_binary_picker_card.dart';
import '../widgets/firmware/firmware_cloud_release_card.dart';
import '../widgets/firmware/firmware_device_info_card.dart';
import '../widgets/firmware/ota_progress_dialog.dart';
import '../widgets/firmware/reconnection_banner.dart';

/// Screen allowing the user to select or download an ESP32-S3 firmware binary,
/// verify its cryptographic SHA-256 fingerprint, and flash it over BLE OTA.
class FirmwareUpdateScreen extends StatefulWidget {
  final BluetoothDevice? device;
  final String currentFirmwareVersion;
  final BleOtaService? otaService;
  final FirmwareService? firmwareService;
  final AuthService? authService;
  final BleConnectionManager? bleManager;
  final String? targetDeviceId;
  final Future<void> Function()? onReconnect;

  static const String defaultFirmwareUrl =
      'https://healthkicks-firmware-releases.s3.eu-north-1.amazonaws.com/firmware/esp32s3/latest/firmware.bin';

  const FirmwareUpdateScreen({
    super.key,
    this.device,
    this.currentFirmwareVersion = 'v1.2.0-esp32s3',
    this.otaService,
    this.firmwareService,
    this.authService,
    this.bleManager,
    this.targetDeviceId,
    this.onReconnect,
  });

  @override
  State<FirmwareUpdateScreen> createState() => _FirmwareUpdateScreenState();
}

class _FirmwareUpdateScreenState extends State<FirmwareUpdateScreen> {
  late final BleOtaService _otaService;
  late final FirmwareService _firmwareService;
  late final TextEditingController _urlController;

  BleOtaProgress _progress = BleOtaProgress(status: BleOtaStatus.idle);
  StreamSubscription<BleOtaProgress>? _otaSubscription;
  StreamSubscription<BleConnectionStatus>? _bleStatusSub;

  Uint8List? _selectedFirmwareBytes;
  String? _selectedFileName;
  String? _computedSha256;
  bool? _isSha256Valid;

  bool _isCheckingCloud = false;
  String? _cloudCheckError;
  FirmwareReleaseModel? _cloudRelease;
  bool _isCloudReleaseNewer = false;
  bool _isDownloading = false;

  late String _installedFirmwareVersion;
  DateTime? _installedFirmwareDate;
  String _targetFirmwareVersion = 'v1.2.1-esp32s3';

  bool _isReconnecting = false;
  bool _reconnectSuccess = false;
  String? _reconnectMessage;

  @override
  void initState() {
    super.initState();
    _otaService = widget.otaService ?? BleOtaService();
    _firmwareService = widget.firmwareService ?? FirmwareService();
    _installedFirmwareVersion = widget.currentFirmwareVersion;

    _urlController = TextEditingController(
      text: FirmwareUpdateScreen.defaultFirmwareUrl,
    );

    _otaSubscription = _otaService.progressStream.listen((prog) {
      if (mounted) {
        setState(() {
          _progress = prog;
        });
        if (prog.status == BleOtaStatus.success) {
          _onOtaSuccess();
        }
      }
    });

    _loadInstalledDeviceInfoAndCheckCloud();
  }

  Future<void> _loadInstalledDeviceInfoAndCheckCloud() async {
    try {
      final savedVer = await _firmwareService.getLocalInstalledVersion();
      final savedDate = await _firmwareService.getLocalInstalledDate();
      if (mounted && savedVer != null) {
        setState(() {
          _installedFirmwareVersion = savedVer;
          _installedFirmwareDate = savedDate;
        });
      }

      if (widget.device != null) {
        final info = await _firmwareService.readDeviceFirmwareInfo(widget.device!);
        if (mounted && info.version != null && info.version!.isNotEmpty) {
          setState(() {
            _installedFirmwareVersion = info.version!;
            if (info.buildDate != null) {
              _installedFirmwareDate = info.buildDate;
            }
          });
          unawaited(
            _firmwareService.saveLocalInstalledFirmware(
              installedDate: info.buildDate ?? _installedFirmwareDate ?? DateTime.now().toUtc(),
              version: info.version!,
            ),
          );
        }
      }
    } catch (_) {}

    await _checkCloudRelease();
  }

  Future<void> _checkCloudRelease() async {
    if (!mounted) return;
    setState(() {
      _isCheckingCloud = true;
      _cloudCheckError = null;
    });

    try {
      String? token;
      if (widget.authService != null) {
        try {
          token = await widget.authService!.getValidAccessToken();
        } catch (_) {}
      }

      final release = await _firmwareService.fetchLatestRelease(
        backendUrl: widget.authService?.backendBaseUrl,
        token: token,
        fallbackS3Url: _urlController.text.trim().isNotEmpty
            ? _urlController.text.trim()
            : FirmwareUpdateScreen.defaultFirmwareUrl,
      );

      if (!mounted) return;
      final isNewer = _firmwareService.isCloudReleaseNewer(
        cloudReleaseDate: release.releaseDate,
        installedDate: _installedFirmwareDate,
        cloudVersion: release.version,
        installedVersion: _installedFirmwareVersion,
      );

      setState(() {
        _cloudRelease = release;
        _targetFirmwareVersion = release.version;
        if (release.downloadUrl.isNotEmpty) {
          _urlController.text = release.downloadUrl;
        }
        _isCloudReleaseNewer = isNewer;
        _isCheckingCloud = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cloudCheckError = e.toString();
        _isCheckingCloud = false;
      });
    }
  }

  Future<void> _onOtaSuccess() async {
    final now = DateTime.now().toUtc();
    await _firmwareService.saveLocalInstalledFirmware(
      installedDate: now,
      version: _targetFirmwareVersion,
    );
    if (mounted) {
      setState(() {
        _installedFirmwareVersion = _targetFirmwareVersion;
        _installedFirmwareDate = now;
      });
    }

    unawaited(_triggerAutoReconnectAfterReboot());
  }

  Future<void> _triggerAutoReconnectAfterReboot() async {
    if (widget.onReconnect == null && widget.bleManager == null) return;

    if (mounted) {
      setState(() {
        _isReconnecting = true;
        _reconnectSuccess = false;
        _reconnectMessage = 'Attente du redémarrage de la chaussure (3s)...';
      });
    }

    await Future<void>.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    setState(() {
      _reconnectMessage = 'Recherche et reconnexion Bluetooth en cours...';
    });

    _bleStatusSub?.cancel();
    if (widget.bleManager != null) {
      _bleStatusSub = widget.bleManager!.statusStream.listen((status) async {
        if (status == BleConnectionStatus.ready) {
          final connectedDev = widget.bleManager!.connectedDevice;
          if (connectedDev != null) {
            try {
              final info = await _firmwareService.readDeviceFirmwareInfo(connectedDev);
              if (info.version != null && info.version!.isNotEmpty && mounted) {
                setState(() {
                  _installedFirmwareVersion = info.version!;
                  if (info.buildDate != null) {
                    _installedFirmwareDate = info.buildDate;
                  }
                });
              }
            } catch (_) {}
          }
          if (mounted) {
            setState(() {
              _isReconnecting = false;
              _reconnectSuccess = true;
              _reconnectMessage = 'Chaussure reconnectée avec succès ! (version $_installedFirmwareVersion)';
            });
          }
          _bleStatusSub?.cancel();
        }
      });
    }

    try {
      if (widget.onReconnect != null) {
        await widget.onReconnect!();
      } else if (widget.bleManager != null) {
        await widget.bleManager!.startAutoConnect(
          targetDeviceId: widget.targetDeviceId,
          timeout: const Duration(seconds: 45),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isReconnecting = false;
          _reconnectMessage = 'Reconnexion manuelle requise : $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _otaSubscription?.cancel();
    _bleStatusSub?.cancel();
    _urlController.dispose();
    super.dispose();
  }

  Future<bool> _showForceDownloadConfirmationDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue),
              SizedBox(width: 8),
              Expanded(child: Text('Firmware déjà à jour')),
            ],
          ),
          content: Text(
            'La version installée sur la chaussure ($_installedFirmwareVersion) est déjà identique ou plus récente que la release cloud sélectionnée (${_cloudRelease?.version}).\n\n'
            'Souhaitez-vous forcer le re-téléchargement et le flashage de cette version ?',
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Forcer le téléchargement'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _downloadFromUrl(String url) async {
    if (url.trim().isEmpty) return;

    if (!_isCloudReleaseNewer && _installedFirmwareDate != null) {
      final confirmed = await _showForceDownloadConfirmationDialog();
      if (!confirmed) {
        return;
      }
    }

    setState(() {
      _isDownloading = true;
      _computedSha256 = null;
      _isSha256Valid = null;
    });

    try {
      final response = await http.get(
        Uri.parse(url.trim()),
        headers: {'X-Correlation-ID': generateCorrelationId()},
      );
      if (response.statusCode == 200) {
        if (!mounted) return;
        final downloadedBytes = response.bodyBytes;

        final actualHash = _firmwareService.computeSha256(downloadedBytes);
        final expectedHash = _cloudRelease?.sha256.trim() ?? '';
        final bool isValid;
        if (expectedHash.isNotEmpty) {
          isValid = actualHash == expectedHash.toLowerCase();
        } else {
          isValid = true;
        }

        final fileName = url.split('/').last.split('?').first;
        setState(() {
          _selectedFirmwareBytes = downloadedBytes;
          _selectedFileName = fileName.isNotEmpty ? fileName : 'firmware.bin';
          _computedSha256 = actualHash;
          _isSha256Valid = isValid;
          _isDownloading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isValid
                  ? 'Binaire téléchargé avec succès (${(downloadedBytes.length / 1024).toStringAsFixed(1)} Ko). SHA-256 certifié !'
                  : 'Alerte : Le hash SHA-256 calculé ne correspond pas à l\'empreinte officielle.',
            ),
            backgroundColor: isValid ? Colors.green : Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      } else {
        throw Exception('Code HTTP ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Échec du téléchargement : $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _startFlashing() async {
    if (widget.device == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucune chaussure connectée en BLE.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_selectedFirmwareBytes == null || _selectedFirmwareBytes!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner ou charger un fichier binaire.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_isSha256Valid == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Impossible de flasher un binaire dont l\'empreinte SHA-256 est corrompue.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    _showProgressModal();

    await _otaService.startUpdate(
      device: widget.device!,
      firmwareBytes: _selectedFirmwareBytes!,
    );
  }

  void _showProgressModal() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => OtaProgressDialog(
        progressStream: _otaService.progressStream,
        initialProgress: _progress,
        onAbort: () => _otaService.abort(),
        isReconnecting: _isReconnecting,
        reconnectSuccess: _reconnectSuccess,
        reconnectMessage: _reconnectMessage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasDevice = widget.device != null;
    final isUpdating = _otaService.isUpdating;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mise à jour Firmware OTA'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ReconnectionBanner(
            isReconnecting: _isReconnecting,
            reconnectSuccess: _reconnectSuccess,
            reconnectMessage: _reconnectMessage,
          ),
          FirmwareDeviceInfoCard(
            device: widget.device,
            installedVersion: _installedFirmwareVersion,
            installedDate: _installedFirmwareDate,
          ),
          const SizedBox(height: 16),
          FirmwareCloudReleaseCard(
            isCheckingCloud: _isCheckingCloud,
            cloudCheckError: _cloudCheckError,
            cloudRelease: _cloudRelease,
            isCloudReleaseNewer: _isCloudReleaseNewer,
            installedVersion: _installedFirmwareVersion,
            onCheckCloud: _checkCloudRelease,
          ),
          const SizedBox(height: 16),
          FirmwareBinaryPickerCard(
            selectedFirmwareBytes: _selectedFirmwareBytes,
            selectedFileName: _selectedFileName,
            targetFirmwareVersion: _targetFirmwareVersion,
            computedSha256: _computedSha256,
            isSha256Valid: _isSha256Valid,
            onClearFile: () {
              setState(() {
                _selectedFirmwareBytes = null;
                _selectedFileName = null;
                _computedSha256 = null;
                _isSha256Valid = null;
              });
            },
            urlController: _urlController,
            isDownloading: _isDownloading,
            isUpdating: isUpdating,
            onDownloadFromUrl: _downloadFromUrl,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.cloud_upload_outlined),
            label: const Text(
              'Lancer la Mise à Jour OTA',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            onPressed: (!hasDevice ||
                    _selectedFirmwareBytes == null ||
                    isUpdating ||
                    _isSha256Valid == false)
                ? null
                : _startFlashing,
          ),
        ],
      ),
    );
  }
}
