import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../services/ble/ble_connection_manager.dart';
import '../../services/ble/ble_footwear_client.dart';

/// Discreet top status row displaying device identifier and connection status chips.
class GatewayStatusRow extends StatelessWidget {
  final String deviceId;
  final BleConnectionStatus bleStatus;
  final BleFootwearClient? bleClient;
  final BluetoothDevice? connectedDevice;
  final String targetDeviceId;
  final int mtu;
  final bool isMqttConnected;
  final String awsRegion;
  final VoidCallback onTapSettings;

  const GatewayStatusRow({
    super.key,
    required this.deviceId,
    required this.bleStatus,
    this.bleClient,
    this.connectedDevice,
    required this.targetDeviceId,
    required this.mtu,
    required this.isMqttConnected,
    required this.awsRegion,
    required this.onTapSettings,
  });

  @override
  Widget build(BuildContext context) {
    final isBleReady = (bleStatus == BleConnectionStatus.ready || bleStatus == BleConnectionStatus.connected) &&
        (bleClient != null || connectedDevice != null);
    final isBleScanning = bleStatus == BleConnectionStatus.scanning;
    final isBleConnecting = bleStatus == BleConnectionStatus.connecting;

    final Color bleColor = isBleReady
        ? Colors.green
        : (isBleScanning || isBleConnecting ? Colors.orange : Colors.grey);
    final IconData bleIcon = isBleReady
        ? Icons.bluetooth_connected
        : (isBleScanning || isBleConnecting ? Icons.bluetooth_searching : Icons.bluetooth_disabled);
    final String bleTooltip = isBleReady
        ? 'Bluetooth connecté (${connectedDevice?.platformName.isNotEmpty == true ? connectedDevice!.platformName : targetDeviceId}, MTU: $mtu)'
        : (isBleScanning ? 'Bluetooth : Recherche en cours...' : (isBleConnecting ? 'Bluetooth : Connexion...' : 'Bluetooth déconnecté'));

    final Color mqttColor = isMqttConnected ? Colors.green : Colors.grey;
    final IconData mqttIcon = isMqttConnected ? Icons.cloud_done : Icons.cloud_off;
    final String mqttTooltip = isMqttConnected
        ? 'AWS IoT Core : Connecté (Port 443 WSS, $awsRegion)'
        : 'AWS IoT Core : Déconnecté';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.directions_walk_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'Chaussure $deviceId',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Tooltip(
                message: bleTooltip,
                child: Material(
                  color: bleColor.withValues(alpha: 0.12),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onTapSettings,
                    child: Padding(
                      padding: const EdgeInsets.all(7.0),
                      child: Icon(bleIcon, color: bleColor, size: 18),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: mqttTooltip,
                child: Material(
                  color: mqttColor.withValues(alpha: 0.12),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onTapSettings,
                    child: Padding(
                      padding: const EdgeInsets.all(7.0),
                      child: Icon(mqttIcon, color: mqttColor, size: 18),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

