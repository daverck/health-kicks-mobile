import 'package:flutter/material.dart';

/// Current lifecycle state of an active Studio recording session.
enum StudioActiveState {
  countdown,
  recording,
  transmitting,
  success,
  cancelled,
  error,
}

/// Visual gauge and progress indicator for an active Studio recording session.
class StudioRecordingGauge extends StatelessWidget {
  final StudioActiveState state;
  final int countdownStep;
  final int totalCountdownSteps;
  final double elapsedRecordingSec;
  final double targetDurationSec;
  final int samplesCollected;
  final String? errorMessage;

  const StudioRecordingGauge({
    super.key,
    required this.state,
    required this.countdownStep,
    this.totalCountdownSteps = 3,
    required this.elapsedRecordingSec,
    required this.targetDurationSec,
    required this.samplesCollected,
    this.errorMessage,
  });

  /// Computes a smooth color transition: Red -> Orange/Amber -> Green.
  /// Reaches full green once progress reaches [greenThreshold] (default 65%).
  static Color computeProgressColor(double progress, {double greenThreshold = 0.65}) {
    if (greenThreshold <= 0.0) return const Color(0xFF10B981);
    final clampedProgress = progress.clamp(0.0, 1.0);
    final normalized = (clampedProgress / greenThreshold).clamp(0.0, 1.0);

    const startColor = Colors.redAccent;
    const midColor = Colors.orangeAccent;
    const endColor = Color(0xFF10B981);

    if (normalized <= 0.5) {
      return Color.lerp(startColor, midColor, normalized * 2.0) ?? startColor;
    } else {
      return Color.lerp(midColor, endColor, (normalized - 0.5) * 2.0) ?? endColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    switch (state) {
      case StudioActiveState.countdown:
        final remainingSteps = totalCountdownSteps - countdownStep + 1;
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
                    value: countdownStep / totalCountdownSteps,
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
        final progress = targetDurationSec > 0
            ? (elapsedRecordingSec / targetDurationSec).clamp(0.0, 1.0)
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
                color: computeProgressColor(progress),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${elapsedRecordingSec.toStringAsFixed(1)}s / ${targetDurationSec.toStringAsFixed(1)}s',
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
              samplesCollected > 0
                  ? 'Transfert de $samplesCollected trames haute fréquence...'
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
              '$samplesCollected échantillons synchronisés.',
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
              errorMessage ?? 'Une erreur est survenue lors de la capture.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        );
    }
  }
}
