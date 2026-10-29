import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/studio_session_model.dart';
import '../../services/audio/studio_audio_feedback_service.dart';
import 'studio/studio_recording_gauge.dart';
import 'studio_session_dialog.dart';
import '../../services/ble/ble_connection_manager.dart';

export 'studio/studio_recording_gauge.dart' show StudioActiveState, StudioRecordingGauge;

/// Modal dialog overlay displaying live progress of a Studio recording session.
class StudioRecordingDialog extends StatefulWidget {
  final String label;
  final double durationSec;
  final Stream<String> studioStatusStream;
  final Stream<dynamic>? sessionSavedStream;
  final Stream<BleConnectionStatus>? connectionStatusStream;
  final Future<void> Function()? onCancel;
  final Future<void> Function()? onFinish;
  final StudioAudioFeedbackService? audioService;

  const StudioRecordingDialog({
    super.key,
    required this.label,
    this.durationSec = 5.0,
    required this.studioStatusStream,
    this.sessionSavedStream,
    this.connectionStatusStream,
    this.onCancel,
    this.onFinish,
    this.audioService,
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
  Timer? _countdownTimer;
  Timer? _recordingProgressTimer;
  Timer? _autoDismissTimer;
  Timer? _transmissionTimeoutTimer;

  int _samplesCollected = 0;
  String? _errorMessage;
  bool _isCancelling = false;
  bool _isFinishing = false;

  static const double _minimumRecordingDurationSec = 2.0;

  StreamSubscription<String>? _statusSub;
  StreamSubscription<dynamic>? _savedSub;
  StreamSubscription<BleConnectionStatus>? _connSub;
  Timer? _recordingTimeoutTimer;

  late final StudioAudioFeedbackService _audioService;
  bool _ownsAudioService = false;

  @override
  void initState() {
    super.initState();
    if (widget.audioService != null) {
      _audioService = widget.audioService!;
    } else {
      _audioService = StudioAudioFeedbackService();
      _ownsAudioService = true;
    }
    _targetDurationSec = widget.durationSec > 0 ? widget.durationSec : 5.0;

    _audioService.playCountdownBeep();
    _startCountdownTimer();
    _statusSub = widget.studioStatusStream.listen(_handleStatusUpdate);
    _savedSub = widget.sessionSavedStream?.listen(_handleSessionSaved);
    _connSub = widget.connectionStatusStream?.listen(_handleConnectionUpdate);
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _statusSub?.cancel();
    _savedSub?.cancel();
    _connSub?.cancel();
    _recordingTimeoutTimer?.cancel();
    _recordingProgressTimer?.cancel();
    _autoDismissTimer?.cancel();
    _transmissionTimeoutTimer?.cancel();
    _audioService.stopContinuousTone();
    if (_ownsAudioService) {
      _audioService.dispose();
    }
    super.dispose();
  }

  void _handleConnectionUpdate(BleConnectionStatus status) {
    if (!mounted) return;
    if (status == BleConnectionStatus.disconnected || status == BleConnectionStatus.scanning) {
      if (_state == StudioActiveState.countdown ||
          _state == StudioActiveState.recording ||
          _state == StudioActiveState.transmitting) {
        _countdownTimer?.cancel();
        _recordingProgressTimer?.cancel();
        _transmissionTimeoutTimer?.cancel();
        _recordingTimeoutTimer?.cancel();
        _audioService.stopContinuousTone();
        setState(() {
          _state = StudioActiveState.error;
          _errorMessage = 'Connexion Bluetooth avec la chaussure interrompue.';
        });
      }
    }
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_state != StudioActiveState.countdown) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_countdownStep < _totalCountdownSteps) {
          _countdownStep++;
          _audioService.playCountdownBeep();
        } else {
          timer.cancel();
          _startRecordingProgress();
        }
      });
    });
  }

  void _handleStatusUpdate(String status) {
    if (!mounted) return;

    if (status.startsWith('COUNTDOWN')) {
      if (_state == StudioActiveState.recording ||
          _state == StudioActiveState.transmitting ||
          _state == StudioActiveState.success) {
        return;
      }
      final parts = status.split(' ');
      if (parts.length >= 2) {
        final stepParts = parts[1].split('/');
        final step = int.tryParse(stepParts[0]) ?? 1;
        if (_state != StudioActiveState.countdown || _countdownStep != step) {
          _audioService.playCountdownBeep();
        }
        setState(() {
          _state = StudioActiveState.countdown;
          _countdownStep = step;
        });
        _startCountdownTimer();
      }
    } else if (status.startsWith('RECORDING')) {
      _countdownTimer?.cancel();
      final parts = status.split(' ');
      if (parts.length >= 2) {
        final parsedDur = double.tryParse(parts[1]);
        if (parsedDur != null && parsedDur > 0) {
          _targetDurationSec = parsedDur;
        }
      }
      _startRecordingProgress();
    } else if (status.startsWith('FINISHED')) {
      _countdownTimer?.cancel();
      _audioService.stopContinuousTone();
      final parts = status.split(' ');
      if (parts.length >= 2) {
        _samplesCollected = int.tryParse(parts[1]) ?? 0;
      }
      if (parts.length >= 4) {
        final actualDuration = double.tryParse(parts[3]);
        if (actualDuration != null &&
            actualDuration >= _minimumRecordingDurationSec) {
          _targetDurationSec = actualDuration;
          _elapsedRecordingSec = actualDuration;
        }
      }
      _recordingProgressTimer?.cancel();
      _recordingTimeoutTimer?.cancel();
      setState(() {
        _state = StudioActiveState.transmitting;
        _isFinishing = false;
      });
      _startTransmissionTimeout();
    } else if (status == 'CANCELLED') {
      _countdownTimer?.cancel();
      _recordingProgressTimer?.cancel();
      _transmissionTimeoutTimer?.cancel();
      _recordingTimeoutTimer?.cancel();
      _audioService.stopContinuousTone();
      setState(() {
        _state = StudioActiveState.cancelled;
      });
      _autoDismissTimer?.cancel();
      _autoDismissTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop(false);
        }
      });
    } else if (status.startsWith('ERROR')) {
      _countdownTimer?.cancel();
      _recordingProgressTimer?.cancel();
      _recordingTimeoutTimer?.cancel();
      _audioService.stopContinuousTone();
      setState(() {
        _state = StudioActiveState.error;
        _isFinishing = false;
        _errorMessage = status.replaceFirst('ERROR', '').trim();
      });
    }
  }

  void _startRecordingProgress() {
    _countdownTimer?.cancel();
    _recordingProgressTimer?.cancel();
    _audioService.startContinuousRecordingTone();
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

    _recordingTimeoutTimer?.cancel();
    _recordingTimeoutTimer = Timer(Duration(milliseconds: ((_targetDurationSec + 6.0) * 1000).toInt()), () {
      if (!mounted) return;
      if (_state == StudioActiveState.recording) {
        _recordingProgressTimer?.cancel();
        _audioService.stopContinuousTone();
        setState(() {
          _state = StudioActiveState.error;
          _errorMessage = "Délai de capture dépassé : la chaussure n'a pas transmis la fin de session.";
        });
      }
    });
  }

  void _startTransmissionTimeout() {
    _transmissionTimeoutTimer?.cancel();
    _transmissionTimeoutTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted) return;
      if (_state == StudioActiveState.transmitting) {
        setState(() {
          _state = StudioActiveState.error;
          _errorMessage =
              'Délai d\'envoi dépassé : la connexion au Cloud a échoué. Vérifiez votre réseau.';
        });
      }
    });
  }

  void _handleSessionSaved(dynamic session) {
    if (!mounted) return;
    _recordingProgressTimer?.cancel();
    _transmissionTimeoutTimer?.cancel();
    _recordingTimeoutTimer?.cancel();
    _audioService.playFinishedChime();

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
        Navigator.of(context).pop(true);
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
        _state == StudioActiveState.error ||
        _state == StudioActiveState.transmitting ||
        _isCancelling;

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
            if (_state == StudioActiveState.recording &&
                _errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
        actions: _buildActions(theme),
      ),
    );
  }

  Widget _buildStateContent(ThemeData theme) {
    return StudioRecordingGauge(
      state: _state,
      countdownStep: _countdownStep,
      totalCountdownSteps: _totalCountdownSteps,
      elapsedRecordingSec: _elapsedRecordingSec,
      targetDurationSec: _targetDurationSec,
      samplesCollected: _samplesCollected,
      errorMessage: _errorMessage,
    );
  }

  List<Widget> _buildActions(ThemeData theme) {
    if (_state == StudioActiveState.countdown || _state == StudioActiveState.recording) {
      final actions = <Widget>[
        TextButton(
          onPressed: _isCancelling
              ? null
              : () async {
                  setState(() => _isCancelling = true);
                  _countdownTimer?.cancel();
                  _recordingProgressTimer?.cancel();
                  _recordingTimeoutTimer?.cancel();
                  unawaited(_audioService.stopContinuousTone());
                  try {
                    if (widget.onCancel != null) {
                      await widget.onCancel!().timeout(const Duration(milliseconds: 1500));
                    }
                  } catch (_) {
                    // Ignore cancel timeout / disconnection errors
                  } finally {
                    if (mounted && Navigator.of(context).canPop()) {
                      Navigator.of(context).pop(false);
                    }
                  }
                },
          child: const Text('Annuler', style: TextStyle(color: Colors.redAccent)),
        ),
      ];
      if (_state == StudioActiveState.recording &&
          _elapsedRecordingSec >= _minimumRecordingDurationSec &&
          _elapsedRecordingSec < _targetDurationSec &&
          widget.onFinish != null) {
        actions.insert(
          0,
          FilledButton.icon(
            onPressed: _isFinishing
                ? null
                : () async {
                    setState(() => _isFinishing = true);
                    try {
                      await widget.onFinish!();
                    } catch (error) {
                      if (!mounted) return;
                      setState(() {
                        _isFinishing = false;
                        _errorMessage =
                            "Impossible de terminer l'enregistrement : $error";
                      });
                    }
                  },
            icon: const Icon(Icons.stop, size: 18),
            label: Text(_isFinishing ? 'Arrêt...' : 'Terminer'),
          ),
        );
      }
      return actions;
    } else if (_state == StudioActiveState.transmitting) {
      return [
        TextButton(
          onPressed: () async {
            _recordingProgressTimer?.cancel();
            _transmissionTimeoutTimer?.cancel();
            _recordingTimeoutTimer?.cancel();
            unawaited(_audioService.stopContinuousTone());
            try {
              if (widget.onCancel != null) {
                await widget.onCancel!().timeout(const Duration(milliseconds: 1500));
              }
            } catch (_) {
              // Ignore cancel timeout
            } finally {
              if (mounted && Navigator.of(context).canPop()) {
                Navigator.of(context).pop(false);
              }
            }
          },
          child: const Text('Abandonner', style: TextStyle(color: Colors.redAccent)),
        ),
      ];
    } else if (_state == StudioActiveState.error || _state == StudioActiveState.cancelled) {
      return [
        FilledButton(
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop(false);
            }
          },
          child: const Text('Fermer'),
        ),
      ];
    }
    return [];
  }
}
