import 'package:flutter/material.dart';

import '../../../services/ble/ble_footwear_client.dart';
import '../../../services/fall_sensitivity_settings_service.dart';

/// Card for configuring fall detection sensitivity (confidence threshold).
class SettingsFallSensitivityCard extends StatelessWidget {
  final FallSensitivitySettingsService fallSensitivityService;
  final BleFootwearClient? bleClient;
  final bool isBleReady;

  const SettingsFallSensitivityCard({
    super.key,
    required this.fallSensitivityService,
    this.bleClient,
    required this.isBleReady,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: fallSensitivityService,
      builder: (context, _) {
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with icon and title
            Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 24,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sensibilité de détection des chutes',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Ajustez le seuil de confiance pour déclencher les alertes',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Sensitivity label with badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Niveau actuel:',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        fallSensitivityService.sensitivityLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onPrimaryContainer
                              .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${fallSensitivityService.thresholdPercentage}%',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Description text
            Text(
              fallSensitivityService.sensitivityDescription,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            // Slider with labels
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Slider
                Slider(
                  value: fallSensitivityService.threshold,
                  min: FallSensitivitySettingsService.minThreshold,
                  max: FallSensitivitySettingsService.maxThreshold,
                  divisions: FallSensitivitySettingsService.sliderDivisions,
                  label: '${fallSensitivityService.thresholdPercentage}%',
                  onChanged: (double value) async {
                    await fallSensitivityService.setThreshold(
                      value,
                      bleClient: bleClient,
                    );
                  },
                ),
                const SizedBox(height: 4),

                // Range labels
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${(FallSensitivitySettingsService.minThreshold * 100).round()}%',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      'Ultra sensible',
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    Text(
                      '${(FallSensitivitySettingsService.defaultThreshold * 100).round()}%',
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Recommandée',
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    Text(
                      '${(FallSensitivitySettingsService.maxThreshold * 100).round()}%',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      'Robuste',
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Sync status
            Row(
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
          ],
        ),
      ),
    );
      },
    );
  }
}
