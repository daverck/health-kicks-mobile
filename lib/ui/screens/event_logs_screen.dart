import 'package:material_ui/material_ui.dart';
import '../../models/log_entry_model.dart';
import '../../services/log_export_service.dart';
import '../widgets/log_export_dialog.dart';

/// Dedicated full-screen console for monitoring and filtering real-time mobile gateway logs.
class EventLogsScreen extends StatefulWidget {
  final List<LogEntry> logs;
  final VoidCallback onClearLogs;
  final Future<void> Function()? onExportLogs;
  final Listenable? logsNotifier;
  final String deviceId;
  final String? deviceName;
  final String? bleStatus;
  final int? mtu;
  final bool? mqttConnected;

  const EventLogsScreen({
    super.key,
    required this.logs,
    required this.onClearLogs,
    this.onExportLogs,
    this.logsNotifier,
    this.deviceId = 'HK-2',
    this.deviceName,
    this.bleStatus,
    this.mtu,
    this.mqttConnected,
  });

  @override
  State<EventLogsScreen> createState() => _EventLogsScreenState();
}

class _EventLogsScreenState extends State<EventLogsScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _selectedTag = 'ALL';
  String _searchQuery = '';

  final List<String> _filterTags = const [
    'ALL',
    'BLE',
    'MQTT',
    'ACTIVITY',
    'STUDIO',
    'GATEWAY',
    'SYNC',
    'PERM',
    'HAPTIC',
    'ERROR',
  ];

  @override
  void initState() {
    super.initState();
    widget.logsNotifier?.addListener(_onLogsUpdated);
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  @override
  void didUpdateWidget(covariant EventLogsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.logsNotifier != widget.logsNotifier) {
      oldWidget.logsNotifier?.removeListener(_onLogsUpdated);
      widget.logsNotifier?.addListener(_onLogsUpdated);
    }
  }

  void _onLogsUpdated() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    widget.logsNotifier?.removeListener(_onLogsUpdated);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  List<LogEntry> get _filteredLogs {
    return widget.logs.where((entry) {
      final matchesTag = _selectedTag == 'ALL' || entry.tag.toUpperCase() == _selectedTag;
      final matchesQuery = _searchQuery.isEmpty ||
          entry.message.toLowerCase().contains(_searchQuery) ||
          entry.tag.toLowerCase().contains(_searchQuery);
      return matchesTag && matchesQuery;
    }).toList();
  }

  void _openEmailExportDialog() {
    if (widget.logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Le journal d\'événements est vide.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => LogExportDialog(
        logs: widget.logs,
        deviceId: widget.deviceId,
        deviceName: widget.deviceName,
        bleStatus: widget.bleStatus,
        mtu: widget.mtu,
        mqttConnected: widget.mqttConnected,
      ),
    );
  }

  void _confirmClearLogs() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Effacer les logs'),
        content: const Text('Voulez-vous vraiment effacer tous les événements du journal local ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.onClearLogs();
              setState(() {});
            },
            child: const Text('Effacer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final filtered = _filteredLogs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Journal d\'événements'),
        actions: [
          IconButton(
            icon: const Icon(Icons.email_outlined),
            tooltip: 'Exporter par email',
            onPressed: widget.onExportLogs ?? _openEmailExportDialog,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Effacer le journal',
            onPressed: _confirmClearLogs,
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Search Bar & Filter Chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Rechercher dans les logs...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              itemCount: _filterTags.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final tag = _filterTags[index];
                final isSelected = _selectedTag == tag;
                return FilterChip(
                  label: Text(tag, style: const TextStyle(fontSize: 12)),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      _selectedTag = tag;
                    });
                  },
                  showCheckmark: false,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // 2. Terminal Log View
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF18181B) : const Color(0xFFF4F4F5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.2),
                ),
              ),
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.article_outlined,
                            size: 44,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.logs.isEmpty
                                ? 'Aucun événement enregistré.'
                                : 'Aucun log ne correspond au filtre.',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(8.0),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final entry = filtered[index];
                        return InkWell(
                          onLongPress: () async {
                            await LogExportService.copyToClipboard(entry.toFormattedLine());
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Ligne de log copiée !'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.5),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.formattedTimestamp,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: entry.color.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    entry.tag,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: entry.color,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    entry.message,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),

          // 3. Bottom Status Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total : ${filtered.length} / ${widget.logs.length} événements',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.arrow_downward, size: 16),
                  label: const Text('En bas', style: TextStyle(fontSize: 12)),
                  onPressed: _scrollToBottom,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

