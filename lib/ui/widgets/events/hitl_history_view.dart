import 'package:material_ui/material_ui.dart';
import '../../../models/hitl/hitl_detection_item.dart';
import '../../../services/hitl/hitl_coordinator.dart';
import 'unified_activity_card.dart';

/// Helper matching a HITL detection item against a category filter.
bool matchesHitlCategory(HitlDetectionItem item, String category) {
  if (category == 'all') return true;
  final eventType = item.detectedLabel.toLowerCase();
  if (category == 'falls') {
    return item.isFall || (eventType.contains('fall') && eventType != 'fall_recovery');
  }
  if (category == 'impacts') {
    return eventType.contains('impact') ||
        eventType == 'free_fall' ||
        eventType == 'stumble_recover';
  }
  if (category == 'activity') {
    return !item.isFall && !(eventType.contains('fall') && eventType != 'fall_recovery');
  }
  return true;
}

/// Compact HITL mode switch & clear-all header banner.
class HitlHistoryHeader extends StatelessWidget {
  final HitlCoordinator coordinator;
  final ValueChanged<bool>? onToggleHitl;
  final VoidCallback? onCleared;

  const HitlHistoryHeader({
    super.key,
    required this.coordinator,
    this.onToggleHitl,
    this.onCleared,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = coordinator.isHitlActive;
    final items = coordinator.items;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isActive
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? theme.colorScheme.primary.withValues(alpha: 0.35) : Colors.transparent,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.verified_user_rounded,
                      size: 18,
                      color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Mode HITL (Labellisation)',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (isActive && items.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${items.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 28,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Switch(
                    value: isActive,
                    onChanged: (val) {
                      onToggleHitl?.call(val);
                    },
                  ),
                ),
              ),
            ],
          ),
          if (isActive && items.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${items.length} détection${items.length > 1 ? "s" : ""} en attente',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    visualDensity: VisualDensity.compact,
                    foregroundColor: theme.colorScheme.error,
                  ),
                  onPressed: () {
                    coordinator.clear();
                    onCleared?.call();
                  },
                  icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                  label: const Text('Tout effacer', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Body view displaying the queue of HITL detections or dedicated empty states.
class HitlHistoryView extends StatelessWidget {
  final HitlCoordinator coordinator;
  final String selectedCategory;
  final String? selectedEventId;
  final ValueChanged<String>? onSelectEvent;
  final void Function(HitlDetectionItem item)? onConfirmHitl;

  const HitlHistoryView({
    super.key,
    required this.coordinator,
    required this.selectedCategory,
    this.selectedEventId,
    this.onSelectEvent,
    this.onConfirmHitl,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allItems = coordinator.items;

    // Filter HITL items according to selected category
    final items = allItems.where((item) => matchesHitlCategory(item, selectedCategory)).toList();

    if (allItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.touch_app_rounded,
                  size: 44,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Mode HITL actif (File vide)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Chaque nouvelle transition détectée par l\'ESP32 capturera 4s (76 trames IMU) pour validation ou requalification.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.filter_list_off_rounded,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 12),
              Text(
                'Aucune détection HITL pour ce filtre',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                '${allItems.length} détection${allItems.length > 1 ? "s" : ""} présente${allItems.length > 1 ? "s" : ""} dans d\'autres catégories.',
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      itemCount: items.length,
      findChildIndexCallback: (Key key) {
        if (key is ValueKey<String>) {
          final index = items.indexWhere((it) => it.id == key.value);
          return index >= 0 ? index : null;
        }
        return null;
      },
      itemBuilder: (context, index) {
        final item = items[index];
        final isSelected = selectedEventId == item.id;
        return UnifiedActivityCard(
          key: ValueKey(item.id),
          hitlItem: item,
          isSelected: isSelected,
          onTap: () {
            onSelectEvent?.call(item.id);
          },
          onUpdateHitlLabel: (it, label) => coordinator.updateItemLabel(it.id, label),
          onConfirmHitl: (it) => onConfirmHitl?.call(it),
          onDismissHitl: (it) => coordinator.dismissItem(it.id),
        );
      },
    );
  }
}
