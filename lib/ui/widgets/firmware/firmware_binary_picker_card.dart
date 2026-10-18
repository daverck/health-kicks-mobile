import 'dart:typed_data';
import 'package:flutter/material.dart';

/// Card allowing custom firmware binary selection, download via URL, and cryptographic SHA-256 fingerprint display.
class FirmwareBinaryPickerCard extends StatelessWidget {
  final Uint8List? selectedFirmwareBytes;
  final String? selectedFileName;
  final String targetFirmwareVersion;
  final String? computedSha256;
  final bool? isSha256Valid;
  final VoidCallback onClearFile;
  final TextEditingController urlController;
  final bool isDownloading;
  final bool isUpdating;
  final ValueChanged<String> onDownloadFromUrl;

  const FirmwareBinaryPickerCard({
    super.key,
    required this.selectedFirmwareBytes,
    required this.selectedFileName,
    required this.targetFirmwareVersion,
    required this.computedSha256,
    required this.isSha256Valid,
    required this.onClearFile,
    required this.urlController,
    required this.isDownloading,
    required this.isUpdating,
    required this.onDownloadFromUrl,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
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
            if (selectedFirmwareBytes != null)
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
                                selectedFileName ?? 'firmware.bin',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                '${(selectedFirmwareBytes!.length / 1024).toStringAsFixed(1)} Ko · Cible: $targetFirmwareVersion',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: onClearFile,
                        ),
                      ],
                    ),
                    if (computedSha256 != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isSha256Valid == true
                              ? Colors.green.withValues(alpha: 0.15)
                              : Colors.red.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSha256Valid == true ? Icons.verified : Icons.warning_amber,
                              size: 16,
                              color: isSha256Valid == true ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                isSha256Valid == true
                                    ? 'SHA-256 certifié : ${computedSha256!.substring(0, 16)}...'
                                    : 'SHA-256 non conforme !',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isSha256Valid == true ? Colors.green : Colors.red,
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

            // Download from Cloud S3 URL
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
                    controller: urlController,
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
                  onPressed: (isDownloading || isUpdating)
                      ? null
                      : () => onDownloadFromUrl(urlController.text),
                  child: isDownloading
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
          ],
        ),
      ),
    );
  }
}

