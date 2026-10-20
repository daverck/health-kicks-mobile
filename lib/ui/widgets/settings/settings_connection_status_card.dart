import 'package:flutter/material.dart';
import '../../../services/ble/ble_connection_manager.dart';

/// Card widget visualizing BLE footwear connection and Cloud MQTT broker status.
class SettingsConnectionStatusCard extends StatelessWidget {
  final BleConnectionStatus bleStatus;
  final bool isBleReady;
  final bool isBleScanning;
  final bool isBleConnecting;
  final String deviceName;
  final int mtu;
  final VoidCallback? onStartBleScan;
  final VoidCallback? onDisconnectBle;
  final VoidCallback? onOpenCalibration;
  final bool isMqttConnected;
  final VoidCallback? onReconnectMqtt;

  const SettingsConnectionStatusCard({
    super.key,
    required this.bleStatus,
    required this.isBleReady,
    required this.isBleScanning,
    required this.isBleConnecting,
    required this.deviceName,
    required this.mtu,
    this.onStartBleScan,
    this.onDisconnectBle,
    this.onOpenCalibration,
    required this.isMqttConnected,
    this.onReconnectMqtt,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Color bleColor = isBleReady
        ? Colors.green
        : (isBleScanning || isBleConnecting ? Colors.orange : Colors.grey);

    final String bleStatusText = isBleReady
        ? 'Connecté (MTU: $mtu)'
        : (isBleScanning
            ? 'Scan en cours...'
            : (isBleConnecting ? 'Connexion en cours...' : 'Déconnecté'));

    final Color mqttColor = isMqttConnected ? Colors.green : Colors.grey;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            'PASSERELLE & CONNECTIVITÉ',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
        ),

        // Bluetooth BLE Card
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: theme.dividerColor.withValues(alpha: 0.15),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.bluetooth, color: bleColor, size: 22),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Bluetooth',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: bleColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: bleColor),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            bleStatusText,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: bleColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Périphérique cible : $deviceName',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Re-scanner'),
                        onPressed: onStartBleScan,
                      ),
                    ),
                    if (onDisconnectBle != null) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.tonalIcon(
                          icon: const Icon(Icons.bluetooth_disabled, size: 16),
                          label: const Text('Déconnecter'),
                          onPressed: onDisconnectBle,
                        ),
                      ),
                    ],
                  ],
                ),
                if (isBleReady && onOpenCalibration != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.straighten, size: 16),
                      label: const Text("Étalonner l'assiette du capteur"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.primary,
                      ),
                      onPressed: onOpenCalibration,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Cloud MQTT Card
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: theme.dividerColor.withValues(alpha: 0.15),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.cloud, color: mqttColor, size: 22),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Cloud',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: mqttColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: mqttColor),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isMqttConnected ? 'Connecté' : 'Déconnecté',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: mqttColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Passerelle WebSockets MQTT SigV4 (Port 443)',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.sync, size: 16),
                    label: const Text('Re-connecter Cloud MQTT'),
                    onPressed: onReconnectMqtt,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
