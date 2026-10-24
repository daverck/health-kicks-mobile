import 'package:flutter/material.dart';
import '../../../services/background_surveillance_service.dart';
import '../../../services/ble/ble_footwear_client.dart';
import '../../../services/fall_sensitivity_settings_service.dart';
import '../../../services/inactivity_settings_service.dart';
import '../../../services/integrations/health_connect_service.dart';
import '../../../services/locale_service.dart';
import '../../../services/theme_service.dart';
import 'settings_appearance_section.dart';
import 'settings_fall_sensitivity_card.dart';
import 'settings_health_connect_card.dart';
import 'settings_inactivity_card.dart';

export 'settings_appearance_section.dart';
export 'settings_fall_sensitivity_card.dart';
export 'settings_health_connect_card.dart';
export 'settings_inactivity_card.dart';

/// Section widget bundling surveillance mode, inactivity alerts, fall sensitivity, sensor calibration, appearance/theme, and language settings.
class SettingsBiomechanicsSection extends StatelessWidget {
  final BackgroundSurveillanceService surveillanceService;
  final InactivitySettingsService inactivityService;
  final FallSensitivitySettingsService fallSensitivityService;
  final ThemeService themeService;
  final LocaleService localeService;
  final BleFootwearClient? bleClient;
  final bool isBleReady;
  final VoidCallback onOpenCalibrationDialog;
  final VoidCallback onOpenLanguageSelector;
  final HealthConnectService? healthConnectService;

  const SettingsBiomechanicsSection({
    super.key,
    required this.surveillanceService,
    required this.inactivityService,
    required this.fallSensitivityService,
    required this.themeService,
    required this.localeService,
    this.bleClient,
    required this.isBleReady,
    required this.onOpenCalibrationDialog,
    required this.onOpenLanguageSelector,
    this.healthConnectService,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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

        // Fall Sensitivity Category
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            'SENSIBILITÉ DÉTECTION DE CHUTE',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
        ),
        SettingsFallSensitivityCard(
          fallSensitivityService: fallSensitivityService,
          bleClient: bleClient,
          isBleReady: isBleReady,
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
        SettingsInactivityCard(
          inactivityService: inactivityService,
          bleClient: bleClient,
          isBleReady: isBleReady,
        ),

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

        if (healthConnectService != null) ...[
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              'INTÉGRATIONS SANTÉ (CONNECTIVITY)',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
          ),
          SettingsHealthConnectCard(healthConnectService: healthConnectService!),
        ],

        const Divider(height: 32),

        // App Theme & Language Category
        SettingsAppearanceSection(
          themeService: themeService,
          localeService: localeService,
          onOpenLanguageSelector: onOpenLanguageSelector,
        ),
      ],
    );
  }
}
