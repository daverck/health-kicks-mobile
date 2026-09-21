import 'package:flutter/material.dart';
import '../../models/step_data_model.dart';

/// Card widget visualizing real-time step count, cadence (SPM), and activity breakdown.
class StepCounterCard extends StatelessWidget {
  final StepDataModel? stepData;
  final int stepGoal;

  const StepCounterCard({
    super.key,
    this.stepData,
    this.stepGoal = 10000,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = stepData?.totalSteps ?? 0;
    final walk = stepData?.walkSteps ?? 0;
    final run = stepData?.runSteps ?? 0;
    final stairs = stepData?.stairsSteps ?? 0;
    final unclassified = stepData?.unclassifiedSteps ?? 0;
    final cadence = stepData?.cadenceSpm ?? 0;

    final progress = (stepGoal > 0) ? (total / stepGoal).clamp(0.0, 1.0) : 0.0;
    final cadenceInfo = _getCadenceStyle(cadence);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Title & Cadence Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.directions_walk_rounded,
                        color: theme.colorScheme.onPrimaryContainer,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Podomètre',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Objectif: $stepGoal pas',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                // Cadence Badge (SPM)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cadenceInfo.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: cadenceInfo.color.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(cadenceInfo.icon, size: 16, color: cadenceInfo.color),
                      const SizedBox(width: 4),
                      Text(
                        '$cadence SPM',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: cadenceInfo.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Progress Bar & Total Steps Counter
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$total',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 8,
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  '${(progress * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Activity Breakdown Chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildActivityChip(
                  context: context,
                  label: 'Marche',
                  count: walk,
                  icon: Icons.directions_walk,
                  color: Colors.blue,
                ),
                _buildActivityChip(
                  context: context,
                  label: 'Course',
                  count: run,
                  icon: Icons.directions_run,
                  color: Colors.orange,
                ),
                _buildActivityChip(
                  context: context,
                  label: 'Escaliers',
                  count: stairs,
                  icon: Icons.stairs,
                  color: Colors.teal,
                ),
                _buildActivityChip(
                  context: context,
                  label: 'Autre',
                  count: unclassified,
                  icon: Icons.more_horiz,
                  color: Colors.blueGrey,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityChip({
    required BuildContext context,
    required String label,
    required int count,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  _CadenceStyle _getCadenceStyle(int cadence) {
    if (cadence == 0) {
      return const _CadenceStyle(
        label: 'Immobile',
        color: Colors.grey,
        icon: Icons.pause_circle_outline,
      );
    } else if (cadence < 100) {
      return const _CadenceStyle(
        label: 'Lente',
        color: Colors.blue,
        icon: Icons.directions_walk,
      );
    } else if (cadence < 140) {
      return const _CadenceStyle(
        label: 'Modérée',
        color: Colors.teal,
        icon: Icons.speed,
      );
    } else {
      return const _CadenceStyle(
        label: 'Rapide',
        color: Colors.deepOrange,
        icon: Icons.bolt,
      );
    }
  }
}

class _CadenceStyle {
  final String label;
  final Color color;
  final IconData icon;

  const _CadenceStyle({
    required this.label,
    required this.color,
    required this.icon,
  });
}
