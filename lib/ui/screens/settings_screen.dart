import 'package:flutter/material.dart';
import '../../services/background_surveillance_service.dart';

/// Screen allowing the user to configure mobile gateway settings,
/// including the persistent Android Foreground Service (Mode Surveillance Active).
class SettingsScreen extends StatelessWidget {
  final BackgroundSurveillanceService surveillanceService;

  const SettingsScreen({
    super.key,
    required this.surveillanceService,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
      ),
      body: ListenableBuilder(
        listenable: surveillanceService,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            children: [
              // 1. Connectivity & Background Service Category
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Text(
                  'PASSERELLE & CONNECTIVITÉ',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                ),
              ),

              // 2. Mode Surveillance Active SwitchListTile
              SwitchListTile(
                secondary: Icon(
                  Icons.shield_outlined,
                  color: surveillanceService.isSurveillanceActive
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                ),
                title: const Text(
                  'Mode Surveillance Active',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Maintient la connexion active écran éteint pour l\'enregistrement et la télémétrie',
                ),
                value: surveillanceService.isSurveillanceActive,
                onChanged: surveillanceService.isSupported
                    ? (bool value) async {
                        await surveillanceService.toggleSurveillance(value);
                        if (context.mounted && !value) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Mode Surveillance Active désactivé.'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      }
                    : null,
              ),

              // 3. Platform warning or battery note
              if (!surveillanceService.isSupported)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Container(
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(color: Colors.amber.shade700),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: Colors.amber.shade800, size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Le maintien de la passerelle BLE/MQTT avec écran éteint est actuellement réservé à Android. iOS n\'est pas supporté pour ce mode en raison des restrictions d\'arrière-plan de l\'OS.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Container(
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Gestion intelligente de la batterie',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Une notification permanente reste visible tant que la surveillance est active.\n'
                          'Si la chaussure est éteinte ou hors de portée pendant plus de 5 minutes, le service s\'arrête automatiquement pour économiser votre batterie.',
                          style: TextStyle(fontSize: 12, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                ),

              const Divider(height: 32),

              // 4. App Info section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Text(
                  'INFORMATIONS SYSTÈME',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                ),
              ),
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Version'),
                subtitle: Text('HealthKicks Mobile v0.1.0+1 (Gateway BLE-MQTT)'),
              ),
              const ListTile(
                leading: Icon(Icons.notifications_active_outlined),
                title: Text('Canal de Notification'),
                subtitle: Text(BackgroundSurveillanceService.notificationChannelName),
              ),
            ],
          );
        },
      ),
    );
  }
}

