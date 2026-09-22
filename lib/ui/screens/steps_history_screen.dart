import 'package:flutter/material.dart';
import '../../services/local_storage/step_storage_service.dart';
import '../../services/step_sync_service.dart';

/// Screen displaying step history breakdown and summary stats over 7 or 30 days.
class StepsHistoryScreen extends StatefulWidget {
  final StepStorageService storageService;
  final StepSyncService? syncService;
  final String deviceId;

  const StepsHistoryScreen({
    super.key,
    required this.storageService,
    this.syncService,
    this.deviceId = 'HK-2',
  });

  @override
  State<StepsHistoryScreen> createState() => _StepsHistoryScreenState();
}

class _StepsHistoryScreenState extends State<StepsHistoryScreen> {
  int _selectedPeriodDays = 7;
  bool _isLoading = true;
  List<DailyStepRecord> _history = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final history = await widget.storageService.getHistory(_selectedPeriodDays);
    if (mounted) {
      setState(() {
        _history = history;
        _isLoading = false;
      });
    }
  }

  Future<void> _triggerSync() async {
    if (widget.syncService == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Synchronisation des pas avec le serveur...'),
        duration: Duration(seconds: 1),
      ),
    );

    final success = await widget.syncService!.syncPendingSteps(deviceId: widget.deviceId);
    await _loadData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'Synchronisation réussie !' : 'Synchronisation partielle ou reportée.',
          ),
          backgroundColor: success ? const Color(0xFF0F766E) : Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final totalAccumulated = _history.fold<int>(0, (sum, item) => sum + item.totalSteps);
    final averageSteps = _history.isNotEmpty ? (totalAccumulated / _history.length).round() : 0;
    final bestDay = _history.isNotEmpty
        ? _history.map((e) => e.totalSteps).reduce((a, b) => a > b ? a : b)
        : 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historique des Pas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            tooltip: 'Synchroniser maintenant',
            onPressed: widget.syncService != null ? _triggerSync : null,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (widget.syncService != null) {
            await widget.syncService!.syncPendingSteps(deviceId: widget.deviceId);
          }
          await _loadData();
        },
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF0F766E)))
            : ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  // 1. Period Selector (7 or 30 days)
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 7, label: Text('7 derniers jours')),
                      ButtonSegment(value: 30, label: Text('30 derniers jours')),
                    ],
                    selected: {_selectedPeriodDays},
                    onSelectionChanged: (set) {
                      setState(() {
                        _selectedPeriodDays = set.first;
                      });
                      _loadData();
                    },
                  ),
                  const SizedBox(height: 16),

                  // 2. Summary Statistics Cards
                  Row(
                    children: [
                      Expanded(
                        child: _buildSummaryCard(
                          context,
                          title: 'Moyenne / jour',
                          value: '$averageSteps',
                          icon: Icons.auto_graph_rounded,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildSummaryCard(
                          context,
                          title: 'Meilleur jour',
                          value: '$bestDay',
                          icon: Icons.emoji_events_rounded,
                          color: Colors.amber,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildSummaryCard(
                          context,
                          title: 'Total cumulé',
                          value: '$totalAccumulated',
                          icon: Icons.directions_walk_rounded,
                          color: const Color(0xFF0F766E),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // 3. Activity Breakdown Legend
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      _buildLegendItem('Marche', Colors.blue),
                      _buildLegendItem('Course', Colors.orange),
                      _buildLegendItem('Escaliers', Colors.teal),
                      _buildLegendItem('Autre', Colors.blueGrey),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 4. Daily Stacked Activity Cards
                  Text(
                    'Détail par jour',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ..._history.map((record) => _buildDayCard(context, record)),
                ],
              ),
      ),
    );
  }

  Widget _buildSummaryCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildDayCard(BuildContext context, DailyStepRecord record) {
    final theme = Theme.of(context);
    final total = record.totalSteps;

    final walkRatio = total > 0 ? (record.walkSteps / total) : 0.0;
    final runRatio = total > 0 ? (record.runSteps / total) : 0.0;
    final stairsRatio = total > 0 ? (record.stairsSteps / total) : 0.0;
    final unclassRatio = total > 0 ? (record.unclassifiedSteps / total) : 0.0;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      record.date,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      record.isSynced ? Icons.cloud_done_rounded : Icons.cloud_upload_outlined,
                      size: 16,
                      color: record.isSynced ? Colors.teal : Colors.orange,
                    ),
                  ],
                ),
                Text(
                  '$total pas',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Stacked progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 10,
                child: total == 0
                    ? Container(color: Colors.grey.withValues(alpha: 0.2))
                    : Row(
                        children: [
                          if (walkRatio > 0)
                            Expanded(flex: (walkRatio * 1000).round(), child: Container(color: Colors.blue)),
                          if (runRatio > 0)
                            Expanded(flex: (runRatio * 1000).round(), child: Container(color: Colors.orange)),
                          if (stairsRatio > 0)
                            Expanded(flex: (stairsRatio * 1000).round(), child: Container(color: Colors.teal)),
                          if (unclassRatio > 0)
                            Expanded(flex: (unclassRatio * 1000).round(), child: Container(color: Colors.blueGrey)),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 8),

            // Step counts details
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Marche: ${record.walkSteps}', style: const TextStyle(fontSize: 11, color: Colors.blue)),
                Text('Course: ${record.runSteps}', style: const TextStyle(fontSize: 11, color: Colors.orange)),
                Text('Escaliers: ${record.stairsSteps}', style: const TextStyle(fontSize: 11, color: Colors.teal)),
                Text('Autre: ${record.unclassifiedSteps}', style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

