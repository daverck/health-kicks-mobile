import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/studio_activity_option.dart';
import '../../services/studio/studio_api_service.dart';
import 'common/activity_svg_icon.dart';
import 'studio/studio_recent_activity_tile.dart';

export '../../models/studio_activity_option.dart' show StudioActivityOption;
export '../../services/studio/studio_api_service.dart' show StudioDatasetStats;

/// Dialog allowing clinician/admin to configure activity type and duration for Studio recording sessions.
class StudioSessionDialog extends StatefulWidget {
  final Future<dynamic> Function({
    required String label,
    required double durationSec,
  }) onStartSession;
  final String? initialActivityKey;
  final String? initialCustomLabel;
  final SharedPreferences? preferences;
  final void Function({
    required String activityKey,
    required String customLabel,
  })? onActivitySaved;
  final Future<StudioDatasetStats?> Function()? onLoadStats;
  final StudioDatasetStats? initialStats;

  static const String prefLastActivityKey = 'hk_studio_last_activity';
  static const String prefLastCustomLabel = 'hk_studio_last_custom_label';
  static const String prefRecentActivityKeys = 'hk_studio_recent_activities';
  static const int maxRecentActivities = 8;

  /// Target recordings per class before hiding low-sample indicators (matches frontend studio.component.ts:172).
  static const int targetPerClass = 25;

  const StudioSessionDialog({
    super.key,
    required this.onStartSession,
    this.initialActivityKey,
    this.initialCustomLabel,
    this.preferences,
    this.onActivitySaved,
    this.onLoadStats,
    this.initialStats,
  });

  static const List<StudioActivityOption> defaultActivities =
      StudioActivityOption.defaultActivities;

  static const double fixedDurationSec = 5.0;

  @override
  State<StudioSessionDialog> createState() => _StudioSessionDialogState();
}

class _StudioSessionDialogState extends State<StudioSessionDialog> {
  late String _selectedActivityKey;
  late final TextEditingController _customLabelController;
  List<String> _recentActivityKeys = [];
  late StudioDatasetStats _datasetStats;
  bool _isStarting = false;
  String? _successMessage;

  bool _isOptionEdgeAi(StudioActivityOption option) {
    if (_datasetStats.edgeAiLabels.isNotEmpty) {
      return _datasetStats.edgeAiLabels.contains(option.key);
    }
    return option.isEdgeAi;
  }

  @override
  void initState() {
    super.initState();
    _selectedActivityKey = widget.initialActivityKey ?? 'walk';
    _customLabelController =
        TextEditingController(text: widget.initialCustomLabel ?? '');
    _datasetStats = widget.initialStats ?? const StudioDatasetStats.empty();

    _loadSavedPreferences();
    _loadStudioStats();
  }

  Future<void> _loadStudioStats() async {
    if (widget.onLoadStats == null) return;
    try {
      final stats = await widget.onLoadStats!();
      if (stats != null && mounted) {
        setState(() {
          _datasetStats = stats;
        });
      }
    } catch (_) {
      // Ignore stats fetch errors so recording UI stays functional
    }
  }

  Future<void> _loadSavedPreferences() async {
    try {
      final prefs = widget.preferences ?? await SharedPreferences.getInstance();
      final savedKey = prefs.getString(StudioSessionDialog.prefLastActivityKey);
      final savedCustom =
          prefs.getString(StudioSessionDialog.prefLastCustomLabel);
      final savedRecents =
          prefs.getStringList(StudioSessionDialog.prefRecentActivityKeys) ?? [];
      if (mounted) {
        setState(() {
          _recentActivityKeys = savedRecents
              .where((key) => StudioSessionDialog.defaultActivities
                  .any((a) => a.key == key))
              .toSet()
              .take(StudioSessionDialog.maxRecentActivities)
              .toList();
          if (widget.initialActivityKey == null &&
              savedKey != null &&
              StudioSessionDialog.defaultActivities
                  .any((a) => a.key == savedKey)) {
            _selectedActivityKey = savedKey;
          }
          if (savedCustom != null && savedCustom.isNotEmpty) {
            _customLabelController.text = savedCustom;
          }
        });
      }
    } catch (_) {
      // Ignore preference read errors
    }
  }

  Future<void> _savePreferences(String key, String customLabel) async {
    final updatedRecents = [
      key,
      ..._recentActivityKeys.where((recentKey) => recentKey != key),
    ]
        .where((recentKey) => StudioSessionDialog.defaultActivities
            .any((a) => a.key == recentKey))
        .take(StudioSessionDialog.maxRecentActivities)
        .toList();

    if (mounted) {
      setState(() {
        _recentActivityKeys = updatedRecents;
      });
    }

    try {
      final prefs = widget.preferences ?? await SharedPreferences.getInstance();
      await prefs.setString(StudioSessionDialog.prefLastActivityKey, key);
      if (key == 'custom') {
        await prefs.setString(
            StudioSessionDialog.prefLastCustomLabel, customLabel);
      }
      final previous =
          prefs.getStringList(StudioSessionDialog.prefRecentActivityKeys) ??
              updatedRecents;
      final recentKeys = [
        key,
        ...previous.where((recentKey) => recentKey != key),
      ]
          .where((recentKey) => StudioSessionDialog.defaultActivities
              .any((a) => a.key == recentKey))
          .take(StudioSessionDialog.maxRecentActivities)
          .toList();
      await prefs.setStringList(
        StudioSessionDialog.prefRecentActivityKeys,
        recentKeys,
      );
      if (mounted) {
        setState(() {
          _recentActivityKeys = recentKeys;
        });
      }
    } catch (_) {
      // Ignore preference write errors
    }
  }

  @override
  void dispose() {
    _customLabelController.dispose();
    super.dispose();
  }

  Future<void> _onConfirm() async {
    if (_isStarting) return;
    setState(() {
      _isStarting = true;
      _successMessage = null;
    });

    String label = _selectedActivityKey;
    final customText = _customLabelController.text.trim();
    if (_selectedActivityKey == 'custom') {
      label = customText.isNotEmpty ? customText : 'custom';
    }

    await _savePreferences(_selectedActivityKey, customText);
    if (!mounted) return;
    widget.onActivitySaved?.call(
      activityKey: _selectedActivityKey,
      customLabel: customText,
    );

    try {
      final result = await widget.onStartSession(
        label: label,
        durationSec: StudioSessionDialog.fixedDurationSec,
      );
      if (result != false && mounted) {
        setState(() {
          _successMessage = 'Capture réalisée avec succès';
          _datasetStats = _datasetStats.incrementPendingForLabel(
            label,
            durationSec: StudioSessionDialog.fixedDurationSec,
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isStarting = false;
        });
      }
    }
  }

  Widget _buildActivityCategoryBadge(bool isEdgeAi) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isEdgeAi ? const Color(0xFFE8F5E9) : const Color(0xFFF3E5F5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isEdgeAi ? const Color(0xFFA5D6A7) : const Color(0xFFCE93D8),
          width: 0.8,
        ),
      ),
      child: Text(
        isEdgeAi ? '⚡ Edge AI' : '🧪 R&D',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isEdgeAi ? const Color(0xFF1B5E20) : const Color(0xFF4A148C),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 22),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Enregistrement Studio',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Type d\'activité',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey(_selectedActivityKey),
              initialValue: _selectedActivityKey,
              isExpanded: true,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: StudioSessionDialog.defaultActivities.map((opt) {
                return DropdownMenuItem<String>(
                  value: opt.key,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            ActivitySvgIcon(
                              activityKey: opt.key,
                              size: 18,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                opt.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildActivityCategoryBadge(_isOptionEdgeAi(opt)),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedActivityKey = val;
                  });
                }
              },
            ),
            if (_recentActivityKeys.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Récemment utilisés',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < _recentActivityKeys.length; i += 2) ...[
                    if (i > 0) const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: StudioRecentActivityTile(
                            activityKey: _recentActivityKeys[i],
                            isSelected: _recentActivityKeys[i] == _selectedActivityKey,
                            customText: _customLabelController.text.trim(),
                            datasetStats: _datasetStats,
                            isEdgeAi: _isOptionEdgeAi(StudioActivityOption.defaultActivities.firstWhere((a) => a.key == _recentActivityKeys[i])),
                            onSelect: (selectedKey) => setState(() {
                              _selectedActivityKey = selectedKey;
                            }),
                            targetPerClass: StudioSessionDialog.targetPerClass,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: i + 1 < _recentActivityKeys.length
                              ? StudioRecentActivityTile(
                                  activityKey: _recentActivityKeys[i + 1],
                                  isSelected: _recentActivityKeys[i + 1] == _selectedActivityKey,
                                  customText: _customLabelController.text.trim(),
                                  datasetStats: _datasetStats,
                                  isEdgeAi: _isOptionEdgeAi(StudioActivityOption.defaultActivities.firstWhere((a) => a.key == _recentActivityKeys[i + 1])),
                                  onSelect: (selectedKey) => setState(() {
                                    _selectedActivityKey = selectedKey;
                                  }),
                                  targetPerClass: StudioSessionDialog.targetPerClass,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
            if (_selectedActivityKey == 'custom') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _customLabelController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Libellé personnalisé',
                  hintText: 'Ex: saut_a_la_corde, squat...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.timer_outlined,
                    size: 16, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  'Durée : 5 secondes',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (_successMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFA5D6A7)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, size: 18, color: Color(0xFF2E7D32)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _successMessage!,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1B5E20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
        FilledButton.icon(
          onPressed: _isStarting ? null : _onConfirm,
          icon: _isStarting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.play_arrow, size: 18),
          label: const Text("Démarrer l'enregistrement"),
        ),
      ],
    );
  }
}
