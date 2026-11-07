import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/ble/ble_footwear_client.dart';
import '../../../services/fall_sensitivity_settings_service.dart';

/// Card for configuring fall detection sensitivity (confidence threshold) and fall alert cooldown.
class SettingsFallSensitivityCard extends StatefulWidget {
  final FallSensitivitySettingsService fallSensitivityService;
  final BleFootwearClient? bleClient;
  final bool isBleReady;

  const SettingsFallSensitivityCard({
    super.key,
    required this.fallSensitivityService,
    this.bleClient,
    required this.isBleReady,
  });

  @override
  State<SettingsFallSensitivityCard> createState() => _SettingsFallSensitivityCardState();
}

class _SettingsFallSensitivityCardState extends State<SettingsFallSensitivityCard> {
  late double _localThreshold;
  late double _localCooldownSeconds;
  Timer? _thresholdDebounceTimer;
  Timer? _cooldownDebounceTimer;

  @override
  void initState() {
    super.initState();
    _localThreshold = widget.fallSensitivityService.threshold;
    _localCooldownSeconds = widget.fallSensitivityService.cooldownSeconds;
  }

  @override
  void didUpdateWidget(covariant SettingsFallSensitivityCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fallSensitivityService != oldWidget.fallSensitivityService) {
      if (_thresholdDebounceTimer == null || !_thresholdDebounceTimer!.isActive) {
        _localThreshold = widget.fallSensitivityService.threshold;
      }
      if (_cooldownDebounceTimer == null || !_cooldownDebounceTimer!.isActive) {
        _localCooldownSeconds = widget.fallSensitivityService.cooldownSeconds;
      }
    }
  }

  @override
  void dispose() {
    _thresholdDebounceTimer?.cancel();
    _cooldownDebounceTimer?.cancel();
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
        if (_cooldownDebounceTimer == null || !_cooldownDebounceTimer!.isActive) {
          _localCooldownSeconds = widget.fallSensitivityService.cooldownSeconds;
        }

        final thresholdPercent = (_localThreshold * 100).round();
        final sensitivityLabel = _getSensitivityLabel(_localThreshold);
        final sensitivityDescription = _getSensitivityDescription(_localThreshold);
        final cooldownFormatted =
            FallSensitivitySettingsService.formatCooldownSeconds(_localCooldownSeconds);

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with icon and title
                Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 24,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sensibilité de détection des chutes',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Ajustez le seuil de confiance pour déclencher les alertes',
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

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
                        mainAxisSize: minAxisSize(),
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

                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14.0),
                  child: Divider(height: 1),
                ),

                // Fall Cooldown Slider section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Délai entre deux alertes (Cooldown)',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Intervalle minimal avant de pouvoir déclencher une nouvelle alerte de chute',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        cooldownFormatted,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Slider(
                      value: _localCooldownSeconds,
                      min: FallSensitivitySettingsService.minCooldownSeconds,
                      max: FallSensitivitySettingsService.maxCooldownSeconds,
                      divisions: FallSensitivitySettingsService.cooldownSliderDivisions,
                      label: cooldownFormatted,
                      onChanged: (double value) {
                        setState(() => _localCooldownSeconds = value);
                        _cooldownDebounceTimer?.cancel();
                        _cooldownDebounceTimer =
                            Timer(const Duration(milliseconds: 300), () async {
                          await widget.fallSensitivityService.setCooldownSeconds(
                            _localCooldownSeconds,
                            bleClient: widget.bleClient,
                          );
                        });
                      },
                      onChangeEnd: (double value) async {
                        _cooldownDebounceTimer?.cancel();
                        await widget.fallSensitivityService.setCooldownSeconds(
                          value,
                          bleClient: widget.bleClient,
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          FallSensitivitySettingsService.formatCooldownSeconds(
                            FallSensitivitySettingsService.minCooldownSeconds,
                          ),
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          '${FallSensitivitySettingsService.formatCooldownSeconds(FallSensitivitySettingsService.defaultCooldownSeconds)} (défaut)',
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          FallSensitivitySettingsService.formatCooldownSeconds(
                            FallSensitivitySettingsService.maxCooldownSeconds,
                          ),
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Sync status
                Row(
                  children: [
                    Icon(
                      widget.isBleReady ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                      size: 14,
                      color: widget.isBleReady ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.isBleReady
                            ? 'Synchronisé en direct avec la chaussure'
                            : 'Sera synchronisé dès la prochaine connexion BLE',
                        style: TextStyle(
                          fontSize: 11,
                          color: widget.isBleReady ? Colors.green.shade700 : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  MainAxisSize minAxisSize() => MainAxisSize.min;
}
