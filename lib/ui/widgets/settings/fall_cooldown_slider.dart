import 'dart:async';
import 'package:material_ui/material_ui.dart';

import '../../../services/ble/ble_footwear_client.dart';
import '../../../services/fall_sensitivity_settings_service.dart';

/// Slider control for configuring the cooldown delay between two fall alerts.
class FallCooldownSlider extends StatefulWidget {
  final FallSensitivitySettingsService fallSensitivityService;
  final BleFootwearClient? bleClient;

  const FallCooldownSlider({
    super.key,
    required this.fallSensitivityService,
    this.bleClient,
  });

  @override
  State<FallCooldownSlider> createState() => _FallCooldownSliderState();
}

class _FallCooldownSliderState extends State<FallCooldownSlider> {
  late double _localCooldownSeconds;
  Timer? _cooldownDebounceTimer;

  @override
  void initState() {
    super.initState();
    _localCooldownSeconds = widget.fallSensitivityService.cooldownSeconds;
  }

  @override
  void didUpdateWidget(covariant FallCooldownSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fallSensitivityService != oldWidget.fallSensitivityService) {
      if (_cooldownDebounceTimer == null || !_cooldownDebounceTimer!.isActive) {
        _localCooldownSeconds = widget.fallSensitivityService.cooldownSeconds;
      }
    }
  }

  @override
  void dispose() {
    _cooldownDebounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: widget.fallSensitivityService,
      builder: (context, _) {
        if (_cooldownDebounceTimer == null || !_cooldownDebounceTimer!.isActive) {
          _localCooldownSeconds = widget.fallSensitivityService.cooldownSeconds;
        }

        final cooldownFormatted =
            FallSensitivitySettingsService.formatCooldownSeconds(_localCooldownSeconds);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fall Cooldown Header with title and formatted badge
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
          ],
        );
      },
    );
  }
}
