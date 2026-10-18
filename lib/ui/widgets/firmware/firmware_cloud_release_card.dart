import 'package:flutter/material.dart';
import '../../../models/firmware_release_model.dart';

/// Card showing latest official firmware release from Cloud backend/GitHub with metadata and comparison badge.
class FirmwareCloudReleaseCard extends StatelessWidget {
  final bool isCheckingCloud;
  final String? cloudCheckError;
  final FirmwareReleaseModel? cloudRelease;
  final bool isCloudReleaseNewer;
  final String installedVersion;
  final VoidCallback? onCheckCloud;

  const FirmwareCloudReleaseCard({
    super.key,
    required this.isCheckingCloud,
    this.cloudCheckError,
    this.cloudRelease,
    required this.isCloudReleaseNewer,
    required this.installedVersion,
    this.onCheckCloud,
  });

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return 'Inconnue';
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year;
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min';
  }

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
                  icon: isCheckingCloud
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 20),
                  onPressed: isCheckingCloud ? null : onCheckCloud,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (isCheckingCloud)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Text('Recherche de la dernière version sur le serveur...'),
              )
            else if (cloudCheckError != null)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade700),
                ),
                child: Text(
                  'Information Cloud indisponible : $cloudCheckError',
                  style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                ),
              )
            else if (cloudRelease != null) ...[
              if (isCloudReleaseNewer)
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
                          'Nouvelle version disponible (${cloudRelease!.version}) !',
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
                          'Votre firmware est à jour ($installedVersion).',
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
                '• Version Cloud : ${cloudRelease!.version}\n'
                '• Date de publication : ${_formatDateTime(cloudRelease!.releaseDate)}\n'
                '• Taille du binaire : ${(cloudRelease!.sizeBytes / 1024).toStringAsFixed(1)} Ko'
                '${cloudRelease!.sha256.isNotEmpty ? '\n• Empreinte SHA-256 attendue : ${cloudRelease!.sha256.substring(0, 16)}...' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
