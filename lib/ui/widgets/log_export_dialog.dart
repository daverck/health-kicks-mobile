import 'package:flutter/material.dart';
import '../../models/log_entry_model.dart';
import '../../services/log_export_service.dart';

/// Modal dialog for previewing, copying, or exporting gateway event logs via email.
class LogExportDialog extends StatefulWidget {
  final List<LogEntry> logs;
  final String deviceId;
  final String? deviceName;
  final String? bleStatus;
  final int? mtu;
  final bool? mqttConnected;

  const LogExportDialog({
    super.key,
    required this.logs,
    this.deviceId = 'HK-2',
    this.deviceName,
    this.bleStatus,
    this.mtu,
    this.mqttConnected,
  });

  @override
  State<LogExportDialog> createState() => _LogExportDialogState();
}

class _LogExportDialogState extends State<LogExportDialog> {
  late final TextEditingController _recipientController;
  late final String _logText;

  @override
  void initState() {
    super.initState();
    _recipientController = TextEditingController();
    _logText = LogExportService.formatLogs(
      logs: widget.logs,
      deviceId: widget.deviceId,
      deviceName: widget.deviceName,
      bleStatus: widget.bleStatus,
      mtu: widget.mtu,
      mqttConnected: widget.mqttConnected,
    );
  }

  @override
  void dispose() {
    _recipientController.dispose();
    super.dispose();
  }

  Future<void> _handleCopy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    await LogExportService.copyToClipboard(_logText);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Logs copiés dans le presse-papier !'),
        backgroundColor: Colors.teal,
      ),
    );
  }

  Future<void> _handleSend(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final recipient = _recipientController.text.trim();
    Navigator.of(context).pop();

    final subject =
        'Journal d\'événements HealthKicks - ${widget.deviceId} - ${DateTime.now().toIso8601String().substring(0, 10)}';
    final success = await LogExportService.sendEmail(
      recipient: recipient,
      subject: subject,
      body: _logText,
    );

    if (!success) {
      await LogExportService.copyToClipboard(_logText);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Impossible d\'ouvrir l\'application email. Les logs ont été copiés dans le presse-papier.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.email_outlined),
          SizedBox(width: 8),
          Text('Export du Journal'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Envoyer les ${widget.logs.length} événements par email.',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _recipientController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Destinataire (optionnel)',
                hintText: 'ex: support@healthkicks.fr',
                prefixIcon: Icon(Icons.alternate_email, size: 20),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              constraints: const BoxConstraints(maxHeight: 120),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: SingleChildScrollView(
                child: Text(
                  _logText,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Copier'),
          onPressed: () => _handleCopy(context),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.send, size: 16),
          label: const Text('Envoyer'),
          onPressed: () => _handleSend(context),
        ),
      ],
    );
  }
}
