import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Activity option model for the Studio session configuration.
class StudioActivityOption {
  final String key;
  final String label;
  final String emoji;

  const StudioActivityOption({
    required this.key,
    required this.label,
    required this.emoji,
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

  static const String prefLastActivityKey = 'hk_studio_last_activity';
  static const String prefLastCustomLabel = 'hk_studio_last_custom_label';

  const StudioSessionDialog({
    super.key,
    required this.onStartSession,
    this.initialActivityKey,
    this.initialCustomLabel,
    this.preferences,
  });

  static const List<StudioActivityOption> defaultActivities = [
    StudioActivityOption(key: 'walk', label: 'Marche', emoji: '🚶'),
    StudioActivityOption(key: 'run', label: 'Course', emoji: '🏃'),
    StudioActivityOption(key: 'stairs', label: 'Escaliers', emoji: '🪜'),
    StudioActivityOption(key: 'idle', label: 'Repos / Assis', emoji: '🪑'),
    StudioActivityOption(key: 'jump', label: 'Saut', emoji: '🦘'),
    StudioActivityOption(key: 'custom', label: 'Autre / Personnalisé', emoji: '🏷️'),
  ];

  static const double fixedDurationSec = 5.0;

  @override
  State<StudioSessionDialog> createState() => _StudioSessionDialogState();
}

class _StudioSessionDialogState extends State<StudioSessionDialog> {
  late String _selectedActivityKey;
  late final TextEditingController _customLabelController;

  @override
  void initState() {
    super.initState();
    _selectedActivityKey = widget.initialActivityKey ?? 'walk';
    _customLabelController = TextEditingController(text: widget.initialCustomLabel ?? '');

    if (widget.initialActivityKey == null) {
      _loadSavedPreferences();
    }
  }

  Future<void> _loadSavedPreferences() async {
    try {
      final prefs = widget.preferences ?? await SharedPreferences.getInstance();
      final savedKey = prefs.getString(StudioSessionDialog.prefLastActivityKey);
      final savedCustom = prefs.getString(StudioSessionDialog.prefLastCustomLabel);
      if (savedKey != null && StudioSessionDialog.defaultActivities.any((a) => a.key == savedKey)) {
        if (mounted) {
          setState(() {
            _selectedActivityKey = savedKey;
            if (savedCustom != null && savedCustom.isNotEmpty) {
              _customLabelController.text = savedCustom;
            }
          });
        }
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
        await prefs.setString(StudioSessionDialog.prefLastCustomLabel, customLabel);
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

  void _onConfirm() {
    String label = _selectedActivityKey;
    final customText = _customLabelController.text.trim();
    if (_selectedActivityKey == 'custom') {
      label = customText.isNotEmpty ? customText : 'custom';
    }

    _savePreferences(_selectedActivityKey, customText);

    Navigator.of(context).pop();
    widget.onStartSession(
      label: label,
      durationSec: StudioSessionDialog.fixedDurationSec,
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
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: StudioSessionDialog.defaultActivities.map((opt) {
                return DropdownMenuItem<String>(
                  value: opt.key,
                  child: Text(opt.displayText),
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
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.timer_outlined, size: 16, color: theme.colorScheme.onSurfaceVariant),
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
