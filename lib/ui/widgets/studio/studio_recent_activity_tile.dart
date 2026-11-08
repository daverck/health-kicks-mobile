import 'package:flutter/material.dart';
import '../../../models/studio_activity_option.dart';
import '../../../services/studio/studio_api_service.dart';

/// Interactive tile representing a recently recorded Studio activity shortcut.
class StudioRecentActivityTile extends StatelessWidget {
  final String activityKey;
  final bool isSelected;
  final String customText;
  final StudioDatasetStats datasetStats;
  final bool isEdgeAi;
  final ValueChanged<String> onSelect;
  final int targetPerClass;

  const StudioRecentActivityTile({
    super.key,
    required this.activityKey,
    required this.isSelected,
    required this.customText,
    required this.datasetStats,
    required this.isEdgeAi,
    required this.onSelect,
    this.targetPerClass = 25,
  });

  Widget _buildCompactCountBadge({
    required Key badgeKey,
    required String icon,
    required int count,
    required Color activeBg,
    required Color activeText,
    required Color inactiveBg,
    required Color inactiveText,
  }) {
    final isActive = count > 0;
    return Container(
      key: badgeKey,
      padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 1),
      decoration: BoxDecoration(
        color: isActive ? activeBg : inactiveBg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$icon$count',
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          color: isActive ? activeText : inactiveText,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final option = StudioActivityOption.defaultActivities.firstWhere(
      (activity) => activity.key == activityKey,
      orElse: () => StudioActivityOption(
        key: activityKey,
        label: activityKey,
        emoji: '🏷️',
      ),
    );

    final label = activityKey == 'custom' && customText.isNotEmpty
        ? customText
        : option.label;
    final effectiveLabelKey = activityKey == 'custom' && customText.isNotEmpty
        ? customText
        : activityKey;

    final totalCount = datasetStats.getCountForLabel(effectiveLabelKey);
    final validatedCount =
        datasetStats.getValidatedCountForLabel(effectiveLabelKey);
    final pendingCount = datasetStats.getPendingCountForLabel(effectiveLabelKey);
    final showCounts = totalCount < targetPerClass;

    return SizedBox(
      width: 126,
      height: 58,
      child: Material(
        color: isSelected
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: ValueKey('studio-recent-activity-$activityKey'),
          borderRadius: BorderRadius.circular(10),
          onTap: () => onSelect(activityKey),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(option.emoji),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        isEdgeAi ? '⚡ Edge AI' : '🧪 R&D',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: isEdgeAi
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFF6A1B9A),
                        ),
                      ),
                    ),
                    if (showCounts) ...[
                      const SizedBox(width: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildCompactCountBadge(
                            badgeKey: ValueKey('studio-recent-validated-$activityKey'),
                            icon: '✅',
                            count: validatedCount,
                            activeBg: isDark
                                ? const Color(0xFF064E3B)
                                : const Color(0xFFD1FAE5),
                            activeText: isDark
                                ? const Color(0xFFA7F3D0)
                                : const Color(0xFF065F46),
                            inactiveBg: isDark
                                ? const Color(0xFF374151)
                                : const Color(0xFFF3F4F6),
                            inactiveText: const Color(0xFF9CA3AF),
                          ),
                          const SizedBox(width: 2),
                          _buildCompactCountBadge(
                            badgeKey: ValueKey('studio-recent-pending-$activityKey'),
                            icon: '⏳',
                            count: pendingCount,
                            activeBg: isDark
                                ? const Color(0xFF78350F)
                                : const Color(0xFFFEF3C7),
                            activeText: isDark
                                ? const Color(0xFFFDE68A)
                                : const Color(0xFF92400E),
                            inactiveBg: isDark
                                ? const Color(0xFF374151)
                                : const Color(0xFFF3F4F6),
                            inactiveText: const Color(0xFF9CA3AF),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
