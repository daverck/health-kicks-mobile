import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final Future<void> Function({
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

  static const String prefLastActivityKey = 'hk_studio_last_activity';
  static const String prefLastCustomLabel = 'hk_studio_last_custom_label';
  static const String prefRecentActivityKeys = 'hk_studio_recent_activities';
  static const int maxRecentActivities = 4;

  const StudioSessionDialog({
    super.key,
    required this.onStartSession,
    this.initialActivityKey,
    this.initialCustomLabel,
    this.preferences,
    this.onActivitySaved,
  });

  static const List<StudioActivityOption> defaultActivities = [
    StudioActivityOption(key: 'walk', label: 'Marche', emoji: '🚶', isEdgeAi: true),
    StudioActivityOption(key: 'run', label: 'Course', emoji: '🏃', isEdgeAi: true),
    StudioActivityOption(key: 'stairs', label: 'Escaliers', emoji: '🪜', isEdgeAi: true),
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
        key: 'lie_down', label: "S'allonger (Transition)", emoji: '🛏️', isEdgeAi: false),
    StudioActivityOption(
        key: 'lying_supine', label: 'Couché dorsal', emoji: '🛌', isEdgeAi: false),
    StudioActivityOption(
        key: 'lying_prone', label: 'Couché frontal', emoji: '🛌', isEdgeAi: false),
    StudioActivityOption(
        key: 'lying_lateral', label: 'Couché latéral', emoji: '🛌', isEdgeAi: false),
    StudioActivityOption(key: 'jump', label: 'Saut', emoji: '🦘', isEdgeAi: false),
    StudioActivityOption(
        key: 'stumble_recover', label: 'Trébuchement rattrapé', emoji: '⚠️', isEdgeAi: true),
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

  @override
  void initState() {
    super.initState();
    _selectedActivityKey = widget.initialActivityKey ?? 'walk';
    _customLabelController =
        TextEditingController(text: widget.initialCustomLabel ?? '');

    _loadSavedPreferences();
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
    try {
      final prefs = widget.preferences ?? await SharedPreferences.getInstance();
      await prefs.setString(StudioSessionDialog.prefLastActivityKey, key);
      if (key == 'custom') {
        await prefs.setString(
            StudioSessionDialog.prefLastCustomLabel, customLabel);
      }
      final previous =
          prefs.getStringList(StudioSessionDialog.prefRecentActivityKeys) ?? [];
      final recentKeys = [
        key,
        ...previous.where((recentKey) => recentKey != key),
      ].take(StudioSessionDialog.maxRecentActivities);
      await prefs.setStringList(
        StudioSessionDialog.prefRecentActivityKeys,
        recentKeys.toList(),
      );
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

    Navigator.of(context).pop();
    await widget.onStartSession(
      label: label,
      durationSec: StudioSessionDialog.fixedDurationSec,
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
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _recentActivityKeys.map((key) {
                  final option = StudioSessionDialog.defaultActivities
                      .firstWhere((activity) => activity.key == key);
                  final isSelected = key == _selectedActivityKey;
                  final label = key == 'custom' &&
                          _customLabelController.text.trim().isNotEmpty
                      ? _customLabelController.text.trim()
                      : option.label;

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
                              Text(
                                option.isEdgeAi ? '⚡ Edge AI' : '🧪 R&D',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: option.isEdgeAi
                                      ? const Color(0xFF2E7D32)
                                      : const Color(0xFF6A1B9A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
            if (_selectedActivityKey == 'custom') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _customLabelController,
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton.icon(
          onPressed: _onConfirm,
          icon: const Icon(Icons.play_arrow, size: 18),
          label: const Text("Démarrer l'enregistrement"),
        ),
      ],
    );
  }
}
