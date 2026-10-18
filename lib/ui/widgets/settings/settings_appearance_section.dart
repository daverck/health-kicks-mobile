import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../services/locale_service.dart';
import '../../../services/theme_service.dart';

/// Section managing app theme (light, dark, system) and localization / language settings.
class SettingsAppearanceSection extends StatelessWidget {
  final ThemeService themeService;
  final LocaleService localeService;
  final VoidCallback onOpenLanguageSelector;

  const SettingsAppearanceSection({
    super.key,
    required this.themeService,
    required this.localeService,
    required this.onOpenLanguageSelector,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
