import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../services/background_surveillance_service.dart';
import '../../../services/ble/ble_footwear_client.dart';
import '../../../services/inactivity_settings_service.dart';
import '../../../services/locale_service.dart';
import '../../../services/theme_service.dart';

/// Section widget bundling surveillance mode, inactivity alerts, sensor calibration, appearance/theme, and language settings.
class SettingsBiomechanicsSection extends StatelessWidget {
  final BackgroundSurveillanceService surveillanceService;
  final InactivitySettingsService inactivityService;
  final ThemeService themeService;
  final LocaleService localeService;
  final BleFootwearClient? bleClient;
  final bool isBleReady;
  final VoidCallback onOpenCalibrationDialog;
  final VoidCallback onOpenLanguageSelector;

  const SettingsBiomechanicsSection({
    super.key,
    required this.surveillanceService,
    required this.inactivityService,
    required this.themeService,
    required this.localeService,
    this.bleClient,
    required this.isBleReady,
    required this.onOpenCalibrationDialog,
    required this.onOpenLanguageSelector,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),

        // Surveillance Mode SwitchListTile
        SwitchListTile(
          secondary: Icon(
            Icons.shield_outlined,
            color: surveillanceService.isSurveillanceActive
                ? theme.colorScheme.primary
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

        // Platform warning or battery note
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
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
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
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Gestion intelligente de la batterie',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
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

        // Prolonged Inactivity Reminder Category
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            'RAPPEL D\'INACTIVITÉ PROLONGÉE',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
        ),

        SwitchListTile(
          secondary: Icon(
            Icons.airline_seat_recline_normal_outlined,
            color: inactivityService.isEnabled
                ? theme.colorScheme.primary
                : Colors.grey,
          ),
          title: const Text(
            'Alerte de sédentarité',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            'Vibration discrète de la chaussure après une longue période d\'immobilité',
          ),
          value: inactivityService.isEnabled,
          onChanged: (bool value) async {
            await inactivityService.updateSettings(
              enabled: value,
              repeatEnabled: inactivityService.isRepeatEnabled,
              thresholdMinutes: inactivityService.thresholdMinutes,
              cooldownMinutes: inactivityService.cooldownMinutes,
              bleClient: bleClient,
            );
          },
        ),

        if (inactivityService.isEnabled) ...[
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
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${inactivityService.thresholdMinutes} min',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                Slider(
                  value: inactivityService.thresholdMinutes.toDouble(),
                  min: 10,
                  max: 120,
                  divisions: 22,
                  label: '${inactivityService.thresholdMinutes} min',
                  onChanged: (double val) {
                    inactivityService.updateSettings(
                      enabled: inactivityService.isEnabled,
                      repeatEnabled: inactivityService.isRepeatEnabled,
                      thresholdMinutes: val.round(),
                      cooldownMinutes: inactivityService.cooldownMinutes,
                      bleClient: bleClient,
                    );
                  },
                ),
              ],
            ),
          ),
          SwitchListTile(
            secondary: Icon(
              Icons.replay_outlined,
              color: inactivityService.isRepeatEnabled
                  ? theme.colorScheme.primary
                  : Colors.grey,
            ),
            title: const Text(
              'Répéter les alertes',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Fait re-vibrer la chaussure à intervalle régulier si vous restez assis',
            ),
            value: inactivityService.isRepeatEnabled,
            onChanged: (bool value) async {
              await inactivityService.updateSettings(
                enabled: inactivityService.isEnabled,
                repeatEnabled: value,
                thresholdMinutes: inactivityService.thresholdMinutes,
                cooldownMinutes: inactivityService.cooldownMinutes,
                bleClient: bleClient,
              );
            },
          ),
          if (inactivityService.isRepeatEnabled)
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
                          color: theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${inactivityService.cooldownMinutes} min',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: inactivityService.cooldownMinutes.toDouble(),
                    min: 5,
                    max: 30,
                    divisions: 5,
                    label: '${inactivityService.cooldownMinutes} min',
                    onChanged: (double val) {
                      inactivityService.updateSettings(
                        enabled: inactivityService.isEnabled,
                        repeatEnabled: inactivityService.isRepeatEnabled,
                        thresholdMinutes: inactivityService.thresholdMinutes,
                        cooldownMinutes: val.round(),
                        bleClient: bleClient,
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

        // Sensor Calibration Category
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            'CALIBRATION DU CAPTEUR (ASSIETTE)',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
        ),
        ListTile(
          leading: Icon(
            Icons.screen_rotation_outlined,
            color: theme.colorScheme.primary,
          ),
          title: const Text(
            'Calibration de l\'assiette (Zéro gravité)',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            'Recalibre l\'horizontalité et la compensation d\'inclinaison mécanique',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: onOpenCalibrationDialog,
        ),

        const Divider(height: 32),

        // App Theme Category
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            'APPARENCE & THÈME',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
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
                color: theme.dividerColor.withValues(alpha: 0.2),
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
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ListenableBuilder(
                    listenable: themeService,
                    builder: (context, _) {
                      return SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<AppThemeMode>(
                          segments: [
                            ButtonSegment<AppThemeMode>(
                              value: AppThemeMode.system,
                              label: Text(l10n.themeSystem),
                              icon: const Icon(Icons.brightness_auto, size: 18),
                            ),
                            ButtonSegment<AppThemeMode>(
                              value: AppThemeMode.light,
                              label: Text(l10n.themeLight),
                              icon: const Icon(Icons.light_mode, size: 18),
                            ),
                            ButtonSegment<AppThemeMode>(
                              value: AppThemeMode.dark,
                              label: Text(l10n.themeDark),
                              icon: const Icon(Icons.dark_mode, size: 18),
                            ),
                          ],
                          selected: {themeService.currentMode},
                          onSelectionChanged: (Set<AppThemeMode> selected) {
                            if (selected.isNotEmpty) {
                              themeService.setThemeMode(selected.first);
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

        const SizedBox(height: 8),

        // Language & Region Category
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            l10n.languageRegion,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.15),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.languageTitle,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.languageDesc,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ListenableBuilder(
                    listenable: localeService,
                    builder: (context, _) {
                      final current = localeService.currentLanguage;
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: onOpenLanguageSelector,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.dividerColor.withValues(alpha: 0.25),
                            ),
                            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          ),
                          child: Row(
                            children: [
                              Text(current.flag, style: const TextStyle(fontSize: 22)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      current.nativeName,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    Text(
                                      current.name,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.arrow_drop_down_rounded, size: 28),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
