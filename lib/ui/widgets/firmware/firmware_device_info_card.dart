import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Card displaying installed footwear firmware version, build date, and BLE hardware connectivity.
class FirmwareDeviceInfoCard extends StatelessWidget {
  final BluetoothDevice? device;
  final String installedVersion;
  final DateTime? installedDate;

  const FirmwareDeviceInfoCard({
    super.key,
    required this.device,
    required this.installedVersion,
    this.installedDate,
  });

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return 'Inconnue (non provisionné)';
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year;
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDevice = device != null;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: hasDevice ? Colors.green.shade100 : Colors.red.shade100,
              child: Icon(
                hasDevice ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                color: hasDevice ? Colors.green.shade800 : Colors.red.shade800,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasDevice
                        ? device!.platformName.isNotEmpty
                            ? device!.platformName
                            : 'Chaussure Connectée (ESP32-S3)'
                        : 'Non connectée',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Version installée : $installedVersion',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.calendar_today_outlined, size: 13, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Date firmware actif : ${_formatDateTime(installedDate)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

