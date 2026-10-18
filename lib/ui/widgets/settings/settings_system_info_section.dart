import 'package:flutter/material.dart';

/// Section displaying application and footwear firmware system information tiles.
class SettingsSystemInfoSection extends StatelessWidget {
  final bool isBleReady;
  final String firmwareSubtitle;
  final VoidCallback onOpenFirmwareUpdateScreen;

  const SettingsSystemInfoSection({
    super.key,
    required this.isBleReady,
    required this.firmwareSubtitle,
    required this.onOpenFirmwareUpdateScreen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            'INFORMATIONS SYSTÈME',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
        ),
        const ListTile(
          leading: Icon(Icons.phone_android_outlined),
          title: Text('Application mobile'),
          subtitle: Text('HealthKicks Mobile v0.1.0+1 (Gateway BLE-MQTT)'),
        ),
        ListTile(
          leading: Icon(Icons.memory_outlined, color: isBleReady ? Colors.teal : null),
          title: const Text('Firmware chaussure connectée (ESP32-S3)'),
          subtitle: Text(firmwareSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onOpenFirmwareUpdateScreen,
        ),
      ],
    );
  }
}

