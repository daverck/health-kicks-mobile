import 'package:material_ui/material_ui.dart';
import '../../../services/integrations/health_connect_service.dart';

/// Settings widget controlling health platform synchronization (Google Health Connect on Android / Apple HealthKit on iOS).
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
        final isIos = healthConnectService.isIos;
        final serviceName = healthConnectService.platformServiceName;

        final title = isIos ? 'Apple Santé (HealthKit)' : 'Google Health Connect';

        String subtitle = isIos
            ? 'Exporter les pas de la chaussure vers Apple Santé'
            : 'Exporter les pas de la chaussure vers vos applications de santé (Google Fit, etc.)';

        if (isEnabled && lastSync != null) {
          final timeStr = '${lastSync.toLocal().hour.toString().padLeft(2, '0')}:${lastSync.toLocal().minute.toString().padLeft(2, '0')}';
          subtitle = 'Actif • Dernière synchro : $timeStr';
        }

        final icon = isIos ? Icons.favorite_outline : Icons.health_and_safety_outlined;

        return SwitchListTile(
          secondary: Icon(
            icon,
            color: isEnabled ? theme.colorScheme.primary : Colors.grey,
            size: 28,
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600),
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
                  SnackBar(
                    content: Text('Synchronisation $serviceName désactivée.'),
                    duration: const Duration(seconds: 2),
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
                    content: Text('Synchronisation santé non supportée sur cet appareil.'),
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
                  SnackBar(
                    content: Text('Synchronisation $serviceName activée !'),
                    duration: const Duration(seconds: 2),
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
