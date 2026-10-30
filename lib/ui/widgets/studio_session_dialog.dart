import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/studio/studio_api_service.dart';

export '../../services/studio/studio_api_service.dart' show StudioDatasetStats;

/// Activity option model for the Studio session configuration.
class StudioActivityOption {
  final String key;
  final String label;
  final String emoji;
  final bool isEdgeAi;

  const StudioActivityOption({
    required this.key,
    required this.label,
    required this.emoji,
    this.isEdgeAi = true,
  });

  String get displayText => '$label $emoji';
}

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

  static const List<StudioActivityOption> defaultActivities = [
    StudioActivityOption(key: 'walk', label: 'Marche', emoji: '🚶', isEdgeAi: true),
    StudioActivityOption(key: 'run', label: 'Course', emoji: '🏃', isEdgeAi: true),
    StudioActivityOption(key: 'stairs', label: 'Escaliers', emoji: '🪜', isEdgeAi: false),
    StudioActivityOption(
        key: 'stairs_up', label: 'Escaliers (Montée)', emoji: '↗️', isEdgeAi: true),
    StudioActivityOption(
        key: 'stairs_down', label: 'Escaliers (Descente)', emoji: '↘️', isEdgeAi: true),
    StudioActivityOption(key: 'idle', label: 'Repos / Assis', emoji: '🪑', isEdgeAi: true),
    StudioActivityOption(
        key: 'sit_down', label: "S'asseoir (Transition)", emoji: '🪑', isEdgeAi: true),
    StudioActivityOption(
        key: 'stand_up', label: 'Se lever (Transition)', emoji: '🧍', isEdgeAi: true),
    StudioActivityOption(
        key: 'lie_down', label: "S'allonger (Transition)", emoji: '🛏️', isEdgeAi: true),
    StudioActivityOption(
        key: 'lying_supine', label: 'Couché dorsal', emoji: '🛌', isEdgeAi: true),
    StudioActivityOption(
        key: 'lying_prone', label: 'Couché frontal', emoji: '🛌', isEdgeAi: true),
    StudioActivityOption(
        key: 'lying_lateral', label: 'Couché latéral', emoji: '🛌', isEdgeAi: false),
    StudioActivityOption(key: 'jump', label: 'Saut', emoji: '🦘', isEdgeAi: true),
    StudioActivityOption(
        key: 'stumble_recover', label: 'Trébuchement rattrapé', emoji: '⚠️', isEdgeAi: false),
    StudioActivityOption(
        key: 'fall_forward', label: 'Chute avant', emoji: '⤵️', isEdgeAi: true),
    StudioActivityOption(
        key: 'fall_backward', label: 'Chute arrière', emoji: '⤴️', isEdgeAi: true),
    StudioActivityOption(
        key: 'fall_lateral', label: 'Chute latérale', emoji: '↔️', isEdgeAi: true),
    StudioActivityOption(
        key: 'fall_recovery', label: 'Chute relevée', emoji: '🔄', isEdgeAi: true),
    StudioActivityOption(
        key: 'custom', label: 'Autre / Personnalisé', emoji: '🏷️', isEdgeAi: false),
  ];

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

  Widget _buildCompactCountBadge({
    required Key badgeKey,
    required String icon,
    required int count,
    required Color activeBg,
    required Color activeText,
    required Color inactiveBg,
    required Color inactiveText,
  }) {
    final isActive = count > 0;
    return Container(
      key: badgeKey,
      padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 1),
      decoration: BoxDecoration(
        color: isActive ? activeBg : inactiveBg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$icon$count',
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          color: isActive ? activeText : inactiveText,
        ),
      ),
    );
  }

  Widget _buildRecentActivityTile(String key, ThemeData theme) {
    final option = StudioSessionDialog.defaultActivities
        .firstWhere((activity) => activity.key == key);
    final isSelected = key == _selectedActivityKey;
    final customText = _customLabelController.text.trim();
    final label =
        key == 'custom' && customText.isNotEmpty ? customText : option.label;
    final effectiveLabelKey =
        key == 'custom' && customText.isNotEmpty ? customText : key;

    final totalCount = _datasetStats.getCountForLabel(effectiveLabelKey);
    final validatedCount =
        _datasetStats.getValidatedCountForLabel(effectiveLabelKey);
    final pendingCount =
        _datasetStats.getPendingCountForLabel(effectiveLabelKey);
    final showCounts = totalCount < StudioSessionDialog.targetPerClass;
    final isDark = theme.brightness == Brightness.dark;

    return SizedBox(
      width: 126,
      height: 58,
      child: Material(
        color: isSelected
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: ValueKey('studio-recent-activity-$key'),
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() {
            _selectedActivityKey = key;
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(option.emoji),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        option.isEdgeAi ? '⚡ Edge AI' : '🧪 R&D',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: option.isEdgeAi
                              ? const Color(0xFF2E7D32)
                              : const Color(0xFF6A1B9A),
                        ),
                      ),
                    ),
                    if (showCounts) ...[
                      const SizedBox(width: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildCompactCountBadge(
                            badgeKey: ValueKey('studio-recent-validated-$key'),
                            icon: '✅',
                            count: validatedCount,
                            activeBg: isDark
                                ? const Color(0xFF064E3B)
                                : const Color(0xFFD1FAE5),
                            activeText: isDark
                                ? const Color(0xFFA7F3D0)
                                : const Color(0xFF065F46),
                            inactiveBg: isDark
                                ? const Color(0xFF374151)
                                : const Color(0xFFF3F4F6),
                            inactiveText: const Color(0xFF9CA3AF),
                          ),
                          const SizedBox(width: 2),
                          _buildCompactCountBadge(
                            badgeKey: ValueKey('studio-recent-pending-$key'),
                            icon: '⏳',
                            count: pendingCount,
                            activeBg: isDark
                                ? const Color(0xFF78350F)
                                : const Color(0xFFFEF3C7),
                            activeText: isDark
                                ? const Color(0xFFFDE68A)
                                : const Color(0xFF92400E),
                            inactiveBg: isDark
                                ? const Color(0xFF374151)
                                : const Color(0xFFF3F4F6),
                            inactiveText: const Color(0xFF9CA3AF),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
                      Flexible(
                        child: Text(
                          opt.displayText,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildActivityCategoryBadge(opt.isEdgeAi),
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
                          child: _buildRecentActivityTile(
                            _recentActivityKeys[i],
                            theme,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: i + 1 < _recentActivityKeys.length
                              ? _buildRecentActivityTile(
                                  _recentActivityKeys[i + 1],
                                  theme,
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
