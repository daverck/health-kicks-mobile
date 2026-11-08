/// Activity option model and catalog for Studio recording sessions.
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
        key: 'lying_lateral', label: 'Couché latéral', emoji: '🛌', isEdgeAi: true),
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
}
