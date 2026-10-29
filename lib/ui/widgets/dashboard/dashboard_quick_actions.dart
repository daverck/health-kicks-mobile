import 'package:flutter/material.dart';

/// Row of quick testing and clinical action controls on the gateway dashboard.
class DashboardQuickActions extends StatelessWidget {
  final VoidCallback onSendTestHaptic;
  final bool isClinicianOrAdmin;
  final VoidCallback onOpenStudio;
  final bool isConnected;

  const DashboardQuickActions({
    super.key,
    required this.onSendTestHaptic,
    required this.isClinicianOrAdmin,
    required this.onOpenStudio,
    this.isConnected = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.vibration),
            label: const Text('Test Haptique'),
            onPressed: isConnected ? onSendTestHaptic : null,
          ),
        ),
        if (isClinicianOrAdmin) ...[
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Studio'),
              onPressed: isConnected ? onOpenStudio : null,
            ),
          ),
        ],
      ],
    );
  }
}

