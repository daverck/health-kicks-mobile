import 'package:flutter/material.dart';
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
                      'Activités récentes',
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
                    label: const Text('Voir tout'),
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
                        'En attente de détections...',
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
    final meta = _getActivityMeta(activity.eventType, isFall: activity.isFall);
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
                      child: const Text(
                        'CHUTE',
                        style: TextStyle(
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

  _ActivityMeta _getActivityMeta(String eventType, {required bool isFall}) {
    if (isFall || eventType.contains('fall')) {
      return const _ActivityMeta(
        label: 'Chute',
        icon: Icons.warning_amber_rounded,
        color: Color(0xFFDC2626),
      );
    }

    switch (eventType.toLowerCase()) {
      case 'walk':
      case 'walking':
        return const _ActivityMeta(
          label: 'Marche',
          icon: Icons.directions_walk_rounded,
          color: Color(0xFF0F766E),
        );
      case 'run':
      case 'running':
        return const _ActivityMeta(
          label: 'Course',
          icon: Icons.directions_run_rounded,
          color: Colors.indigo,
        );
      case 'stairs':
        return const _ActivityMeta(
          label: 'Escaliers',
          icon: Icons.stairs_rounded,
          color: Colors.teal,
        );
      case 'idle':
        return const _ActivityMeta(
          label: 'Immobile',
          icon: Icons.chair_rounded,
          color: Colors.blueGrey,
        );
      case 'stumble_recover':
        return const _ActivityMeta(
          label: 'Trébuchement',
          icon: Icons.sync_problem_rounded,
          color: Colors.amber,
        );
      case 'inactivity_alert':
        return const _ActivityMeta(
          label: 'Rappel inactivité',
          icon: Icons.alarm_rounded,
          color: Colors.deepOrange,
        );
      default:
        return _ActivityMeta(
          label: eventType.replaceAll('_', ' '),
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

