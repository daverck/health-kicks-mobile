import 'package:flutter/material.dart';
import '../../../services/ble/ble_footwear_client.dart';
import '../../../services/fall_sensitivity_settings_service.dart';

/// Card managing on-device fall detection physical impact sensitivity.
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
        final currentG = fallSensitivityService.thresholdG;
        final currentMs2 = fallSensitivityService.thresholdMs2;
        final label = fallSensitivityService.sensitivityLabel;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: Icon(
                Icons.personal_injury_outlined,
                color: theme.colorScheme.primary,
              ),
              title: const Text(
                'Sensibilité détection de chute',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Seuil d\'impact physique minimal requis par l\'IA de la chaussure',
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (currentG == 1.65)
                                ? Colors.green.withValues(alpha: 0.15)
                                : theme.colorScheme.secondaryContainer.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: (currentG == 1.65)
                                  ? Colors.green.shade600
                                  : theme.colorScheme.outlineVariant,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            label,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: (currentG == 1.65)
                                  ? Colors.green.shade800
                                  : theme.colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${currentG.toStringAsFixed(2)} g (${currentMs2.toStringAsFixed(1)} m/s²)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Slider(
                    value: currentG,
                    min: FallSensitivitySettingsService.minThresholdG,
                    max: FallSensitivitySettingsService.maxThresholdG,
                    divisions: FallSensitivitySettingsService.divisions,
                    label: '${currentG.toStringAsFixed(2)} g',
                    onChanged: (double val) {
                      fallSensitivityService.updateThreshold(
                        val,
                        bleClient: bleClient,
                      );
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '1.40 g (Très sensible)',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                      ),
                      Text(
                        '1.90 g (Robuste)',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        isBleReady ? Icons.check_circle_outline : Icons.cloud_queue_outlined,
                        size: 14,
                        color: isBleReady ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          isBleReady
                              ? 'Synchronisé en direct avec la chaussure via BLE.'
                              : 'Enregistré localement. Sera transmis à la connexion de la chaussure.',
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
