import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/background_surveillance_service.dart';
import '../../services/inactivity_settings_service.dart';
import '../../services/ble/ble_connection_manager.dart';
import '../../services/ble/ble_footwear_client.dart';
import '../../services/theme_service.dart';
import 'firmware_update_screen.dart';

/// Screen allowing the user to configure mobile gateway settings,
/// BLE/MQTT connectivity actions, background surveillance, inactivity reminders, appearance/theme, and tilt calibration.
class SettingsScreen extends StatefulWidget {
  final BackgroundSurveillanceService surveillanceService;
  final InactivitySettingsService? inactivitySettingsService;
  final ThemeService? themeService;
  final BleFootwearClient? bleClient;
  final ValueNotifier<BleFootwearClient?>? bleClientNotifier;
  final Future<void> Function()? onCalibrateSensor;
  final bool isFootwearConnected;
  final Stream<String>? studioStatusStream;

  // Connectivity action controls & status
  final BleConnectionManager? bleManager;
  final Future<void> Function()? onStartBleScan;
  final Future<void> Function()? onDisconnectBle;
  final Future<void> Function()? onReconnectMqtt;
  final BleConnectionStatus bleStatus;
  final bool isMqttConnected;
  final ValueNotifier<bool>? isMqttConnectedNotifier;
  final String? deviceName;
  final String? targetDeviceId;
  final int mtu;

  const SettingsScreen({
    super.key,
    required this.surveillanceService,
    this.inactivitySettingsService,
    this.themeService,
    this.bleManager,
    this.bleClient,
    this.bleClientNotifier,
    this.onCalibrateSensor,
    this.isFootwearConnected = false,
    this.studioStatusStream,
    this.onStartBleScan,
    this.onDisconnectBle,
    this.onReconnectMqtt,
    this.bleStatus = BleConnectionStatus.disconnected,
    this.isMqttConnected = false,
    this.isMqttConnectedNotifier,
    this.deviceName,
    this.targetDeviceId,
    this.mtu = 23,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final InactivitySettingsService _inactivityService;
  bool _ownsInactivityService = false;
  late final ThemeService _themeService;
  bool _ownsThemeService = false;

  bool _isLocallyDisconnected = false;
  BleConnectionStatus? _previousBleStatus;

  @override
  void initState() {
    super.initState();
    if (widget.inactivitySettingsService != null) {
      _inactivityService = widget.inactivitySettingsService!;
    } else {
      _inactivityService = InactivitySettingsService();
      _ownsInactivityService = true;
      unawaited(_inactivityService.loadSettings());
    }

    if (widget.themeService != null) {
      _themeService = widget.themeService!;
    } else {
      _themeService = ThemeService();
      _ownsThemeService = true;
      unawaited(_themeService.loadTheme());
    }
  }

  @override
  void dispose() {
    if (_ownsInactivityService) {
      _inactivityService.dispose();
    }
    if (_ownsThemeService) {
      _themeService.dispose();
    }
    super.dispose();
  }

  void _showCalibrationDialog(BuildContext context, bool isConnected) {
    final activeBleClient = widget.bleClientNotifier?.value ?? widget.bleClient;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ImuCalibrationDialog(
        onCalibrate: activeBleClient != null
            ? activeBleClient.sendCalibrateZeroCommand
            : widget.onCalibrateSensor,
        isConnected: isConnected,
        studioStatusStream: activeBleClient?.studioStatusStream ?? widget.studioStatusStream,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          widget.surveillanceService,
          _inactivityService,
          if (widget.bleManager != null) widget.bleManager!,
          if (widget.bleClientNotifier != null) widget.bleClientNotifier!,
          if (widget.isMqttConnectedNotifier != null) widget.isMqttConnectedNotifier!,
        ]),
        builder: (context, _) {
          final currentBleStatus = widget.bleManager?.status ?? widget.bleStatus;
          if ((currentBleStatus == BleConnectionStatus.ready ||
                  currentBleStatus == BleConnectionStatus.connected) &&
              (_previousBleStatus != null &&
                  _previousBleStatus != BleConnectionStatus.ready &&
                  _previousBleStatus != BleConnectionStatus.connected)) {
            _isLocallyDisconnected = false;
          }
          _previousBleStatus = currentBleStatus;
          final isBleReady = !_isLocallyDisconnected &&
              (widget.bleManager != null
                  ? (currentBleStatus == BleConnectionStatus.ready ||
                      currentBleStatus == BleConnectionStatus.connected)
                  : (widget.isFootwearConnected ||
                      currentBleStatus == BleConnectionStatus.ready ||
                      currentBleStatus == BleConnectionStatus.connected));
          final isBleScanning = !_isLocallyDisconnected && currentBleStatus == BleConnectionStatus.scanning;
          final isBleConnecting = !_isLocallyDisconnected && currentBleStatus == BleConnectionStatus.connecting;
          final activeBleClient = widget.bleClientNotifier?.value ?? widget.bleClient;

          final Color bleColor = isBleReady
              ? Colors.green
              : (isBleScanning || isBleConnecting ? Colors.orange : Colors.grey);

          final currentMtu = widget.bleManager?.negotiatedMtu ?? widget.mtu;
          final String currentDeviceName = widget.bleManager?.connectedDevice?.platformName.isNotEmpty == true
              ? widget.bleManager!.connectedDevice!.platformName
              : (widget.deviceName ?? widget.targetDeviceId ?? 'HealthKicks-HK-2');

          final String bleStatusText = isBleReady
              ? 'Connecté (MTU: $currentMtu)'
              : (isBleScanning
                  ? 'Scan en cours...'
                  : (isBleConnecting ? 'Connexion en cours...' : 'Déconnecté'));

          final isMqttConnected = widget.isMqttConnectedNotifier?.value ?? widget.isMqttConnected;
          final Color mqttColor = isMqttConnected ? Colors.green : Colors.grey;

          final VoidCallback? onDisconnect = isBleReady
              ? () {
                  setState(() {
                    _isLocallyDisconnected = true;
                  });
                  if (widget.onDisconnectBle != null) {
                    widget.onDisconnectBle!();
                  } else if (widget.bleManager != null) {
                    widget.bleManager!.disconnect();
                  }
                }
              : null;

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

              // 1.1 Bluetooth BLE Control Card
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
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
                        'Périphérique cible : $currentDeviceName',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Re-scanner'),
                              onPressed: () {
                                setState(() {
                                  _isLocallyDisconnected = false;
                                });
                                widget.onStartBleScan?.call();
                              },
                            ),
                          ),
                          if (onDisconnect != null) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.tonalIcon(
                                icon: const Icon(Icons.bluetooth_disabled, size: 16),
                                label: const Text('Déconnecter'),
                                onPressed: onDisconnect,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (isBleReady && (activeBleClient != null || widget.onCalibrateSensor != null)) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.straighten, size: 16),
                            label: const Text("Étalonner l'assiette du capteur (4s)"),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(context).colorScheme.primary,
                            ),
                            onPressed: () async {
                              try {
                                if (activeBleClient != null) {
                                  await activeBleClient.sendCalibrateZeroCommand();
                                } else if (widget.onCalibrateSensor != null) {
                                  await widget.onCalibrateSensor!();
                                }
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        "Étalonnage initié. Gardez la chaussure immobile à plat pendant 4 secondes pour ajuster la baseline à 0.",
                                      ),
                                      duration: Duration(seconds: 4),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text("Échec de l'étalonnage: $e")),
                                  );
                                }
                              }
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // 1.2 AWS IoT Core Control Card
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
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
                          onPressed: widget.onReconnectMqtt,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // 1.3 Mode Surveillance Active SwitchListTile
              SwitchListTile(
                secondary: Icon(
                  Icons.shield_outlined,
                  color: widget.surveillanceService.isSurveillanceActive
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
                value: widget.surveillanceService.isSurveillanceActive,
                onChanged: widget.surveillanceService.isSupported
                    ? (bool value) async {
                        await widget.surveillanceService.toggleSurveillance(value);
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

              // Platform warning or battery note
              if (!widget.surveillanceService.isSupported)
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

              // 2. Prolonged Inactivity Reminder Category
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Text(
                  'RAPPEL D\'INACTIVITÉ PROLONGÉE',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                ),
              ),

              SwitchListTile(
                secondary: Icon(
                  Icons.airline_seat_recline_normal_outlined,
                  color: _inactivityService.isEnabled
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                ),
                title: const Text(
                  'Alerte de sédentarité',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Vibration discrète de la chaussure après une longue période d\'immobilité',
                ),
                value: _inactivityService.isEnabled,
                onChanged: (bool value) async {
                  await _inactivityService.updateSettings(
                    enabled: value,
                    repeatEnabled: _inactivityService.isRepeatEnabled,
                    thresholdMinutes: _inactivityService.thresholdMinutes,
                    cooldownMinutes: _inactivityService.cooldownMinutes,
                    bleClient: widget.bleClient,
                  );
                },
              ),

              if (_inactivityService.isEnabled) ...[
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
                              color: Theme.of(context).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${_inactivityService.thresholdMinutes} min',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _inactivityService.thresholdMinutes.toDouble(),
                        min: 10,
                        max: 120,
                        divisions: 22,
                        label: '${_inactivityService.thresholdMinutes} min',
                        onChanged: (double val) {
                          _inactivityService.updateSettings(
                            enabled: _inactivityService.isEnabled,
                            repeatEnabled: _inactivityService.isRepeatEnabled,
                            thresholdMinutes: val.round(),
                            cooldownMinutes: _inactivityService.cooldownMinutes,
                            bleClient: widget.bleClient,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                SwitchListTile(
                  secondary: Icon(
                    Icons.replay_outlined,
                    color: _inactivityService.isRepeatEnabled
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                  ),
                  title: const Text(
                    'Répéter les alertes',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Fait re-vibrer la chaussure à intervalle régulier si vous restez assis',
                  ),
                  value: _inactivityService.isRepeatEnabled,
                  onChanged: (bool value) async {
                    await _inactivityService.updateSettings(
                      enabled: _inactivityService.isEnabled,
                      repeatEnabled: value,
                      thresholdMinutes: _inactivityService.thresholdMinutes,
                      cooldownMinutes: _inactivityService.cooldownMinutes,
                      bleClient: widget.bleClient,
                    );
                  },
                ),
                if (_inactivityService.isRepeatEnabled)
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
                                color: Theme.of(context).colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${_inactivityService.cooldownMinutes} min',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _inactivityService.cooldownMinutes.toDouble(),
                          min: 5,
                          max: 30,
                          divisions: 5,
                          label: '${_inactivityService.cooldownMinutes} min',
                          onChanged: (double val) {
                            _inactivityService.updateSettings(
                              enabled: _inactivityService.isEnabled,
                              repeatEnabled: _inactivityService.isRepeatEnabled,
                              thresholdMinutes: _inactivityService.thresholdMinutes,
                              cooldownMinutes: val.round(),
                              bleClient: widget.bleClient,
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

              const Divider(height: 32),

              // 3. Sensor Calibration Category
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Text(
                  'CALIBRATION DU CAPTEUR (ASSIETTE)',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.screen_rotation_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text(
                  'Calibration de l\'assiette (Zéro gravité)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Recalibre l\'horizontalité et la compensation d\'inclinaison mécanique',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showCalibrationDialog(context, isBleReady),
              ),

              const Divider(height: 32),

              // 4. Firmware OTA Update Category
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Text(
                  'MISE À JOUR MATÉRIELLE (FIRMWARE OTA)',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.system_update_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text(
                  'Mise à jour du firmware (BLE)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Transférer un nouveau binaire .bin vers la chaussure connectée',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (ctx) => FirmwareUpdateScreen(
                        device: widget.bleClient?.device ?? widget.bleManager?.connectedDevice,
                      ),
                    ),
                  );
                },
              ),

              const Divider(height: 32),

              // 5. App Theme Category
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Text(
                  'APPARENCE & THÈME',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Thème de l\'application',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Choisissez le mode d\'affichage clair, sombre ou automatique.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 14),
                        ListenableBuilder(
                          listenable: _themeService,
                          builder: (context, _) {
                            return SizedBox(
                              width: double.infinity,
                              child: SegmentedButton<AppThemeMode>(
                                segments: const [
                                  ButtonSegment<AppThemeMode>(
                                    value: AppThemeMode.system,
                                    label: Text('Système'),
                                    icon: Icon(Icons.brightness_auto, size: 18),
                                  ),
                                  ButtonSegment<AppThemeMode>(
                                    value: AppThemeMode.light,
                                    label: Text('Clair'),
                                    icon: Icon(Icons.light_mode, size: 18),
                                  ),
                                  ButtonSegment<AppThemeMode>(
                                    value: AppThemeMode.dark,
                                    label: Text('Sombre'),
                                    icon: Icon(Icons.dark_mode, size: 18),
                                  ),
                                ],
                                selected: {_themeService.currentMode},
                                onSelectionChanged: (Set<AppThemeMode> selected) {
                                  if (selected.isNotEmpty) {
                                    _themeService.setThemeMode(selected.first);
                                  }
                                },
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const Divider(height: 32),

              // 6. App Info section
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

enum _CalibrationStep { idle, calibrating, success, error }

/// Interactive modal dialog executing the 4.0s tilt calibration protocol.
class _ImuCalibrationDialog extends StatefulWidget {
  final Future<void> Function()? onCalibrate;
  final bool isConnected;
  final Stream<String>? studioStatusStream;

  const _ImuCalibrationDialog({
    required this.onCalibrate,
    required this.isConnected,
    this.studioStatusStream,
  });

  @override
  State<_ImuCalibrationDialog> createState() => _ImuCalibrationDialogState();
}

class _ImuCalibrationDialogState extends State<_ImuCalibrationDialog> {
  _CalibrationStep _step = _CalibrationStep.idle;
  double _remainingSeconds = 4.0;
  Timer? _countdownTimer;
  StreamSubscription<String>? _statusSubscription;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    if (widget.studioStatusStream != null) {
      _statusSubscription = widget.studioStatusStream!.listen((status) {
        if (!mounted) return;
        if (status.contains('CALIBRATION_OK')) {
          _onCalibrationSuccess();
        } else if (status.contains('CALIBRATION_ERROR')) {
          _onCalibrationError('Erreur de calibration reçue de la chaussure.');
        }
      });
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _statusSubscription?.cancel();
    super.dispose();
  }

  void _onCalibrationSuccess() {
    _countdownTimer?.cancel();
    if (mounted) {
      setState(() {
        _step = _CalibrationStep.success;
      });
    }
  }

  void _onCalibrationError(String msg) {
    _countdownTimer?.cancel();
    if (mounted) {
      setState(() {
        _step = _CalibrationStep.error;
        _errorMessage = msg;
      });
    }
  }

  Future<void> _startCalibration() async {
    setState(() {
      _step = _CalibrationStep.calibrating;
      _remainingSeconds = 4.0;
      _errorMessage = '';
    });

    try {
      if (widget.onCalibrate != null) {
        await widget.onCalibrate!();
      }
    } catch (e) {
      _onCalibrationError('Échec de l\'envoi de la commande : $e');
      return;
    }

    const intervalMs = 100;
    _countdownTimer = Timer.periodic(const Duration(milliseconds: intervalMs), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _remainingSeconds -= intervalMs / 1000.0;
        if (_remainingSeconds <= 0.0) {
          _remainingSeconds = 0.0;
          timer.cancel();
          if (_step == _CalibrationStep.calibrating) {
            _step = _CalibrationStep.success;
          }
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.screen_rotation_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('Calibration de l\'Assiette', style: TextStyle(fontSize: 18))),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.isConnected) ...[
              Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(color: Colors.amber.shade700),
                ),
                child: Row(
                  children: [
                    Icon(Icons.bluetooth_disabled, color: Colors.amber.shade800),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Chaussure non connectée en BLE. Veuillez établir la connexion avant de lancer la calibration.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            if (_step == _CalibrationStep.idle) ...[
              const Text(
                '1. Posez la chaussure sur une surface plane et horizontale (semelle bien à plat).\n\n'
                '2. Cliquez sur "Démarrer". La chaussure doit rester parfaitement immobile pendant 4 secondes.\n\n'
                '3. Une double vibration confirmera la réussite et la persistance en mémoire.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
            ] else if (_step == _CalibrationStep.calibrating) ...[
              const Text(
                'Mesure de l\'assiette en cours...\nNe bougez pas la chaussure.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: (4.0 - _remainingSeconds) / 4.0,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                color: theme.colorScheme.primary,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 12),
              Text(
                '${_remainingSeconds.toStringAsFixed(1)} s restantes',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ] else if (_step == _CalibrationStep.success) ...[
              Container(
                padding: const EdgeInsets.all(14.0),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(color: Colors.green.shade600),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 28),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Calibration réussie !\nL\'alignement de gravité est désormais sauvegardé.',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (_step == _CalibrationStep.error) ...[
              Container(
                padding: const EdgeInsets.all(14.0),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(color: Colors.red.shade600),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage.isNotEmpty ? _errorMessage : 'Échec de la calibration.',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_step == _CalibrationStep.idle) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('Démarrer'),
            onPressed: widget.isConnected ? _startCalibration : null,
          ),
        ] else if (_step == _CalibrationStep.calibrating) ...[
          TextButton(
            onPressed: () {
              _countdownTimer?.cancel();
              Navigator.of(context).pop();
            },
            child: const Text('Annuler'),
          ),
        ] else if (_step == _CalibrationStep.success) ...[
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Terminer'),
          ),
        ] else if (_step == _CalibrationStep.error) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
          FilledButton(
            onPressed: widget.isConnected ? _startCalibration : null,
            child: const Text('Réessayer'),
          ),
        ],
      ],
    );
  }
}
