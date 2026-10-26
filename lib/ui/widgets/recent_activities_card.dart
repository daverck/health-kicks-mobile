import 'package:flutter/material.dart';
import '../../core/localization/app_localizations.dart';
import '../../models/activity_detection_model.dart';
import '../../models/hitl/hitl_detection_item.dart';
import 'events/unified_activity_card.dart';

/// Dashboard card displaying real-time stream of latest detected physical activities,
/// with integrated Human-in-the-Loop (HITL) mode for clinicians and administrators.
class RecentActivitiesCard extends StatefulWidget {
  final List<ActivityDetectionModel> activities;
  final VoidCallback? onViewAll;
  final bool canUseHitl;
  final bool isHitlActive;
  final ValueChanged<bool>? onToggleHitl;
  final List<HitlDetectionItem>? hitlItems;
  final void Function(HitlDetectionItem item, String newLabel)? onUpdateHitlLabel;
  final void Function(HitlDetectionItem item)? onConfirmHitl;
  final void Function(HitlDetectionItem item)? onDismissHitl;
  final VoidCallback? onClearHitl;

  const RecentActivitiesCard({
    super.key,
    required this.activities,
    this.onViewAll,
    this.canUseHitl = false,
    this.isHitlActive = false,
    this.onToggleHitl,
    this.hitlItems,
    this.onUpdateHitlLabel,
    this.onConfirmHitl,
    this.onDismissHitl,
    this.onClearHitl,
  });

  @override
  State<RecentActivitiesCard> createState() => _RecentActivitiesCardState();
}

class _RecentActivitiesCardState extends State<RecentActivitiesCard> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    final hitlList = widget.hitlItems ?? const [];

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Row: Title & View All
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
                if (widget.onViewAll != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: widget.onViewAll,
                    icon: const Icon(Icons.chevron_right, size: 18),
                    label: Text(l10n.viewAll),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // HITL Mode Toggle (Visible only for Clinician / Admin)
            if (widget.canUseHitl) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: widget.isHitlActive
                      ? theme.colorScheme.primaryContainer.withValues(alpha: 0.45)
                      : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: widget.isHitlActive
                        ? theme.colorScheme.primary.withValues(alpha: 0.4)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            Icons.verified_user_rounded,
                            size: 16,
                            color: widget.isHitlActive
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Mode HITL (Labellisation)',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: widget.isHitlActive
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 28,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Switch(
                          value: widget.isHitlActive,
                          onChanged: widget.onToggleHitl,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Content: HITL Mode vs Nominal Activities
            if (widget.isHitlActive) ...[
              if (hitlList.isEmpty)
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
                          Icons.touch_app_rounded,
                          size: 32,
                          color: theme.colorScheme.primary.withValues(alpha: 0.6),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Mode HITL actif (File de 15 max)',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Chaque transition capturera 4s (76 trames IMU) prêtes pour validation.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                // Clear all bar
                Padding(
                  padding: const EdgeInsets.only(bottom: 6.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'En attente de validation (${hitlList.length})',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                      if (widget.onClearHitl != null)
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            visualDensity: VisualDensity.compact,
                            foregroundColor: theme.colorScheme.error,
                          ),
                          onPressed: widget.onClearHitl,
                          icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                          label: const Text('Tout effacer', style: TextStyle(fontSize: 11)),
                        ),
                    ],
                  ),
                ),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: hitlList.length,
                  itemBuilder: (context, index) {
                    final item = hitlList[index];
                    final isSelected = _selectedId == item.id;
                    return UnifiedActivityCard(
                      hitlItem: item,
                      isSelected: isSelected,
                      onTap: () {
                        setState(() {
                          _selectedId = item.id;
                        });
                      },
                      onUpdateHitlLabel: widget.onUpdateHitlLabel,
                      onConfirmHitl: widget.onConfirmHitl,
                      onDismissHitl: widget.onDismissHitl,
                    );
                  },
                ),
              ],
            ] else if (widget.activities.isEmpty)
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
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: widget.activities.length.clamp(0, 5),
                itemBuilder: (context, index) {
                  final item = widget.activities[index];
                  final id = '${item.eventType}_${item.effectiveTimestamp.millisecondsSinceEpoch}_$index';
                  final isSelected = _selectedId == id;
                  return UnifiedActivityCard(
                    activity: item,
                    isSelected: isSelected,
                    onTap: () {
                      setState(() {
                        _selectedId = id;
                      });
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
