import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/background_surveillance_service.dart';
import '../../services/inactivity_settings_service.dart';
import '../../services/ble/ble_connection_manager.dart';
import '../../services/ble/ble_footwear_client.dart';

/// Screen allowing the user to configure mobile gateway settings,
/// BLE/MQTT connectivity actions, background surveillance, inactivity reminders, and tilt calibration.
class SettingsScreen extends StatefulWidget {
  final BackgroundSurveillanceService surveillanceService;
  final InactivitySettingsService? inactivitySettingsService;
  final BleFootwearClient? bleClient;
  final Future<void> Function()? onCalibrateSensor;
  final bool isFootwearConnected;
  final Stream<String>? studioStatusStream;

  // Connectivity action controls & status
  final Future<void> Function()? onStartBleScan;
  final Future<void> Function()? onDisconnectBle;
  final Future<void> Function()? onReconnectMqtt;
  final BleConnectionStatus bleStatus;
  final bool isMqttConnected;
  final String? deviceName;
  final String? targetDeviceId;
  final int mtu;

  const SettingsScreen({
    super.key,
    required this.surveillanceService,
    this.inactivitySettingsService,
    this.bleClient,
    this.onCalibrateSensor,
    this.isFootwearConnected = false,
    this.studioStatusStream,
    this.onStartBleScan,
    this.onDisconnectBle,
    this.onReconnectMqtt,
    this.bleStatus = BleConnectionStatus.disconnected,
    this.isMqttConnected = false,
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
  }

  @override
  void dispose() {
    if (_ownsInactivityService) {
      _inactivityService.dispose();
    }
    super.dispose();
  }

  void _showCalibrationDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ImuCalibrationDialog(
        onCalibrate: widget.onCalibrateSensor,
        isConnected: widget.isFootwearConnected,
        studioStatusStream: widget.studioStatusStream,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBleReady = widget.isFootwearConnected ||
        widget.bleStatus == BleConnectionStatus.ready ||
        widget.bleStatus == BleConnectionStatus.connected;
    final isBleScanning = widget.bleStatus == BleConnectionStatus.scanning;
    final isBleConnecting = widget.bleStatus == BleConnectionStatus.connecting;

    final Color bleColor = isBleReady
        ? Colors.green
        : (isBleScanning || isBleConnecting ? Colors.orange : Colors.grey);

    final String bleStatusText = isBleReady
        ? 'Connecté (MTU: ${widget.mtu})'
        : (isBleScanning
            ? 'Scan en cours...'
            : (isBleConnecting ? 'Connexion en cours...' : 'Déconnecté'));

    final Color mqttColor = widget.isMqttConnected ? Colors.green : Colors.grey;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([widget.surveillanceService, _inactivityService]),
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
                                    'Bluetooth Low Energy (BLE)',
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
                        'Périphérique cible : ${widget.deviceName ?? widget.targetDeviceId ?? "HealthKicks-HK-2"}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Re-scanner'),
                              onPressed: widget.onStartBleScan,
                            ),
                          ),
                          if (isBleReady && widget.onDisconnectBle != null) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.tonalIcon(
                                icon: const Icon(Icons.bluetooth_disabled, size: 16),
                                label: const Text('Déconnecter'),
                                onPressed: widget.onDisconnectBle,
                              ),
                            ),
                          ],
                        ],
                      ),
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
                                    'AWS IoT Core Cloud',
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
                                  widget.isMqttConnected ? 'Connecté' : 'Déconnecté',
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
                        widget.isFootwearConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                        size: 14,
                        color: widget.isFootwearConnected ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.isFootwearConnected
                              ? 'Synchronisé en direct avec la chaussure'
                              : 'Sera synchronisé dès la prochaine connexion BLE',
                          style: TextStyle(
                            fontSize: 11,
                            color: widget.isFootwearConnected ? Colors.green.shade700 : Colors.grey.shade600,
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
                onTap: () => _showCalibrationDialog(context),
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
