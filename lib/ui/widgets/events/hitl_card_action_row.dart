import 'package:flutter/material.dart';
import '../../../models/hitl/hitl_detection_item.dart';
import 'activity_visual_meta.dart';

/// Interactive Human-In-The-Loop (HITL) action and reclassification row.
///
/// Displays the active classification label (or an editable popup menu if not yet synchronized)
/// along with burst capture progress, synchronizing indicators, or "Valider & Envoyer" action button.
class HitlCardActionRow extends StatelessWidget {
  final HitlDetectionItem item;
  final List<String> availableLabels;
  final VoidCallback? onTap;
  final void Function(HitlDetectionItem item, String newLabel)? onUpdateLabel;
  final void Function(HitlDetectionItem item)? onConfirm;

  const HitlCardActionRow({
    super.key,
    required this.item,
    required this.availableLabels,
    this.onTap,
    this.onUpdateLabel,
    this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Divider(
          height: 1,
          thickness: 0.75,
          color: theme.dividerColor.withValues(alpha: 0.20),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(
              'Label :',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: item.isSynchronized
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            ActivityVisualMeta.fromEventType(context, item.selectedLabel).icon,
                            size: 14,
                            color: ActivityVisualMeta.fromEventType(context, item.selectedLabel).color,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              item.selectedLabel,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Builder(
                      builder: (context) {
                        final currentLabelMeta = ActivityVisualMeta.fromEventType(context, item.selectedLabel);
                        return PopupMenuButton<String>(
                          key: ValueKey('hitl_label_dropdown_${item.id}'),
                          initialValue: item.selectedLabel,
                          tooltip: 'Modifier l\'activité',
                          padding: EdgeInsets.zero,
                          color: theme.colorScheme.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                            ),
                          ),
                          onOpened: () => onTap?.call(),
                          onSelected: (String label) {
                            onTap?.call();
                            onUpdateLabel?.call(item, label);
                          },
                          itemBuilder: (BuildContext context) {
                            return availableLabels.map((String l) {
                              final optMeta = ActivityVisualMeta.fromEventType(context, l);
                              final isSelected = l == item.selectedLabel;
                              return PopupMenuItem<String>(
                                value: l,
                                height: 34,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(optMeta.icon, size: 14, color: optMeta.color),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        l,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                          color: theme.colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    if (isSelected)
                                      Icon(Icons.check_rounded, size: 14, color: theme.colorScheme.primary),
                                  ],
                                ),
                              );
                            }).toList();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(currentLabelMeta.icon, size: 14, color: currentLabelMeta.color),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    item.selectedLabel,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Icon(
                                  Icons.arrow_drop_down_rounded,
                                  size: 16,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(width: 8),
            if (item.isPublishing)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (item.isSynchronized)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.teal.withValues(alpha: 0.35),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_done_rounded, size: 14, color: Colors.teal),
                    SizedBox(width: 4),
                    Text(
                      'Synchronisé',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal,
                      ),
                    ),
                  ],
                ),
              )
            else if (item.isBurstReady)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: Colors.teal.shade700,
                ),
                onPressed: () {
                  onTap?.call();
                  onConfirm?.call(item);
                },
                icon: const Icon(Icons.send_rounded, size: 13),
                label: const Text('Valider & Envoyer', style: TextStyle(fontSize: 11)),
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Capture 4s...',
                    style: TextStyle(
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
