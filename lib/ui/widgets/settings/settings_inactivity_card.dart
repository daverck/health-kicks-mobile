import 'package:flutter/material.dart';
import '../../../services/ble/ble_footwear_client.dart';
import '../../../services/inactivity_settings_service.dart';

/// Card managing prolonged inactivity sedentary reminders and vibration intervals.
class SettingsInactivityCard extends StatelessWidget {
  final InactivitySettingsService inactivityService;
  final BleFootwearClient? bleClient;
  final bool isBleReady;

  const SettingsInactivityCard({
    super.key,
    required this.inactivityService,
    this.bleClient,
    required this.isBleReady,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          secondary: Icon(
            Icons.airline_seat_recline_normal_outlined,
            color: inactivityService.isEnabled
                ? theme.colorScheme.primary
                : Colors.grey,
          ),
          title: const Text(
            'Alerte de sédentarité',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            'Vibration discrète de la chaussure après une longue période d\'immobilité',
          ),
          value: inactivityService.isEnabled,
          onChanged: (bool value) async {
            await inactivityService.updateSettings(
              enabled: value,
              repeatEnabled: inactivityService.isRepeatEnabled,
              thresholdMinutes: inactivityService.thresholdMinutes,
              cooldownMinutes: inactivityService.cooldownMinutes,
              bleClient: bleClient,
            );
          },
        ),
        if (inactivityService.isEnabled) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'Délai avant première alerte',
                        style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${inactivityService.thresholdMinutes} min',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: inactivityService.thresholdMinutes.toDouble(),
                  min: 10,
                  max: 120,
                  divisions: 22,
                  label: '${inactivityService.thresholdMinutes} min',
                  onChanged: (double val) {
                    inactivityService.updateSettings(
                      enabled: inactivityService.isEnabled,
                      repeatEnabled: inactivityService.isRepeatEnabled,
                      thresholdMinutes: val.round(),
                      cooldownMinutes: inactivityService.cooldownMinutes,
                      bleClient: bleClient,
                    );
                  },
                ),
              ],
            ),
          ),
          SwitchListTile(
            secondary: Icon(
              Icons.replay_outlined,
              color: inactivityService.isRepeatEnabled
                  ? theme.colorScheme.primary
                  : Colors.grey,
            ),
            title: const Text(
              'Répéter les alertes',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Fait re-vibrer la chaussure à intervalle régulier si vous restez assis',
            ),
            value: inactivityService.isRepeatEnabled,
            onChanged: (bool value) async {
              await inactivityService.updateSettings(
                enabled: inactivityService.isEnabled,
                repeatEnabled: value,
                thresholdMinutes: inactivityService.thresholdMinutes,
                cooldownMinutes: inactivityService.cooldownMinutes,
                bleClient: bleClient,
              );
            },
          ),
          if (inactivityService.isRepeatEnabled)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'Délai de répétition (Cooldown / Snooze)',
                          style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${inactivityService.cooldownMinutes} min',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: inactivityService.cooldownMinutes.toDouble(),
                    min: 5,
                    max: 30,
                    divisions: 5,
                    label: '${inactivityService.cooldownMinutes} min',
                    onChanged: (double val) {
                      inactivityService.updateSettings(
                        enabled: inactivityService.isEnabled,
                        repeatEnabled: inactivityService.isRepeatEnabled,
                        thresholdMinutes: inactivityService.thresholdMinutes,
                        cooldownMinutes: val.round(),
                        bleClient: bleClient,
                      );
                    },
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Row(
              children: [
                Icon(
                  isBleReady ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  size: 14,
                  color: isBleReady ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isBleReady
                        ? 'Synchronisé en direct avec la chaussure'
                        : 'Sera synchronisé dès la prochaine connexion BLE',
                    style: TextStyle(
                      fontSize: 11,
                      color: isBleReady ? Colors.green.shade700 : Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
