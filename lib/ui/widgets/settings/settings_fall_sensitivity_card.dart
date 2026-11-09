import 'package:flutter/material.dart';

import '../../../services/ble/ble_footwear_client.dart';
import '../../../services/fall_sensitivity_settings_service.dart';
import 'fall_cooldown_slider.dart';
import 'fall_sensitivity_slider.dart';

/// Card for configuring fall detection sensitivity (confidence threshold) and fall alert cooldown.
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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      elevation: 0,
      color: Colors.transparent,
      shape: const RoundedRectangleBorder(side: BorderSide.none),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
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

            // Sensitivity slider section
            FallSensitivitySlider(
              fallSensitivityService: fallSensitivityService,
              bleClient: bleClient,
            ),

            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14.0),
              child: Divider(height: 1),
            ),

            // Cooldown slider section
            FallCooldownSlider(
              fallSensitivityService: fallSensitivityService,
              bleClient: bleClient,
            ),

            const SizedBox(height: 12),

            // BLE synchronization status
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
  }
}
