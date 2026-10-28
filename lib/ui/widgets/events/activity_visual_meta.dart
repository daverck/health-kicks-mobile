import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';

/// Unified visual representation (icon, color, label) for any physical activity
/// or biomechanical detection event across the mobile app.
class ActivityVisualMeta {
  final String label;
  final IconData icon;
  final Color color;

  const ActivityVisualMeta({
    required this.label,
    required this.icon,
    required this.color,
  });

  /// Returns the corresponding status color for confidence score:
  /// - Green (≥ 85%): High confidence
  /// - Amber/Orange (70% - 84%): Moderate confidence
  /// - Red (< 70%): Low confidence
  static Color confidenceColor(num confidencePercent) {
    if (confidencePercent >= 85) {
      return const Color(0xFF16A34A); // Green 600
    } else if (confidencePercent >= 70) {
      return const Color(0xFFD97706); // Amber 600
    } else {
      return const Color(0xFFDC2626); // Red 600
    }
  }

  /// Returns an icon depicting the confidence reliability level.
  static IconData confidenceIcon(num confidencePercent) {
    if (confidencePercent >= 85) {
      return Icons.check_circle_outline_rounded;
    } else if (confidencePercent >= 70) {
      return Icons.info_outline_rounded;
    } else {
      return Icons.warning_amber_rounded;
    }
  }

  /// Resolves the unified visual metadata for a given event type string.
  static ActivityVisualMeta fromEventType(
    BuildContext? context,
    String rawEventType, {
    bool isFall = false,
  }) {
    final l10n = context != null ? AppLocalizations.of(context) : null;
    final normalized = rawEventType.toLowerCase().trim();

    String tr(String key, String fallback) {
      if (l10n != null) {
        return l10n.translateEventType(key);
      }
      return fallback;
    }

    switch (normalized) {
      case 'walk':
      case 'walking':
        return ActivityVisualMeta(
          label: tr('walk', 'Marche'),
          icon: Icons.directions_walk_rounded,
          color: const Color(0xFF0F766E), // Teal 700
        );

      case 'run':
      case 'running':
        return ActivityVisualMeta(
          label: tr('run', 'Course à pied'),
          icon: Icons.directions_run_rounded,
          color: const Color(0xFF4F46E5), // Indigo 600
        );

      case 'stairs_up':
        return ActivityVisualMeta(
          label: tr('stairs_up', 'Escaliers (Montée)'),
          icon: Icons.stairs_rounded,
          color: const Color(0xFF0284C7), // Sky 600
        );

      case 'stairs_down':
        return ActivityVisualMeta(
          label: tr('stairs_down', 'Escaliers (Descente)'),
          icon: Icons.stairs_rounded,
          color: const Color(0xFF0D9488), // Teal 600
        );

      case 'stairs':
        return ActivityVisualMeta(
          label: tr('stairs', 'Escaliers'),
          icon: Icons.stairs_rounded,
          color: const Color(0xFF0284C7),
        );

      case 'idle':
        return ActivityVisualMeta(
          label: tr('idle', 'Repos / Debout'),
          icon: Icons.accessibility_rounded,
          color: const Color(0xFF64748B), // Slate 500
        );

      case 'sit_down':
      case 'sit':
        return ActivityVisualMeta(
          label: tr('sit_down', 'Position assise'),
          icon: Icons.airline_seat_recline_normal_rounded,
          color: const Color(0xFF8D6E63), // Brown 400
        );

      case 'stand_up':
        return ActivityVisualMeta(
          label: tr('stand_up', 'Relevage'),
          icon: Icons.accessibility_new_rounded,
          color: const Color(0xFF059669), // Emerald 600
        );

      case 'lying_supine':
        return ActivityVisualMeta(
          label: tr('lying_supine', 'Couché dorsal'),
          icon: Icons.bed_rounded,
          color: const Color(0xFF6366F1), // Indigo 500
        );

      case 'lying_prone':
        return ActivityVisualMeta(
          label: tr('lying_prone', 'Couché frontal'),
          icon: Icons.bed_rounded,
          color: const Color(0xFF8B5CF6), // Purple 500
        );

      case 'lying_lateral':
        return ActivityVisualMeta(
          label: tr('lying_lateral', 'Couché latéral'),
          icon: Icons.bed_rounded,
          color: const Color(0xFFA855F7), // Purple 400
        );

      case 'jump':
        return ActivityVisualMeta(
          label: tr('jump', 'Saut'),
          icon: Icons.nordic_walking_rounded,
          color: const Color(0xFF7C3AED), // Purple 600
        );

      case 'stumble_recover':
        return ActivityVisualMeta(
          label: tr('stumble_recover', 'Trébuchement rattrapé'),
          icon: Icons.sync_problem_rounded,
          color: const Color(0xFFD97706), // Amber 600
        );

      case 'fall_forward':
        return ActivityVisualMeta(
          label: tr('fall_forward', 'Chute avant'),
          icon: Icons.warning_amber_rounded,
          color: const Color(0xFFDC2626), // Red 600
        );

      case 'fall_backward':
        return ActivityVisualMeta(
          label: tr('fall_backward', 'Chute arrière'),
          icon: Icons.warning_amber_rounded,
          color: const Color(0xFFDC2626),
        );

      case 'fall_lateral':
        return ActivityVisualMeta(
          label: tr('fall_lateral', 'Chute latérale'),
          icon: Icons.warning_amber_rounded,
          color: const Color(0xFFDC2626),
        );

      case 'fall_recovery':
        return ActivityVisualMeta(
          label: tr('fall_recovery', 'Chute relevée'),
          icon: Icons.sync_problem_rounded,
          color: const Color(0xFFEA580C), // Orange 600
        );

      case 'free_fall':
        return ActivityVisualMeta(
          label: tr('free_fall', 'Chute libre (Impact violent)'),
          icon: Icons.warning_amber_rounded,
          color: const Color(0xFFB91C1C), // Deep Red 700
        );

      case 'fall':
      case 'fall_detected':
      case 'fall_generic':
        return ActivityVisualMeta(
          label: tr('fall_generic', 'Chute détectée'),
          icon: Icons.warning_amber_rounded,
          color: const Color(0xFFDC2626),
        );

      case 'high_impact':
        return ActivityVisualMeta(
          label: 'Impact élevé',
          icon: Icons.bolt_rounded,
          color: const Color(0xFFDC2626),
        );

      case 'inactivity_alert':
        return ActivityVisualMeta(
          label: tr('inactivity_alert', 'Rappel d\'inactivité'),
          icon: Icons.alarm_rounded,
          color: const Color(0xFFEA580C),
        );

      case 'calibration':
      case 'sensor_calibration':
        return const ActivityVisualMeta(
          label: 'Calibration des capteurs',
          icon: Icons.tune_rounded,
          color: Color(0xFF2563EB),
        );

      default:
        if (isFall || normalized.contains('fall')) {
          return ActivityVisualMeta(
            label: tr('fall_generic', 'Chute détectée'),
            icon: Icons.warning_amber_rounded,
            color: const Color(0xFFDC2626),
          );
        }
        return ActivityVisualMeta(
          label: normalized.replaceAll('_', ' ').toUpperCase(),
          icon: Icons.directions_walk_rounded,
          color: const Color(0xFF6B7280),
        );
    }
  }
}
