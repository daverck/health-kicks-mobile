import 'package:flutter/material.dart';

import '../../../models/detection_event.dart';
import 'unified_activity_card.dart';

/// Adapter widget presenting an individual biomechanical detection event
/// using the shared [UnifiedActivityCard].
class DetectionEventCard extends StatelessWidget {
  final DetectionEvent event;
  final bool isSelected;
  final VoidCallback? onTap;

  const DetectionEventCard({
    super.key,
    required this.event,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return UnifiedActivityCard(
      event: event,
      isSelected: isSelected,
      onTap: onTap,
    );
  }
}
