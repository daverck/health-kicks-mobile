import 'package:flutter/material.dart';

/// Top app bar for the HealthKicks gateway dashboard with quick navigation actions.
class DashboardAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onOpenStepsHistory;
  final VoidCallback onOpenDetectionEventsHistory;
  final VoidCallback onOpenSettings;
  final VoidCallback? onLogout;

  const DashboardAppBar({
    super.key,
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
    return AppBar(
      title: const Text('HealthKicks BLE-to-MQTT Gateway'),
      actions: [
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
