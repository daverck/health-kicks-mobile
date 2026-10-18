import 'package:flutter/material.dart';

/// Status banner showing automatic BLE reconnection attempts after ESP32 reboot.
class ReconnectionBanner extends StatelessWidget {
  final bool isReconnecting;
  final bool reconnectSuccess;
  final String? reconnectMessage;

  const ReconnectionBanner({
    super.key,
    required this.isReconnecting,
    required this.reconnectSuccess,
    this.reconnectMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (!isReconnecting && !reconnectSuccess && (reconnectMessage == null || reconnectMessage!.isEmpty)) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: reconnectSuccess
            ? Colors.teal.withValues(alpha: 0.15)
            : isReconnecting
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                : Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: reconnectSuccess
              ? Colors.teal
              : isReconnecting
                  ? theme.colorScheme.primary
                  : Colors.orange,
        ),
      ),
      child: Row(
        children: [
          if (isReconnecting)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          else if (reconnectSuccess)
            const Icon(Icons.check_circle, color: Colors.teal, size: 20)
          else
            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              reconnectMessage ?? '',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: reconnectSuccess
                    ? Colors.teal.shade800
                    : isReconnecting
                        ? theme.colorScheme.onSurface
                        : Colors.orange.shade900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
