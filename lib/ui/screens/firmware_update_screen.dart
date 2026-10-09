import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:http/http.dart' as http;
import '../../services/ble/ble_ota_service.dart';

/// Screen managing firmware selection and Over-The-Air (OTA) flashing over BLE GATT.
class FirmwareUpdateScreen extends StatefulWidget {
  final BluetoothDevice? device;
  final String currentFirmwareVersion;
  final BleOtaService? otaService;

  static const String defaultFirmwareUrl =
      'https://healthkicks-firmware-releases.s3.eu-north-1.amazonaws.com/firmware/esp32s3/latest/firmware.bin';

  const FirmwareUpdateScreen({
    super.key,
    this.device,
    this.currentFirmwareVersion = 'v1.2.0-esp32s3',
    this.otaService,
  });

  @override
  State<FirmwareUpdateScreen> createState() => _FirmwareUpdateScreenState();
}

class _FirmwareUpdateScreenState extends State<FirmwareUpdateScreen> {
  late final BleOtaService _otaService;
  StreamSubscription<BleOtaProgress>? _otaSubscription;

  Uint8List? _selectedFirmwareBytes;
  String? _selectedFileName;
  final String _targetFirmwareVersion = 'v1.2.1-esp32s3';

  final TextEditingController _urlController =
      TextEditingController(text: FirmwareUpdateScreen.defaultFirmwareUrl);
  final TextEditingController _customPathController = TextEditingController();
  bool _isDownloading = false;

  BleOtaProgress _progress =
      const BleOtaProgress(status: BleOtaStatus.idle);

  @override
  void initState() {
    super.initState();
    _otaService = widget.otaService ?? BleOtaService();
    _otaSubscription = _otaService.progressStream.listen((prog) {
      if (mounted) {
        setState(() {
          _progress = prog;
        });
      }
    });
  }

  @override
  void dispose() {
    _otaSubscription?.cancel();
    _urlController.dispose();
    _customPathController.dispose();
    if (widget.otaService == null) {
      _otaService.dispose();
    }
    super.dispose();
  }

  Future<void> _loadFromLocalPath(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fichier introuvable : $path'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _selectedFirmwareBytes = bytes;
      _selectedFileName = file.uri.pathSegments.last;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Fichier chargé (${(bytes.length / 1024).toStringAsFixed(1)} Ko)'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _downloadFromUrl(String url) async {
    if (url.trim().isEmpty) return;

    setState(() {
      _isDownloading = true;
    });

    try {
      final response = await http.get(Uri.parse(url.trim()));
      if (response.statusCode == 200) {
        if (!mounted) return;
        setState(() {
          _selectedFirmwareBytes = response.bodyBytes;
          _selectedFileName = url.split('/').last.split('?').first;
          if (_selectedFileName!.isEmpty) {
            _selectedFileName = 'firmware_downloaded.bin';
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Téléchargement réussi (${(_selectedFirmwareBytes!.length / 1024).toStringAsFixed(1)} Ko)'),
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
          // 1. Device Info Card
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
                          'Version installée : ${widget.currentFirmwareVersion}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 2. Target Firmware Selection Card
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
                    'Sélectionnez le binaire compilé (ex. PlatformIO firmware.bin) à injecter dans le slot OTA inactif.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Selected File Badge
                  if (_selectedFirmwareBytes != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                      ),
                      child: Row(
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
                              });
                            },
                          ),
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
                            : const Text('Télécharger'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Option B: Local path
                  Text(
                    'Ou charger un fichier local (.bin)',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Option C: Local path
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _customPathController,
                          decoration: InputDecoration(
                            hintText: 'Chemin local (.bin)...',
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            prefixIcon: const Icon(Icons.folder_open, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: isUpdating
                            ? null
                            : () => _loadFromLocalPath(_customPathController.text),
                        child: const Text('Charger'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 3. Trigger Flash Button
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
            onPressed: (!hasDevice || _selectedFirmwareBytes == null || isUpdating)
                ? null
                : _startFlashing,
          ),
        ],
      ),
    );
  }
}
