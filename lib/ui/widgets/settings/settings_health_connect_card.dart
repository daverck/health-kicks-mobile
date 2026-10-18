import 'package:flutter/material.dart';
import '../../../services/integrations/health_connect_service.dart';

/// Settings widget controlling Google Health Connect synchronization.
class SettingsHealthConnectCard extends StatelessWidget {
  final HealthConnectService healthConnectService;

  const SettingsHealthConnectCard({
    super.key,
    required this.healthConnectService,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: healthConnectService,
      builder: (context, _) {
        final isEnabled = healthConnectService.isEnabled;
        final lastSync = healthConnectService.lastSyncTime;

        String subtitle = 'Exporter les pas de la chaussure vers vos applications de santé (Google Fit, etc.)';
        if (isEnabled && lastSync != null) {
          final timeStr = '${lastSync.toLocal().hour.toString().padLeft(2, '0')}:${lastSync.toLocal().minute.toString().padLeft(2, '0')}';
          subtitle = 'Actif • Dernière synchro : $timeStr';
        }

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isEnabled
                  ? theme.colorScheme.primary.withValues(alpha: 0.5)
                  : theme.dividerColor.withValues(alpha: 0.3),
            ),
          ),
          child: SwitchListTile(
            secondary: Icon(
              Icons.health_and_safety_outlined,
              color: isEnabled ? theme.colorScheme.primary : Colors.grey,
              size: 28,
            ),
            title: const Text(
              'Google Health Connect',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: isEnabled ? theme.colorScheme.primary : theme.textTheme.bodySmall?.color,
              ),
            ),
            value: isEnabled,
            onChanged: (bool value) async {
              if (!value) {
                await healthConnectService.setEnabled(false);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Synchronisation Google Health Connect désactivée.'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
                return;
              }

              // Checking status before enabling
              final status = await healthConnectService.checkInstallationStatus();
              if (status == HealthConnectInstallationStatus.notInstalled) {
                if (context.mounted) {
                  _showInstallDialog(context);
                }
                return;
              } else if (status == HealthConnectInstallationStatus.unsupportedPlatform) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Google Health Connect est réservé aux appareils Android.'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
                return;
              }

              // Request permissions
              final granted = await healthConnectService.requestWritePermissions();
              if (granted) {
                await healthConnectService.setEnabled(true);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Synchronisation Google Health Connect activée !'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Autorisation refusée par l\'utilisateur.'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                }
              }
            },
          ),
        );
      },
    );
  }

  void _showInstallDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.get_app_outlined, color: Colors.teal),
            SizedBox(width: 8),
            Text('Health Connect requis'),
          ],
        ),
        content: const Text(
          'L\'application Google Health Connect n\'est pas installée sur cet appareil.\n\n'
          'Souhaitez-vous ouvrir le Google Play Store pour l\'installer et activer la synchronisation ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Plus tard'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Installer'),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await healthConnectService.promptInstallHealthConnect();
            },
          ),
        ],
      ),
    );
  }
}
