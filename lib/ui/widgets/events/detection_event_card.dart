import 'package:flutter/material.dart';

import '../../../models/detection_event.dart';

/// Custom Card widget presenting an individual biomechanical detection event.
class DetectionEventCard extends StatelessWidget {
  final DetectionEvent event;
  final VoidCallback? onTap;

  const DetectionEventCard({
    super.key,
    required this.event,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: event.severity == EventSeverity.critical
              ? event.color.withValues(alpha: 0.5)
              : theme.dividerColor.withValues(alpha: 0.15),
          width: event.severity == EventSeverity.critical ? 1.5 : 1.0,
        ),
      ),
      color: event.severity == EventSeverity.critical
          ? event.color.withValues(alpha: 0.04)
          : theme.cardColor,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              // Severity Indicator Icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: event.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  event.icon,
                  color: event.color,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),

              // Title and Relative Timestamp
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            event.localizedTitle(context),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (event.isValidated) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified_rounded, size: 14, color: Colors.blue),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      event.relativeTime,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),

              // Trailing Metrics (Peak Impact or Confidence)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (event.peakImpactG != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: event.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${event.peakImpactG!.toStringAsFixed(1)} g',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: event.color,
                        ),
                      ),
                    )
                  else if (event.confidence != null)
                    Text(
                      '${(event.confidence! * 100).toInt()}% conf.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: Colors.grey.shade400,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

