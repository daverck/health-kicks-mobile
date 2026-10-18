import 'package:flutter/material.dart';
import '../../../services/ble/ble_ota_service.dart';

/// Modal dialog displaying live OTA flashing progress, speed, SHA-256 validation, and reboot auto-reconnection status.
class OtaProgressDialog extends StatelessWidget {
  final Stream<BleOtaProgress> progressStream;
  final BleOtaProgress initialProgress;
  final VoidCallback onAbort;
  final bool isReconnecting;
  final bool reconnectSuccess;
  final String? reconnectMessage;

  const OtaProgressDialog({
    super.key,
    required this.progressStream,
    required this.initialProgress,
    required this.onAbort,
    this.isReconnecting = false,
    this.reconnectSuccess = false,
    this.reconnectMessage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<BleOtaProgress>(
      stream: progressStream,
      initialData: initialProgress,
      builder: (dialogContext, snapshot) {
        final prog = snapshot.data ?? initialProgress;
        final isBusy = prog.status == BleOtaStatus.preparing ||
            prog.status == BleOtaStatus.transferring ||
            prog.status == BleOtaStatus.finalizing;
        final isDone = prog.status == BleOtaStatus.success;
        final isError = prog.status == BleOtaStatus.error ||
            prog.status == BleOtaStatus.aborted;

        return PopScope(
          canPop: !isBusy,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(
                  isDone
                      ? Icons.check_circle
                      : isError
                          ? Icons.error_outline
                          : Icons.system_update_alt,
                  color: isDone
                      ? Colors.green
                      : isError
                          ? Colors.redAccent
                          : theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isDone
                        ? 'Mise à jour réussie'
                        : isError
                            ? 'Erreur de mise à jour'
                            : 'Mise à jour en cours',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  prog.message ?? 'Préparation du transfert...',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isError
                        ? Colors.redAccent
                        : isDone
                            ? Colors.green
                            : theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: prog.status == BleOtaStatus.preparing ? null : prog.progress,
                  minHeight: 10,
                  borderRadius: BorderRadius.circular(5),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isDone
                        ? Colors.green
                        : isError
                            ? Colors.redAccent
                            : theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${(prog.progress * 100).toStringAsFixed(1)} %',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      '${(prog.bytesSent / 1024).toStringAsFixed(0)} / ${(prog.totalBytes / 1024).toStringAsFixed(0)} Ko',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (prog.status == BleOtaStatus.transferring) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Débit : ${prog.speedKbps.toStringAsFixed(1)} Ko/s',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (prog.estimatedTimeRemaining != null)
                        Text(
                          'Restant : ~${prog.estimatedTimeRemaining!.inSeconds} s',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ],
                if (isDone) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      'L\'ESP32-S3 a validé la nouvelle partition et redémarre automatiquement.',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.brightness == Brightness.dark
                            ? Colors.green.shade300
                            : Colors.green.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (isReconnecting || reconnectSuccess || reconnectMessage != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: reconnectSuccess
                            ? Colors.teal.withValues(alpha: 0.12)
                            : isReconnecting
                                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
                                : Colors.orange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: reconnectSuccess
                              ? Colors.teal
                              : isReconnecting
                                  ? theme.colorScheme.primary.withValues(alpha: 0.3)
                                  : Colors.orange,
                        ),
                      ),
                      child: Row(
                        children: [
                          if (isReconnecting)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else if (reconnectSuccess)
                            const Icon(Icons.check_circle, color: Colors.teal, size: 18)
                          else
                            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              reconnectMessage ?? '',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
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
                    ),
                  ],
                ],
              ],
            ),
            actions: [
              if (isBusy && prog.status != BleOtaStatus.finalizing)
                TextButton(
                  onPressed: onAbort,
                  child: const Text(
                    'Annuler',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              if (!isBusy)
                FilledButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: Text(isDone ? 'Terminer' : 'Fermer'),
                ),
            ],
          ),
        );
      },
    );
  }
}

