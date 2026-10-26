import 'package:flutter/material.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../models/activity_detection_model.dart';
import '../../../models/detection_event.dart';
import '../../../models/hitl/hitl_detection_item.dart';
import 'activity_visual_meta.dart';

/// Unified activity card widget used identically in:
/// - Dashboard nominal activities stream
/// - Dashboard HITL validation stream (with extra action row)
/// - Historical Detection Events screen
class UnifiedActivityCard extends StatelessWidget {
  final ActivityDetectionModel? activity;
  final HitlDetectionItem? hitlItem;
  final DetectionEvent? event;

  final bool isSelected;
  final VoidCallback? onTap;

  // HITL actions (only used when hitlItem is provided)
  final void Function(HitlDetectionItem item, String newLabel)? onUpdateHitlLabel;
  final void Function(HitlDetectionItem item)? onConfirmHitl;
  final void Function(HitlDetectionItem item)? onDismissHitl;

  static const List<String> hitlAvailableLabels = [
    'idle',
    'walk',
    'run',
    'sit_down',
    'stand_up',
    'stairs_up',
    'stairs_down',
    'fall_forward',
    'fall_backward',
    'fall_lateral',
    'fall_recovery',
    'stumble_recover',
  ];

  const UnifiedActivityCard({
    super.key,
    this.activity,
    this.hitlItem,
    this.event,
    this.isSelected = false,
    this.onTap,
    this.onUpdateHitlLabel,
    this.onConfirmHitl,
    this.onDismissHitl,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    // Resolve event type, timestamp, fall flag, and confidence
    final String rawEventType = hitlItem?.detectedLabel ??
        activity?.eventType ??
        event?.eventType ??
        'unknown';

    final bool isFall = hitlItem?.isFall ??
        activity?.isFall ??
        (event?.severity == EventSeverity.critical || rawEventType.contains('fall'));

    final bool isHapticTriggered = activity?.isHapticTriggered ?? false;

    final DateTime timestamp = hitlItem?.timestamp ??
        activity?.effectiveTimestamp ??
        event?.timestamp ??
        DateTime.now();

    final int confidencePercent = hitlItem?.confidencePercent ??
        activity?.confidencePercent ??
        (event?.confidence != null ? (event!.confidence! * 100).round() : 0);

    final double? peakImpactG = event?.peakImpactG;
    final bool isValidated = event?.isValidated ?? false;

    final meta = ActivityVisualMeta.fromEventType(
      context,
      rawEventType,
      isFall: isFall,
    );

    final confColor = ActivityVisualMeta.confidenceColor(confidencePercent);
    final confIcon = ActivityVisualMeta.confidenceIcon(confidencePercent);

    // Title label resolution
    final String titleText;
    if (hitlItem != null) {
      titleText = 'Détecté : ${hitlItem!.detectedLabel} (${hitlItem!.confidencePercent}%)';
    } else if (event != null) {
      titleText = event!.localizedTitle(context);
    } else {
      titleText = meta.label;
    }

    // Card styling: selected highlight (glow + primary tint) vs colored activity card
    final Color cardBg = isSelected
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.50)
        : meta.color.withValues(alpha: 0.05);

    final Color borderColor = isSelected
        ? theme.colorScheme.primary
        : meta.color.withValues(alpha: 0.28);

    final double borderWidth = isSelected ? 2.0 : 1.0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.30),
                  blurRadius: 10,
                  spreadRadius: 1,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left accent vertical color stripe (4px)
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: isSelected ? theme.colorScheme.primary : meta.color,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Main Card Content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 10.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header Row: Icon + Title/Time/Gauge + Trailing Metrics/Dismiss
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Circular Tinted Activity Icon
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: meta.color.withValues(alpha: 0.16),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(meta.icon, color: meta.color, size: 22),
                            ),
                            const SizedBox(width: 10),

                            // Title, Badges & Confidence Progress Bar Gauge
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          titleText,
                                          style: theme.textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: theme.colorScheme.onSurface,
                                            fontSize: 13,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isFall) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFDC2626),
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
                                      if (isHapticTriggered) ...[
                                        const SizedBox(width: 4),
                                        const Icon(Icons.vibration_rounded, size: 14, color: Colors.amber),
                                      ],
                                      if (hitlItem?.isSynchronized == true) ...[
                                        const SizedBox(width: 4),
                                        const Icon(Icons.cloud_done_rounded, size: 14, color: Colors.teal),
                                      ],
                                      if (isValidated) ...[
                                        const SizedBox(width: 4),
                                        const Icon(Icons.verified_rounded, size: 14, color: Colors.blue),
                                      ],
                                      if (event != null && !event!.id.startsWith('live_')) ...[
                                        const SizedBox(width: 4),
                                        const Icon(Icons.cloud_done_rounded, size: 14, color: Colors.teal),
                                      ],
                                      if (isSelected) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.primary,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'Actif',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),

                                  // Confidence Progress Bar Gauge under Title
                                  Row(
                                    children: [
                                      // Compact linear bar
                                      SizedBox(
                                        width: 76,
                                        height: 5,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(3),
                                          child: LinearProgressIndicator(
                                            value: (confidencePercent / 100.0).clamp(0.0, 1.0),
                                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                                            valueColor: AlwaysStoppedAnimation<Color>(confColor),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Icon(confIcon, size: 12, color: confColor),
                                      const SizedBox(width: 3),
                                      Text(
                                        '$confidencePercent% conf.',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: confColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Right Side: Timestamp / Impact / Dismiss
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _formatTime(timestamp),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    if (hitlItem != null && onDismissHitl != null) ...[
                                      const SizedBox(width: 6),
                                      InkWell(
                                        onTap: () => onDismissHitl!(hitlItem!),
                                        borderRadius: BorderRadius.circular(12),
                                        child: Padding(
                                          padding: const EdgeInsets.all(2.0),
                                          child: Icon(
                                            Icons.close,
                                            size: 16,
                                            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (peakImpactG != null) ...[
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: meta.color.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      '${peakImpactG.toStringAsFixed(1)} g',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: meta.color,
                                      ),
                                    ),
                                  ),
                                ] else if (event != null && onTap != null) ...[
                                  const SizedBox(height: 4),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    size: 16,
                                    color: Colors.grey.shade400,
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),

                        // Extra Row for HITL Mode (Reclassification & Send Controls)
                        if (hitlItem != null) ...[
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
                                child: hitlItem!.isSynchronized
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
                                              ActivityVisualMeta.fromEventType(context, hitlItem!.selectedLabel).icon,
                                              size: 14,
                                              color: ActivityVisualMeta.fromEventType(context, hitlItem!.selectedLabel).color,
                                            ),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                hitlItem!.selectedLabel,
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
                                    : Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.surface,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                                          ),
                                        ),
                                        child: DropdownButtonHideUnderline(
                                          child: DropdownButton<String>(
                                            isExpanded: true,
                                            iconSize: 18,
                                            value: hitlAvailableLabels.contains(hitlItem!.selectedLabel)
                                                ? hitlItem!.selectedLabel
                                                : hitlAvailableLabels.first,
                                            isDense: true,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: theme.colorScheme.onSurface,
                                            ),
                                            items: hitlAvailableLabels.map((l) {
                                              final optMeta = ActivityVisualMeta.fromEventType(context, l);
                                              return DropdownMenuItem(
                                                value: l,
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(optMeta.icon, size: 14, color: optMeta.color),
                                                    const SizedBox(width: 4),
                                                    Flexible(
                                                      child: Text(
                                                        l,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              );
                                            }).toList(),
                                            onTap: onTap,
                                            onChanged: (newVal) {
                                              onTap?.call();
                                              if (newVal != null) {
                                                onUpdateHitlLabel?.call(hitlItem!, newVal);
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 8),
                              if (hitlItem!.isPublishing)
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              else if (hitlItem!.isSynchronized)
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
                              else if (hitlItem!.isBurstReady)
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    visualDensity: VisualDensity.compact,
                                    backgroundColor: Colors.teal.shade700,
                                  ),
                                  onPressed: () {
                                    onTap?.call();
                                    onConfirmHitl?.call(hitlItem!);
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
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    final s = local.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
