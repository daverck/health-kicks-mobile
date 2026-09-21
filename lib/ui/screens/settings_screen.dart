import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/background_surveillance_service.dart';

/// Screen allowing the user to configure mobile gateway settings,
/// background surveillance service, and IMU zero/tilt sensor calibration.
class SettingsScreen extends StatelessWidget {
  final BackgroundSurveillanceService surveillanceService;
  final Future<void> Function()? onCalibrateSensor;
  final bool isFootwearConnected;
  final Stream<String>? studioStatusStream;

  const SettingsScreen({
    super.key,
    required this.surveillanceService,
    this.onCalibrateSensor,
    this.isFootwearConnected = false,
    this.studioStatusStream,
  });

  void _showCalibrationDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ImuCalibrationDialog(
        onCalibrate: onCalibrateSensor,
        isConnected: isFootwearConnected,
        studioStatusStream: studioStatusStream,
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
        listenable: surveillanceService,
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

              // 2. Mode Surveillance Active SwitchListTile
              SwitchListTile(
                secondary: Icon(
                  Icons.shield_outlined,
                  color: surveillanceService.isSurveillanceActive
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
                value: surveillanceService.isSurveillanceActive,
                onChanged: surveillanceService.isSupported
                    ? (bool value) async {
                        await surveillanceService.toggleSurveillance(value);
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

              // 3. Platform warning or battery note
              if (!surveillanceService.isSupported)
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

              // 4. Sensor Calibration Category
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

              // 5. App Info section
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

    // Option A: Send BLE command immediately on tapping Start
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


