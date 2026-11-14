import 'dart:async';
import 'package:material_ui/material_ui.dart';

import '../../../services/ble/ble_footwear_client.dart';
import '../../../services/fall_sensitivity_settings_service.dart';

/// Slider control for configuring fall detection sensitivity (confidence threshold).
class FallSensitivitySlider extends StatefulWidget {
  final FallSensitivitySettingsService fallSensitivityService;
  final BleFootwearClient? bleClient;

  const FallSensitivitySlider({
    super.key,
    required this.fallSensitivityService,
    this.bleClient,
  });

  @override
  State<FallSensitivitySlider> createState() => _FallSensitivitySliderState();
}

class _FallSensitivitySliderState extends State<FallSensitivitySlider> {
  late double _localThreshold;
  Timer? _thresholdDebounceTimer;

  @override
  void initState() {
    super.initState();
    _localThreshold = widget.fallSensitivityService.threshold;
  }

  @override
  void didUpdateWidget(covariant FallSensitivitySlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fallSensitivityService != oldWidget.fallSensitivityService) {
      if (_thresholdDebounceTimer == null || !_thresholdDebounceTimer!.isActive) {
        _localThreshold = widget.fallSensitivityService.threshold;
      }
    }
  }

  @override
  void dispose() {
    _thresholdDebounceTimer?.cancel();
    super.dispose();
  }

  String _getSensitivityLabel(double threshold) {
    if (threshold <= 0.40) {
      return 'Ultra sensible';
    } else if (threshold <= 0.45) {
      return 'Démo';
    } else if (threshold <= 0.55) {
      return 'Très sensible';
    } else if (threshold <= 0.70) {
      return 'Équilibrée';
    } else if (threshold <= 0.75) {
      return 'Recommandée';
    } else {
      return 'Robuste';
    }
  }

  String _getSensitivityDescription(double threshold) {
    if (threshold <= 0.40) {
      return 'Détecte presque toutes les anomalies de mouvement comme des chutes';
    } else if (threshold <= 0.45) {
      return 'Mode démonstration - très perméable aux faux positifs';
    } else if (threshold <= 0.55) {
      return 'Détection précoce avec quelques faux positifs acceptables';
    } else if (threshold <= 0.70) {
      return 'Équilibre optimal entre détection et précision';
    } else if (threshold <= 0.75) {
      return 'Recommandé pour un usage quotidien fiable';
    } else {
      return 'Seulement les chutes très certaines seront signalées';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: widget.fallSensitivityService,
      builder: (context, _) {
        if (_thresholdDebounceTimer == null || !_thresholdDebounceTimer!.isActive) {
          _localThreshold = widget.fallSensitivityService.threshold;
        }

        final thresholdPercent = (_localThreshold * 100).round();
        final sensitivityLabel = _getSensitivityLabel(_localThreshold);
        final sensitivityDescription = _getSensitivityDescription(_localThreshold);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sensitivity label with badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Niveau actuel:',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        sensitivityLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onPrimaryContainer
                              .withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '$thresholdPercent%',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Description text
            Text(
              sensitivityDescription,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            // Confidence Threshold Slider with labels
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Slider(
                  value: _localThreshold,
                  min: FallSensitivitySettingsService.minThreshold,
                  max: FallSensitivitySettingsService.maxThreshold,
                  divisions: FallSensitivitySettingsService.sliderDivisions,
                  label: '$thresholdPercent%',
                  onChanged: (double value) {
                    setState(() => _localThreshold = value);
                    _thresholdDebounceTimer?.cancel();
                    _thresholdDebounceTimer =
                        Timer(const Duration(milliseconds: 300), () async {
                      await widget.fallSensitivityService.setThreshold(
                        _localThreshold,
                        bleClient: widget.bleClient,
                      );
                    });
                  },
                  onChangeEnd: (double value) async {
                    _thresholdDebounceTimer?.cancel();
                    await widget.fallSensitivityService.setThreshold(
                      value,
                      bleClient: widget.bleClient,
                    );
                  },
                ),
                const SizedBox(height: 4),

                // Range labels
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${(FallSensitivitySettingsService.minThreshold * 100).round()}%',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      'Ultra sensible',
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    Text(
                      '${(FallSensitivitySettingsService.defaultThreshold * 100).round()}%',
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Recommandée',
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    Text(
                      '${(FallSensitivitySettingsService.maxThreshold * 100).round()}%',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      'Robuste',
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
