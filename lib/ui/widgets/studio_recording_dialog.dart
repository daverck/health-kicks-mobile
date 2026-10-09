import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/studio_session_model.dart';
import 'studio_session_dialog.dart';

/// Current lifecycle state of an active Studio recording session.
enum StudioActiveState {
  countdown,
  recording,
  transmitting,
  success,
  cancelled,
  error,
}

/// Modal dialog overlay displaying live progress of a Studio recording session.
class StudioRecordingDialog extends StatefulWidget {
  final String label;
  final double durationSec;
  final Stream<String> studioStatusStream;
  final Stream<dynamic>? sessionSavedStream;
  final Future<void> Function()? onCancel;

  const StudioRecordingDialog({
    super.key,
    required this.label,
    this.durationSec = 5.0,
    required this.studioStatusStream,
    this.sessionSavedStream,
    this.onCancel,
  });

  @override
  State<StudioRecordingDialog> createState() => _StudioRecordingDialogState();
}

class _StudioRecordingDialogState extends State<StudioRecordingDialog> {
  StudioActiveState _state = StudioActiveState.countdown;
  int _countdownStep = 1;
  static const int _totalCountdownSteps = 3;

  double _elapsedRecordingSec = 0.0;
  late double _targetDurationSec;
  Timer? _recordingProgressTimer;
  Timer? _autoDismissTimer;

  int _samplesCollected = 0;
  String? _errorMessage;
  bool _isCancelling = false;

  StreamSubscription<String>? _statusSub;
  StreamSubscription<dynamic>? _savedSub;

  @override
  void initState() {
    super.initState();
    _targetDurationSec = widget.durationSec > 0 ? widget.durationSec : 5.0;

    _statusSub = widget.studioStatusStream.listen(_handleStatusUpdate);
    _savedSub = widget.sessionSavedStream?.listen(_handleSessionSaved);
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _savedSub?.cancel();
    _recordingProgressTimer?.cancel();
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  void _handleStatusUpdate(String status) {
    if (!mounted) return;

    if (status.startsWith('COUNTDOWN')) {
      final parts = status.split(' ');
      if (parts.length >= 2) {
        final stepParts = parts[1].split('/');
        final step = int.tryParse(stepParts[0]) ?? 1;
        setState(() {
          _state = StudioActiveState.countdown;
          _countdownStep = step;
        });
      }
    } else if (status.startsWith('RECORDING')) {
      final parts = status.split(' ');
      if (parts.length >= 2) {
        final parsedDur = double.tryParse(parts[1]);
        if (parsedDur != null && parsedDur > 0) {
          _targetDurationSec = parsedDur;
        }
      }
      _startRecordingProgress();
    } else if (status.startsWith('FINISHED')) {
      final parts = status.split(' ');
      if (parts.length >= 2) {
        _samplesCollected = int.tryParse(parts[1]) ?? 0;
      }
      _recordingProgressTimer?.cancel();
      setState(() {
        _state = StudioActiveState.transmitting;
      });
    } else if (status == 'CANCELLED') {
      _recordingProgressTimer?.cancel();
      setState(() {
        _state = StudioActiveState.cancelled;
      });
      _autoDismissTimer?.cancel();
      _autoDismissTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    } else if (status.startsWith('ERROR')) {
      _recordingProgressTimer?.cancel();
      setState(() {
        _state = StudioActiveState.error;
        _errorMessage = status.replaceFirst('ERROR', '').trim();
      });
    }
  }

  void _startRecordingProgress() {
    _recordingProgressTimer?.cancel();
    setState(() {
      _state = StudioActiveState.recording;
      _elapsedRecordingSec = 0.0;
    });

    const tickMs = 50;
    _recordingProgressTimer = Timer.periodic(const Duration(milliseconds: tickMs), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _elapsedRecordingSec += tickMs / 1000.0;
        if (_elapsedRecordingSec >= _targetDurationSec) {
          _elapsedRecordingSec = _targetDurationSec;
        }
      });
    });
  }

  void _handleSessionSaved(dynamic session) {
    if (!mounted) return;
    _recordingProgressTimer?.cancel();

    int readingsCount = _samplesCollected;
    if (session is StudioSessionModel) {
      readingsCount = session.readings.length;
    } else if (session is Map && session['readings'] is List) {
      readingsCount = (session['readings'] as List).length;
    }

    setState(() {
      _state = StudioActiveState.success;
      _samplesCollected = readingsCount;
    });

    // Auto-dismiss smoothly after 1.5 seconds upon success
    _autoDismissTimer?.cancel();
    _autoDismissTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  String _getActivityEmoji(String key) {
    final match = StudioSessionDialog.defaultActivities.firstWhere(
      (opt) => opt.key.toLowerCase() == key.toLowerCase(),
      orElse: () => const StudioActivityOption(key: 'custom', label: 'Personnalisé', emoji: '🏷️'),
    );
    return match.emoji;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emoji = _getActivityEmoji(widget.label);
    final canDismiss = _state == StudioActiveState.success ||
        _state == StudioActiveState.cancelled ||
        _state == StudioActiveState.error;

    return PopScope(
      canPop: canDismiss,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _state == StudioActiveState.recording
                    ? Colors.redAccent.withValues(alpha: 0.15)
                    : theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Text(emoji, style: const TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Session Studio : ${widget.label}',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Capteur IMU à 50 Hz',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            _buildStateContent(theme),
          ],
        ),
        actions: _buildActions(theme),
      ),
    );
  }

  Widget _buildStateContent(ThemeData theme) {
    switch (_state) {
      case StudioActiveState.countdown:
        final remainingSteps = _totalCountdownSteps - _countdownStep + 1;
        return Column(
          children: [
            Text(
              'Préparez-vous : 3... 2... 1...',
              style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 90,
                  height: 90,
                  child: CircularProgressIndicator(
                    value: _countdownStep / _totalCountdownSteps,
                    strokeWidth: 6,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    color: Colors.amber.shade700,
                  ),
                ),
                Text(
                  '$remainingSteps',
                  key: const Key('countdown_step_text'),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'La chaussure vibre pour cadencer le départ.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        );

      case StudioActiveState.recording:
        final progress = _targetDurationSec > 0
            ? (_elapsedRecordingSec / _targetDurationSec).clamp(0.0, 1.0)
            : 0.0;
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '🔴 Enregistrement en cours...',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.redAccent.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 12,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                color: Colors.redAccent,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${_elapsedRecordingSec.toStringAsFixed(1)}s / ${_targetDurationSec.toStringAsFixed(1)}s',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Effectuez le geste demandé jusqu\'à la fin de la barre.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        );

      case StudioActiveState.transmitting:
        return Column(
          children: [
            const SizedBox(
              width: 50,
              height: 50,
              child: CircularProgressIndicator(strokeWidth: 4),
            ),
            const SizedBox(height: 16),
            Text(
              '⚡ Synchronisation des données biomécaniques...',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              _samplesCollected > 0
                  ? 'Transfert de $_samplesCollected trames haute fréquence...'
                  : 'Réception des trames haute fréquence via BLE...',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        );

      case StudioActiveState.success:
        return Column(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 54),
            const SizedBox(height: 12),
            Text(
              '✅ Capture terminée avec succès !',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.green.shade800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$_samplesCollected échantillons synchronisés.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        );

      case StudioActiveState.cancelled:
        return Column(
          children: [
            const Icon(Icons.cancel_outlined, color: Colors.orange, size: 50),
            const SizedBox(height: 12),
            Text(
              'Session annulée',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.orange.shade800,
              ),
            ),
          ],
        );

      case StudioActiveState.error:
        return Column(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 50),
            const SizedBox(height: 12),
            Text(
              'Erreur Studio',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.redAccent.shade700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage ?? 'Une erreur est survenue lors de la capture.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        );
    }
  }

  List<Widget> _buildActions(ThemeData theme) {
    if (_state == StudioActiveState.countdown || _state == StudioActiveState.recording) {
      return [
        TextButton(
          onPressed: _isCancelling
              ? null
              : () async {
                  setState(() => _isCancelling = true);
                  _recordingProgressTimer?.cancel();
                  if (widget.onCancel != null) {
                    await widget.onCancel!();
                  }
                  if (mounted && Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                },
          child: const Text('Annuler', style: TextStyle(color: Colors.redAccent)),
        ),
      ];
    } else if (_state == StudioActiveState.error || _state == StudioActiveState.cancelled) {
      return [
        FilledButton(
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          },
          child: const Text('Fermer'),
        ),
      ];
    }
    return [];
  }
}
