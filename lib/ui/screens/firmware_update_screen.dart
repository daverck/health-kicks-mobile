import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:http/http.dart' as http;
import '../../models/firmware_release_model.dart';
import '../../services/auth/auth_service.dart';
import '../../services/ble/ble_connection_manager.dart';
import '../../services/ble/ble_ota_service.dart';
import '../../services/firmware/firmware_service.dart';

/// Screen managing firmware discovery, release date & SHA-256 validation,
/// and Over-The-Air (OTA) flashing over BLE GATT.
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
  StreamSubscription<BleOtaProgress>? _otaSubscription;
  StreamSubscription<BleConnectionStatus>? _bleStatusSub;
  bool _isReconnecting = false;
  bool _reconnectSuccess = false;
  String? _reconnectMessage;

  Uint8List? _selectedFirmwareBytes;
  String? _selectedFileName;
  String _targetFirmwareVersion = 'v1.2.1-esp32s3';

  late String _installedFirmwareVersion;
  DateTime? _installedFirmwareDate;

  FirmwareReleaseModel? _cloudRelease;
  bool _isCheckingCloud = false;
  String? _cloudCheckError;
  bool _isCloudReleaseNewer = false;

  String? _computedSha256;
  bool? _isSha256Valid;

  final TextEditingController _urlController =
      TextEditingController(text: FirmwareUpdateScreen.defaultFirmwareUrl);
  bool _isDownloading = false;

  BleOtaProgress _progress =
      const BleOtaProgress(status: BleOtaStatus.idle);

  @override
  void initState() {
    super.initState();
    _otaService = widget.otaService ?? BleOtaService();
    _firmwareService = widget.firmwareService ?? FirmwareService();
    _installedFirmwareVersion = widget.currentFirmwareVersion;

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
    // 1. Try reading local storage first
    try {
      final localDate = await _firmwareService.getLocalInstalledDate();
      final localVer = await _firmwareService.getLocalInstalledVersion();
      if (mounted) {
        setState(() {
          if (localDate != null) _installedFirmwareDate = localDate;
          if (localVer != null && localVer.isNotEmpty) _installedFirmwareVersion = localVer;
        });
      }
    } catch (_) {}

    // 2. Try reading from connected BLE device via Device Information Service (0x180A)
    if (widget.device != null) {
      try {
        final devInfo = await _firmwareService.readDeviceFirmwareInfo(widget.device!);
        if (mounted) {
          setState(() {
            if (devInfo.version != null && devInfo.version!.isNotEmpty) {
              _installedFirmwareVersion = devInfo.version!;
            }
            if (devInfo.buildDate != null) {
              _installedFirmwareDate = devInfo.buildDate!;
            }
          });
        }
      } catch (_) {}
    }

    // 3. Query Cloud for the latest official firmware metadata
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
    final newDate = _cloudRelease?.releaseDate ?? DateTime.now().toUtc();
    final newVer = _cloudRelease?.version ?? _targetFirmwareVersion;

    try {
      await _firmwareService.saveLocalInstalledFirmware(
        installedDate: newDate,
        version: newVer,
      );
    } catch (_) {}

    if (mounted) {
      setState(() {
        _installedFirmwareDate = newDate;
        _installedFirmwareVersion = newVer;
        _isCloudReleaseNewer = false;
      });
    }

    // Trigger auto-reconnection sequence after ESP32-S3 reboot
    unawaited(_triggerAutoReconnectAfterReboot());
  }

  Future<void> _triggerAutoReconnectAfterReboot() async {
    if (widget.onReconnect == null && widget.bleManager == null) return;

    if (mounted) {
      setState(() {
        _isReconnecting = true;
        _reconnectSuccess = false;
        _reconnectMessage = 'Attente du redémarrage de la chaussure (4s)...';
      });
    }

    // Wait 4 seconds for footwear hardware reboot (boot, CDC delay, IMU self-test, NimBLE startup)
    await Future.delayed(const Duration(seconds: 4));
    if (!mounted) return;

    setState(() {
      _reconnectMessage = 'Recherche et reconnexion Bluetooth en cours...';
    });

    final manager = widget.bleManager;
    if (manager != null) {
      await _bleStatusSub?.cancel();
      _bleStatusSub = manager.statusStream.listen((status) async {
        if (status == BleConnectionStatus.ready && manager.connectedDevice != null) {
          // Wait briefly to allow main client service initialization to complete cleanly without GATT collision
          await Future.delayed(const Duration(milliseconds: 400));
          if (manager.connectedDevice != null) {
            try {
              final info = await _firmwareService.readDeviceFirmwareInfo(manager.connectedDevice!);
              if (info.version != null && info.version!.isNotEmpty && mounted) {
                setState(() {
                  _installedFirmwareVersion = info.version!;
                  _installedFirmwareDate = info.buildDate ?? _installedFirmwareDate;
                });
              }
            } catch (_) {}
          }
          if (mounted) {
            setState(() {
              _isReconnecting = false;
              _reconnectSuccess = true;
              _reconnectMessage =
                  'Chaussure reconnectée avec succès ! (version ${_installedFirmwareVersion.isNotEmpty ? _installedFirmwareVersion : "active"})';
            });
          }
          await _bleStatusSub?.cancel();
          _bleStatusSub = null;
        }
      });
    }

    try {
      if (widget.onReconnect != null) {
        await widget.onReconnect!();
      } else if (manager != null) {
        await manager.startAutoConnect(
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
    _bleStatusSub?.cancel();
    _otaSubscription?.cancel();
    _urlController.dispose();
    if (widget.otaService == null) {
      _otaService.dispose();
    }
    super.dispose();
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return 'Inconnue (non horodaté)';
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year;
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$d/$m/$y à $h:$min (heure locale)';
  }

  Future<bool> _showForceDownloadConfirmationDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue),
            SizedBox(width: 8),
            Text('Firmware à jour'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Le firmware actuellement installé sur la chaussure '
              '(${_installedFirmwareDate != null ? _formatDateTime(_installedFirmwareDate) : _installedFirmwareVersion}) '
              'est déjà identique ou plus récent que la release Cloud '
              '(${_cloudRelease != null ? _formatDateTime(_cloudRelease!.releaseDate) : "inconnue"}).',
            ),
            const SizedBox(height: 12),
            const Text(
              'Souhaitez-vous tout de même forcer le téléchargement et réinstaller cette version ?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
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
      ),
    );
    return result ?? false;
  }

  Future<void> _downloadFromUrl(String url) async {
    if (url.trim().isEmpty) return;

    // Check release publication date constraint before downloading
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
      final response = await http.get(Uri.parse(url.trim()));
      if (response.statusCode == 200) {
        if (!mounted) return;
        final downloadedBytes = response.bodyBytes;

        // Compute cryptographic SHA-256 digest of downloaded bytes
        final actualHash = _firmwareService.computeSha256(downloadedBytes);

        // Verify with expected cloud SHA-256 if known
        final expectedHash = _cloudRelease?.sha256.trim() ?? '';
        final bool isValid;
        if (expectedHash.isNotEmpty) {
          isValid = actualHash == expectedHash.toLowerCase();
        } else {
          isValid = true; // No official hash to verify against
        }

        if (!isValid) {
          // Cryptographic integrity failure!
          setState(() {
            _selectedFirmwareBytes = null;
            _selectedFileName = null;
            _computedSha256 = actualHash;
            _isSha256Valid = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Échec d\'intégrité SHA-256 : l\'empreinte téléchargée ($actualHash) '
                'ne correspond pas à l\'empreinte officielle ($expectedHash). Téléchargement rejeté.',
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 6),
            ),
          );
          return;
        }

        // SHA-256 verified successfully!
        setState(() {
          _selectedFirmwareBytes = downloadedBytes;
          _computedSha256 = actualHash;
          _isSha256Valid = true;
          _selectedFileName = url.split('/').last.split('?').first;
          if (_selectedFileName!.isEmpty) {
            _selectedFileName = 'firmware_downloaded.bin';
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Téléchargement réussi (${(downloadedBytes.length / 1024).toStringAsFixed(1)} Ko) · '
              'Intégrité SHA-256 validée !',
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur de téléchargement : $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
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

    // Open non-dismissible modal during update
    _showProgressModal();

    await _otaService.startUpdate(
      device: widget.device!,
      firmwareBytes: _selectedFirmwareBytes!,
    );
  }

  void _showProgressModal() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StreamBuilder<BleOtaProgress>(
          stream: _otaService.progressStream,
          initialData: _progress,
          builder: (context, snapshot) {
            final prog = snapshot.data ?? _progress;
            final isBusy = prog.status == BleOtaStatus.preparing ||
                prog.status == BleOtaStatus.transferring ||
                prog.status == BleOtaStatus.finalizing;
            final isDone = prog.status == BleOtaStatus.success;
            final isError = prog.status == BleOtaStatus.error ||
                prog.status == BleOtaStatus.aborted;

            final theme = Theme.of(context);
            return PopScope(
              canPop: !isBusy,
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: Row(
                  children: [
                    Icon(
                      isDone
                          ? Icons.check_circle
                          : isError
                              ? Icons.error_outline
                              : Icons.system_update_alt,
                      color: isDone
                          ? Colors.green
                          : isError
                              ? Colors.redAccent
                              : theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isDone
                            ? 'Mise à jour réussie'
                            : isError
                                ? 'Erreur de mise à jour'
                                : 'Mise à jour en cours',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prog.message ?? 'Préparation du transfert...',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isError
                            ? Colors.redAccent
                            : isDone
                                ? Colors.green
                                : theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: prog.status == BleOtaStatus.preparing
                          ? null
                          : prog.progress,
                      minHeight: 10,
                      borderRadius: BorderRadius.circular(5),
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDone
                            ? Colors.green
                            : isError
                                ? Colors.redAccent
                                : theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${(prog.progress * 100).toStringAsFixed(1)} %',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          '${(prog.bytesSent / 1024).toStringAsFixed(0)} / ${(prog.totalBytes / 1024).toStringAsFixed(0)} Ko',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    if (prog.status == BleOtaStatus.transferring) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Débit : ${prog.speedKbps.toStringAsFixed(1)} Ko/s',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (prog.estimatedTimeRemaining != null)
                            Text(
                              'Restant : ~${prog.estimatedTimeRemaining!.inSeconds} s',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (isDone) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          'L\'ESP32-S3 a validé la nouvelle partition et redémarre automatiquement.',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.brightness == Brightness.dark
                                ? Colors.green.shade300
                                : Colors.green.shade800,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (_isReconnecting || _reconnectSuccess || _reconnectMessage != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _reconnectSuccess
                                ? Colors.teal.withValues(alpha: 0.12)
                                : _isReconnecting
                                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
                                    : Colors.orange.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _reconnectSuccess
                                  ? Colors.teal
                                  : _isReconnecting
                                      ? theme.colorScheme.primary.withValues(alpha: 0.3)
                                      : Colors.orange,
                            ),
                          ),
                          child: Row(
                            children: [
                              if (_isReconnecting)
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              else if (_reconnectSuccess)
                                const Icon(Icons.check_circle, color: Colors.teal, size: 18)
                              else
                                const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _reconnectMessage ?? '',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: _reconnectSuccess
                                        ? Colors.teal.shade800
                                        : _isReconnecting
                                            ? theme.colorScheme.onSurface
                                            : Colors.orange.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
                actions: [
                  if (isBusy && prog.status != BleOtaStatus.finalizing)
                    TextButton(
                      onPressed: () {
                        _otaService.abort();
                      },
                      child: const Text(
                        'Annuler',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  if (!isBusy)
                    FilledButton(
                      onPressed: () {
                        Navigator.of(dialogCtx).pop();
                      },
                      child: Text(isDone ? 'Terminer' : 'Fermer'),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDevice = widget.device != null;
    final isUpdating = _otaService.isUpdating;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mise à jour Firmware OTA'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 0. Auto-reconnection status banner if active
          if (_isReconnecting || _reconnectSuccess || (_reconnectMessage != null && _reconnectMessage!.isNotEmpty))
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _reconnectSuccess
                    ? Colors.teal.withValues(alpha: 0.15)
                    : _isReconnecting
                        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                        : Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _reconnectSuccess
                      ? Colors.teal
                      : _isReconnecting
                          ? theme.colorScheme.primary
                          : Colors.orange,
                ),
              ),
              child: Row(
                children: [
                  if (_isReconnecting)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    )
                  else if (_reconnectSuccess)
                    const Icon(Icons.check_circle, color: Colors.teal, size: 20)
                  else
                    const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _reconnectMessage ?? '',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _reconnectSuccess
                            ? Colors.teal.shade800
                            : _isReconnecting
                                ? theme.colorScheme.onSurface
                                : Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // 1. Device Info Card (Installed Version & Build/Install Date)
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: hasDevice ? Colors.green.shade100 : Colors.red.shade100,
                    child: Icon(
                      hasDevice ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                      color: hasDevice ? Colors.green.shade800 : Colors.red.shade800,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasDevice
                              ? widget.device!.platformName.isNotEmpty
                                  ? widget.device!.platformName
                                  : 'Chaussure Connectée (ESP32-S3)'
                              : 'Non connectée',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Version installée : $_installedFirmwareVersion',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.calendar_today_outlined, size: 13, color: theme.colorScheme.primary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Date firmware actif : ${_formatDateTime(_installedFirmwareDate)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 2. Cloud Release Status Card
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.cloud_sync_outlined, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Dernière Release Cloud',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      IconButton(
                        tooltip: 'Vérifier la dernière version',
                        icon: _isCheckingCloud
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh, size: 20),
                        onPressed: _isCheckingCloud ? null : _checkCloudRelease,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (_isCheckingCloud)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.0),
                      child: Text('Recherche de la dernière version sur le serveur...'),
                    )
                  else if (_cloudCheckError != null)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade700),
                      ),
                      child: Text(
                        'Information Cloud indisponible : $_cloudCheckError',
                        style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                      ),
                    )
                  else if (_cloudRelease != null) ...[
                    // Comparison Badge
                    if (_isCloudReleaseNewer)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade700),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.new_releases_outlined, color: Colors.blue, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Nouvelle version disponible (${_cloudRelease!.version}) !',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.blue,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.shade700),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Votre firmware est à jour ($_installedFirmwareVersion).',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    Text(
                      '• Version Cloud : ${_cloudRelease!.version}\n'
                      '• Date de publication : ${_formatDateTime(_cloudRelease!.releaseDate)}\n'
                      '• Taille du binaire : ${(_cloudRelease!.sizeBytes / 1024).toStringAsFixed(1)} Ko'
                      '${_cloudRelease!.sha256.isNotEmpty ? '\n• Empreinte SHA-256 attendue : ${_cloudRelease!.sha256.substring(0, 16)}...' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 3. Target Firmware Selection Card
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fichier Binaire Firmware (.bin)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Le fichier téléchargé sera vérifié par empreinte cryptographique SHA-256 avant le flashage.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Selected File Badge & SHA-256 Verification Badge
                  if (_selectedFirmwareBytes != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.description, color: theme.colorScheme.primary),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _selectedFileName ?? 'firmware.bin',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Text(
                                      '${(_selectedFirmwareBytes!.length / 1024).toStringAsFixed(1)} Ko · Cible: $_targetFirmwareVersion',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 20),
                                onPressed: () {
                                  setState(() {
                                    _selectedFirmwareBytes = null;
                                    _selectedFileName = null;
                                    _computedSha256 = null;
                                    _isSha256Valid = null;
                                  });
                                },
                              ),
                            ],
                          ),
                          if (_computedSha256 != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _isSha256Valid == true
                                    ? Colors.green.withValues(alpha: 0.15)
                                    : Colors.red.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _isSha256Valid == true ? Icons.verified : Icons.warning_amber,
                                    size: 16,
                                    color: _isSha256Valid == true ? Colors.green : Colors.red,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _isSha256Valid == true
                                          ? 'SHA-256 certifié : ${_computedSha256!.substring(0, 16)}...'
                                          : 'SHA-256 non conforme !',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: _isSha256Valid == true ? Colors.green : Colors.red,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.colorScheme.outlineVariant),
                      ),
                      child: Center(
                        child: Text(
                          'Aucun fichier sélectionné',
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),

                  // Option A: Download from Cloud S3 URL (Pre-filled by default)
                  Text(
                    'Télécharger depuis le Cloud (AWS S3) ou une URL',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _urlController,
                          decoration: InputDecoration(
                            hintText: 'https://.../firmware.bin',
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: const Icon(Icons.cloud_download_outlined, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: (_isDownloading || isUpdating)
                            ? null
                            : () => _downloadFromUrl(_urlController.text),
                        child: _isDownloading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                (!_isCloudReleaseNewer && _installedFirmwareDate != null)
                                    ? 'Télécharger'
                                    : 'Télécharger',
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 4. Trigger Flash Button
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
