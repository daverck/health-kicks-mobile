import 'package:flutter/material.dart';

/// Top app bar for the HealthKicks gateway dashboard with device ID pill and quick navigation actions.
class DashboardAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String deviceId;
  final VoidCallback onOpenStepsHistory;
  final VoidCallback onOpenDetectionEventsHistory;
  final VoidCallback onOpenSettings;
  final VoidCallback? onLogout;

  const DashboardAppBar({
    super.key,
    required this.deviceId,
    required this.onOpenStepsHistory,
    required this.onOpenDetectionEventsHistory,
    required this.onOpenSettings,
    this.onLogout,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  void _showLogoutDialog(BuildContext context) {
    if (onLogout == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Déconnexion'),
        content: const Text('Voulez-vous vraiment vous déconnecter de votre session HealthKicks ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onLogout!();
            },
            child: const Text('Déconnexion'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppBar(
      title: const Text('HealthKicks BLE-to-MQTT Gateway'),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.perm_identity, size: 16),
              const SizedBox(width: 4),
              Text(
                deviceId,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.show_chart_rounded),
          tooltip: 'Historique des Pas',
          onPressed: onOpenStepsHistory,
        ),
        IconButton(
          icon: const Icon(Icons.history_rounded),
          tooltip: 'Historique des Événements',
          onPressed: onOpenDetectionEventsHistory,
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Paramètres',
          onPressed: onOpenSettings,
        ),
        if (onLogout != null)
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Se déconnecter',
            onPressed: () => _showLogoutDialog(context),
          ),
      ],
    );
  }
}
