import 'package:flutter/material.dart';

import '../../models/activity_detection_model.dart';
import '../../models/detection_event.dart';
import '../../services/event_history_notifier.dart';
import '../../services/event_history_service.dart';
import '../widgets/events/detection_event_card.dart';
import '../widgets/events/detection_event_detail_sheet.dart';
import '../widgets/events/detection_event_skeleton.dart';
import '../widgets/events/detection_filter_bar.dart';

export '../widgets/events/detection_event_card.dart';
export '../widgets/events/detection_event_detail_sheet.dart';
export '../widgets/events/detection_event_skeleton.dart';
export '../widgets/events/detection_filter_bar.dart';

/// Screen displaying the historical list of detected biomechanical events and alerts
/// with pagination, fast FilterChips, Pull-to-Refresh, and detailed bottom sheet inspection.
class DetectionEventsHistoryScreen extends StatefulWidget {
  final EventHistoryNotifier? notifier;
  final EventHistoryService? service;
  final String? deviceId;
  final List<ActivityDetectionModel>? liveActivities;
  final Stream<ActivityDetectionModel>? activityStream;

  const DetectionEventsHistoryScreen({
    super.key,
    this.notifier,
    this.service,
    this.deviceId,
    this.liveActivities,
    this.activityStream,
  });

  @override
  State<DetectionEventsHistoryScreen> createState() => _DetectionEventsHistoryScreenState();
}

class _DetectionEventsHistoryScreenState extends State<DetectionEventsHistoryScreen> {
  late final EventHistoryNotifier _notifier;
  final ScrollController _scrollController = ScrollController();

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique des Événements'),
      ),
      body: ListenableBuilder(
        listenable: _notifier,
        builder: (context, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Horizontal Category Filter Chips Bar
              DetectionFilterBar(
                filters: _filters,
                selectedCategory: _notifier.selectedCategory,
                onSelected: (cat) => _notifier.setCategory(cat),
              ),

              // 2. Main Content Area (Shimmer, Empty, Error or List)
              Expanded(
                child: _buildBodyContent(theme),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBodyContent(ThemeData theme) {
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
          return DetectionEventCard(
            event: event,
            onTap: () => _showEventDetails(context, event),
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
                    Icons.event_available_rounded,
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
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Actualiser'),
                  onPressed: () => _notifier.refresh(),
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
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Erreur de chargement',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _notifier.errorMessage ?? 'Une erreur réseau est survenue.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Réessayer'),
                    onPressed: () => _notifier.loadInitial(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
