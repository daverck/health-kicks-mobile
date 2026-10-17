import 'dart:async';
import 'package:flutter/material.dart';

enum CalibrationStep { idle, calibrating, success, error }

/// Interactive modal dialog executing the 4.0s tilt calibration protocol.
class ImuCalibrationDialog extends StatefulWidget {
  final Future<void> Function()? onCalibrate;
  final bool isConnected;
  final Stream<String>? studioStatusStream;

  const ImuCalibrationDialog({
    super.key,
    required this.onCalibrate,
    required this.isConnected,
    this.studioStatusStream,
  });

  @override
  State<ImuCalibrationDialog> createState() => _ImuCalibrationDialogState();
}

class _ImuCalibrationDialogState extends State<ImuCalibrationDialog> {
  CalibrationStep _step = CalibrationStep.idle;
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
        _step = CalibrationStep.success;
      });
    }
  }

  void _onCalibrationError(String msg) {
    _countdownTimer?.cancel();
    if (mounted) {
      setState(() {
        _step = CalibrationStep.error;
        _errorMessage = msg;
      });
    }
  }

  Future<void> _startCalibration() async {
    setState(() {
      _step = CalibrationStep.calibrating;
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
          if (_step == CalibrationStep.calibrating) {
            _step = CalibrationStep.success;
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

            if (_step == CalibrationStep.idle) ...[
              const Text(
                '1. Posez la chaussure sur une surface plane et horizontale (semelle bien à plat).\n\n'
                '2. Cliquez sur "Démarrer". La chaussure doit rester parfaitement immobile pendant 4 secondes.\n\n'
                '3. Une double vibration confirmera la réussite et la persistance en mémoire.',
                style: TextStyle(fontSize: 13, height: 1.4),
              ),
            ] else if (_step == CalibrationStep.calibrating) ...[
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
            ] else if (_step == CalibrationStep.success) ...[
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
            ] else if (_step == CalibrationStep.error) ...[
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
        if (_step == CalibrationStep.idle) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('Démarrer'),
            onPressed: widget.isConnected ? _startCalibration : null,
          ),
        ] else if (_step == CalibrationStep.calibrating) ...[
          TextButton(
            onPressed: () {
              _countdownTimer?.cancel();
              Navigator.of(context).pop();
            },
            child: const Text('Annuler'),
          ),
        ] else if (_step == CalibrationStep.success) ...[
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Terminer'),
          ),
        ] else if (_step == CalibrationStep.error) ...[
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
