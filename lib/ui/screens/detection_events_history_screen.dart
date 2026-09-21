import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/detection_event.dart';
import '../../services/event_history_notifier.dart';
import '../../services/event_history_service.dart';

/// Screen displaying the historical list of detected biomechanical events and alerts
/// with pagination, fast FilterChips, Pull-to-Refresh, and detailed bottom sheet inspection.
class DetectionEventsHistoryScreen extends StatefulWidget {
  final EventHistoryNotifier? notifier;
  final EventHistoryService? service;
  final String? deviceId;

  const DetectionEventsHistoryScreen({
    super.key,
    this.notifier,
    this.service,
    this.deviceId,
  });

  @override
  State<DetectionEventsHistoryScreen> createState() => _DetectionEventsHistoryScreenState();
}

class _DetectionEventsHistoryScreenState extends State<DetectionEventsHistoryScreen> {
  late final EventHistoryNotifier _notifier;
  final ScrollController _scrollController = ScrollController();

  final List<_CategoryFilterOption> _filters = const [
    _CategoryFilterOption(id: 'all', label: 'Tous', icon: Icons.select_all_rounded),
    _CategoryFilterOption(id: 'falls', label: 'Chutes / Urgences', icon: Icons.warning_amber_rounded),
    _CategoryFilterOption(id: 'impacts', label: 'Impacts', icon: Icons.bolt_rounded),
    _CategoryFilterOption(id: 'activity', label: 'Activité', icon: Icons.directions_walk_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _notifier = widget.notifier ??
        EventHistoryNotifier(
          service: widget.service ?? EventHistoryService(),
          deviceId: widget.deviceId,
        );

    _scrollController.addListener(_onScroll);

    // Initial fetch if notifier doesn't have data yet
    if (_notifier.events.isEmpty && !_notifier.isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _notifier.loadInitial();
      });
    }
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
      builder: (ctx) => _EventDetailBottomSheet(event: event),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique des Événements'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Actualiser',
            onPressed: () => _notifier.refresh(),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _notifier,
        builder: (context, _) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Horizontal Category Filter Chips Bar
              _buildFilterChipsBar(theme),

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

  Widget _buildFilterChipsBar(ThemeData theme) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.15),
          ),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = _filters[index];
          final isSelected = _notifier.selectedCategory == filter.id;

          return FilterChip(
            selected: isSelected,
            avatar: Icon(
              filter.icon,
              size: 16,
              color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.primary,
            ),
            label: Text(filter.label),
            labelStyle: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
            ),
            selectedColor: theme.colorScheme.primary,
            checkmarkColor: theme.colorScheme.onPrimary,
            onSelected: (selected) {
              if (selected) {
                _notifier.setCategory(filter.id);
              }
            },
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
      itemBuilder: (context, index) => const _SkeletonCard(),
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

class _CategoryFilterOption {
  final String id;
  final String label;
  final IconData icon;

  const _CategoryFilterOption({
    required this.id,
    required this.label,
    required this.icon,
  });
}

/// Custom Card widget presenting an event summary.
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
                            event.formattedTitle,
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

/// Modal Bottom Sheet displaying exhaustive event metrics.
class _EventDetailBottomSheet extends StatelessWidget {
  final DetectionEvent event;

  const _EventDetailBottomSheet({required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fullDateStr = DateFormat('dd/MM/yyyy HH:mm:ss').format(event.timestamp);

    return Padding(
      padding: EdgeInsets.only(
        left: 20.0,
        right: 20.0,
        top: 16.0,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24.0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header with Icon & Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: event.color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(event.icon, color: event.color, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.formattedTitle,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Dispositif : ${event.deviceId}',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: event.color,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  event.severity.name.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(),

          // Details Matrix
          _buildDetailRow(context, 'Horodatage précis', fullDateStr),
          _buildDetailRow(
            context,
            'Pic d\'impact',
            event.peakImpactG != null ? '${event.peakImpactG!.toStringAsFixed(2)} g' : 'Non mesuré',
            highlight: event.peakImpactG != null && event.peakImpactG! >= 2.0,
          ),
          _buildDetailRow(
            context,
            'Confiance ML',
            event.confidence != null ? '${(event.confidence! * 100).toStringAsFixed(1)} %' : 'N/A',
          ),
          _buildDetailRow(
            context,
            'Validation clinique',
            event.isValidated ? 'Confirmé / Validé' : 'En attente de qualification',
            highlightColor: event.isValidated ? Colors.green : null,
          ),
          if (event.id.isNotEmpty) _buildDetailRow(context, 'ID Événement', event.id),

          // Metadata block if present
          if (event.metadata != null && event.metadata!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'MÉTADONNÉES TECHNIQUES',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                event.metadata.toString(),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ],

          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    BuildContext context,
    String label,
    String value, {
    bool highlight = false,
    Color? highlightColor,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: highlightColor ?? (highlight ? Colors.red : null),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shimmer placeholder card for skeleton loading.
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.15)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 140,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 80,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 50,
              height: 20,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

