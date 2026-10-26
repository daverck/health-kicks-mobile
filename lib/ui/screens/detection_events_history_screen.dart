import 'package:flutter/material.dart';

import '../../models/activity_detection_model.dart';
import '../../models/detection_event.dart';
import '../../models/hitl/hitl_detection_item.dart';
import '../../services/event_history_notifier.dart';
import '../../services/event_history_service.dart';
import '../../services/hitl/hitl_coordinator.dart';
import '../widgets/events/detection_event_detail_sheet.dart';
import '../widgets/events/detection_event_skeleton.dart';
import '../widgets/events/detection_filter_bar.dart';
import '../widgets/events/unified_activity_card.dart';

export '../widgets/events/detection_event_card.dart';
export '../widgets/events/detection_event_detail_sheet.dart';
export '../widgets/events/detection_event_skeleton.dart';
export '../widgets/events/detection_filter_bar.dart';
export '../widgets/events/unified_activity_card.dart';

/// Screen displaying the historical list of detected biomechanical events and alerts
/// with pagination, fast FilterChips, Pull-to-Refresh, bottom sheet inspection,
/// and integrated Human-in-the-Loop (HITL) mode switching.
class DetectionEventsHistoryScreen extends StatefulWidget {
  final EventHistoryNotifier? notifier;
  final EventHistoryService? service;
  final String? deviceId;
  final List<ActivityDetectionModel>? liveActivities;
  final Stream<ActivityDetectionModel>? activityStream;

  // Optional HITL coordination
  final HitlCoordinator? hitlCoordinator;
  final bool canUseHitl;
  final ValueChanged<bool>? onToggleHitl;
  final void Function(HitlDetectionItem item)? onConfirmHitl;

  const DetectionEventsHistoryScreen({
    super.key,
    this.notifier,
    this.service,
    this.deviceId,
    this.liveActivities,
    this.activityStream,
    this.hitlCoordinator,
    this.canUseHitl = false,
    this.onToggleHitl,
    this.onConfirmHitl,
  });

  @override
  State<DetectionEventsHistoryScreen> createState() => _DetectionEventsHistoryScreenState();
}

class _DetectionEventsHistoryScreenState extends State<DetectionEventsHistoryScreen> {
  late final EventHistoryNotifier _notifier;
  final ScrollController _scrollController = ScrollController();
  String? _selectedEventId;

  final List<CategoryFilterOption> _filters = const [
    CategoryFilterOption(id: 'all', label: 'Tous', icon: Icons.select_all_rounded),
    CategoryFilterOption(id: 'falls', label: 'Chutes / Urgences', icon: Icons.warning_amber_rounded),
    CategoryFilterOption(id: 'impacts', label: 'Impacts', icon: Icons.bolt_rounded),
    CategoryFilterOption(id: 'activity', label: 'Activité', icon: Icons.directions_walk_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _notifier = widget.notifier ??
        EventHistoryNotifier(
          service: widget.service ?? EventHistoryService(),
          deviceId: widget.deviceId,
          liveActivities: widget.liveActivities,
          activityStream: widget.activityStream,
        );

    _scrollController.addListener(_onScroll);

    // Initial fetch from cloud
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifier.loadInitial();
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    // Trigger next page when reaching 85% of list height
    if (currentScroll >= (maxScroll * 0.85)) {
      _notifier.loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    if (widget.notifier == null) {
      _notifier.dispose();
    }
    super.dispose();
  }

  void _showEventDetails(BuildContext context, DetectionEvent event) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DetectionEventDetailSheet(event: event),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listenables = <Listenable>[_notifier];
    if (widget.hitlCoordinator != null) {
      listenables.add(widget.hitlCoordinator!);
    }

    final isHitlActive = widget.canUseHitl && (widget.hitlCoordinator?.isHitlActive ?? false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique des Événements'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge(listenables),
        builder: (context, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 0. Compact HITL Switch & Clear-all Header
              if (widget.canUseHitl && widget.hitlCoordinator != null) ...[
                _buildHitlHeader(theme),
              ],

              // 1. Horizontal Category Filter Chips Bar (only when HITL is inactive)
              if (!isHitlActive)
                DetectionFilterBar(
                  filters: _filters,
                  selectedCategory: _notifier.selectedCategory,
                  onSelected: (cat) => _notifier.setCategory(cat),
                ),

              // 2. Main Content Area (switches between HITL queue and Historical stream)
              Expanded(
                child: isHitlActive ? _buildHitlBody(theme) : _buildHistoricalBody(theme),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHitlHeader(ThemeData theme) {
    final coord = widget.hitlCoordinator!;
    final isActive = coord.isHitlActive;
    final items = coord.items;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isActive
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? theme.colorScheme.primary.withValues(alpha: 0.35) : Colors.transparent,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                Icons.verified_user_rounded,
                size: 18,
                color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                'Mode HITL (Labellisation)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
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
          Row(
            children: [
              if (isActive && items.isNotEmpty) ...[
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    visualDensity: VisualDensity.compact,
                    foregroundColor: theme.colorScheme.error,
                  ),
                  onPressed: () => coord.clear(),
                  icon: const Icon(Icons.delete_sweep_rounded, size: 16),
                  label: const Text('Tout effacer', style: TextStyle(fontSize: 11)),
                ),
                const SizedBox(width: 4),
              ],
              Transform.scale(
                scale: 0.75,
                child: Switch(
                  value: isActive,
                  onChanged: widget.onToggleHitl,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHitlBody(ThemeData theme) {
    final coord = widget.hitlCoordinator!;
    final items = coord.items;

    if (items.isEmpty) {
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

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isSelected = _selectedEventId == item.id;
        return UnifiedActivityCard(
          hitlItem: item,
          isSelected: isSelected,
          onTap: () {
            setState(() {
              _selectedEventId = item.id;
            });
          },
          onUpdateHitlLabel: (it, label) => coord.updateItemLabel(it.id, label),
          onConfirmHitl: (it) => widget.onConfirmHitl?.call(it),
          onDismissHitl: (it) => coord.dismissItem(it.id),
        );
      },
    );
  }

  Widget _buildHistoricalBody(ThemeData theme) {
    if (_notifier.isLoading && _notifier.events.isEmpty) {
      return _buildSkeletonLoader();
    }

    if (_notifier.errorMessage != null && _notifier.events.isEmpty) {
      return _buildErrorState(theme);
    }

    if (_notifier.isEmpty) {
      return _buildEmptyState(theme);
    }

    return RefreshIndicator(
      onRefresh: () => _notifier.refresh(),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        itemCount: _notifier.events.length + (_notifier.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _notifier.events.length) {
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }

          final event = _notifier.events[index];
          final isSelected = _selectedEventId == event.id;

          return UnifiedActivityCard(
            event: event,
            isSelected: isSelected,
            onTap: () {
              setState(() {
                _selectedEventId = event.id;
              });
              _showEventDetails(context, event);
            },
          );
        },
      ),
    );
  }

  Widget _buildSkeletonLoader() {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12.0),
      itemCount: 6,
      itemBuilder: (context, index) => const DetectionEventSkeletonCard(),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return RefreshIndicator(
      onRefresh: () => _notifier.refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.18),
          Center(
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
                    Icons.event_busy_rounded,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Aucun événement détecté',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Text(
                    'Les alertes et événements biomécaniques enregistrés pour cette catégorie s\'afficheront ici.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return RefreshIndicator(
      onRefresh: () => _notifier.refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.18),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 48,
                  color: Colors.redAccent,
                ),
                const SizedBox(height: 16),
                Text(
                  'Erreur de chargement',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: Text(
                    _notifier.errorMessage ?? 'Une erreur réseau est survenue.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _notifier.loadInitial(),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}