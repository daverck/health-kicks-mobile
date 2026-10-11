import 'package:flutter/material.dart';
import '../../core/localization/app_localizations.dart';
import '../../models/activity_detection_model.dart';

/// Dashboard card displaying real-time stream of latest detected physical activities.
class RecentActivitiesCard extends StatelessWidget {
  final List<ActivityDetectionModel> activities;
  final VoidCallback? onViewAll;

  const RecentActivitiesCard({
    super.key,
    required this.activities,
    this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.directions_run_rounded,
                      color: theme.colorScheme.primary,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l10n.recentActivities,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (onViewAll != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: onViewAll,
                    icon: const Icon(Icons.chevron_right, size: 18),
                    label: Text(l10n.viewAll),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Content: Empty State or Activity List
            if (activities.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 12.0),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.history_toggle_off_rounded,
                        size: 32,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.waitingDetections,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Les dernières activités biomécaniques s\'afficheront ici.',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: activities.length.clamp(0, 5),
                separatorBuilder: (_, __) => const Divider(height: 12),
                itemBuilder: (context, index) {
                  final item = activities[index];
                  return _ActivityItemTile(activity: item);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ActivityItemTile extends StatelessWidget {
  final ActivityDetectionModel activity;

  const _ActivityItemTile({required this.activity});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final meta = _getActivityMeta(context, activity.eventType, isFall: activity.isFall);
    final formattedTime = _formatTimestamp(activity);

    return Row(
      children: [
        // Activity Icon with circular tinted container
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: meta.color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(meta.icon, color: meta.color, size: 20),
        ),
        const SizedBox(width: 10),

        // Activity Title + Relative Time
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    meta.label,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  if (activity.isFall) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        l10n.fallBadge,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                  if (activity.isHapticTriggered) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.vibration, size: 14, color: Colors.amber),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                formattedTime,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),

        // Confidence Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: meta.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${activity.confidencePercent}% conf.',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: meta.color,
            ),
          ),
        ),
      ],
    );
  }

  String _formatTimestamp(ActivityDetectionModel activity) {
    final dt = activity.effectiveTimestamp.toLocal();
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  _ActivityMeta _getActivityMeta(BuildContext context, String eventType, {required bool isFall}) {
    final l10n = AppLocalizations.of(context);
    switch (eventType.toLowerCase()) {
      case 'fall_forward':
        return _ActivityMeta(
          label: l10n.translateEventType('fall_forward'),
          icon: Icons.warning_amber_rounded,
          color: const Color(0xFFDC2626),
        );
      case 'fall_backward':
        return _ActivityMeta(
          label: l10n.translateEventType('fall_backward'),
          icon: Icons.warning_amber_rounded,
          color: const Color(0xFFDC2626),
        );
      case 'fall_lateral':
        return _ActivityMeta(
          label: l10n.translateEventType('fall_lateral'),
          icon: Icons.warning_amber_rounded,
          color: const Color(0xFFDC2626),
        );
      case 'fall_recovery':
        return _ActivityMeta(
          label: l10n.translateEventType('fall_recovery'),
          icon: Icons.sync_problem_rounded,
          color: Colors.orange,
        );
      case 'stand_up':
        return _ActivityMeta(
          label: l10n.translateEventType('stand_up'),
          icon: Icons.accessibility_new_rounded,
          color: const Color(0xFF0F766E),
        );
      case 'free_fall':
        return _ActivityMeta(
          label: l10n.translateEventType('free_fall'),
          icon: Icons.warning_amber_rounded,
          color: const Color(0xFFDC2626),
        );
      case 'fall':
      case 'fall_detected':
      case 'fall_generic':
        return _ActivityMeta(
          label: l10n.translateEventType('fall_generic'),
          icon: Icons.warning_amber_rounded,
          color: const Color(0xFFDC2626),
        );
      case 'walk':
      case 'walking':
        return _ActivityMeta(
          label: l10n.translateEventType('walk'),
          icon: Icons.directions_walk_rounded,
          color: const Color(0xFF0F766E),
        );
      case 'run':
      case 'running':
        return _ActivityMeta(
          label: l10n.translateEventType('run'),
          icon: Icons.directions_run_rounded,
          color: Colors.indigo,
        );
      case 'stairs_up':
        return _ActivityMeta(
          label: l10n.translateEventType('stairs_up'),
          icon: Icons.stairs_rounded,
          color: Colors.teal,
        );
      case 'stairs_down':
        return _ActivityMeta(
          label: l10n.translateEventType('stairs_down'),
          icon: Icons.stairs_rounded,
          color: Colors.teal.shade700,
        );
      case 'stairs':
        return _ActivityMeta(
          label: l10n.translateEventType('stairs'),
          icon: Icons.stairs_rounded,
          color: Colors.teal,
        );
      case 'calibration':
      case 'sensor_calibration':
        return _ActivityMeta(
          label: l10n.translateEventType('calibration'),
          icon: Icons.tune_rounded,
          color: const Color(0xFF0F766E),
        );
      case 'idle':
        return _ActivityMeta(
          label: l10n.translateEventType('idle'),
          icon: Icons.chair_rounded,
          color: Colors.blueGrey,
        );
      case 'sit_down':
      case 'sit':
        return _ActivityMeta(
          label: l10n.translateEventType('sit_down'),
          icon: Icons.chair_rounded,
          color: Colors.indigo,
        );
      case 'jump':
        return _ActivityMeta(
          label: l10n.translateEventType('jump'),
          icon: Icons.nordic_walking_rounded,
          color: Colors.deepPurple,
        );
      case 'stumble_recover':
        return _ActivityMeta(
          label: l10n.translateEventType('stumble_recover'),
          icon: Icons.sync_problem_rounded,
          color: Colors.amber,
        );
      case 'inactivity_alert':
        return _ActivityMeta(
          label: l10n.translateEventType('inactivity_alert'),
          icon: Icons.alarm_rounded,
          color: Colors.deepOrange,
        );
      default:
        if (isFall || eventType.contains('fall')) {
          return _ActivityMeta(
            label: l10n.translateEventType('fall_detected'),
            icon: Icons.warning_amber_rounded,
            color: const Color(0xFFDC2626),
          );
        }
        return _ActivityMeta(
          label: l10n.translateEventType(eventType),
          icon: Icons.directions_walk_rounded,
          color: Colors.grey,
        );
    }
  }
}

class _ActivityMeta {
  final String label;
  final IconData icon;
  final Color color;

  const _ActivityMeta({
    required this.label,
    required this.icon,
    required this.color,
  });
}

