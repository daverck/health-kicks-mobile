import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/log_entry_model.dart';

/// Service for exporting and emailing the mobile event log.
class LogExportService {
  /// Formats a list of log entries into a structured text report.
  static String formatLogs({
    required List<LogEntry> logs,
    required String deviceId,
    String? deviceName,
    String? bleStatus,
    int? mtu,
    bool? mqttConnected,
    DateTime? exportDate,
  }) {
    final now = exportDate ?? DateTime.now();
    final buffer = StringBuffer();
    buffer.writeln('=== Journal d\'événements HealthKicks ===');
    buffer.writeln('Périphérique : $deviceId${deviceName != null && deviceName.isNotEmpty ? " ($deviceName)" : ""}');
    if (bleStatus != null) buffer.writeln('Statut BLE : $bleStatus (MTU: ${mtu ?? 23})');
    if (mqttConnected != null) buffer.writeln('Statut MQTT : ${mqttConnected ? "Connecté" : "Déconnecté"}');
    buffer.writeln('Date d\'export : ${now.toIso8601String().substring(0, 19)}');
    buffer.writeln('Nombre d\'événements : ${logs.length}');
    buffer.writeln('----------------------------------------');

    if (logs.isEmpty) {
      buffer.writeln('(Aucun événement enregistré)');
    } else {
      for (final entry in logs) {
        buffer.writeln(entry.toFormattedLine());
      }
    }

    buffer.writeln('========================================');
    return buffer.toString();
  }

  /// Constructs a conforming mailto: URI with query parameter encoding.
  static Uri buildMailtoUri({
    String recipient = '',
    required String subject,
    required String body,
  }) {
    final query = _encodeQueryParameters(<String, String>{
      'subject': subject,
      'body': body,
    });

    return Uri(
      scheme: 'mailto',
      path: recipient.trim(),
      query: query,
    );
  }

  static String? _encodeQueryParameters(Map<String, String> params) {
    return params.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }

  /// Opens the default email app with the prefilled draft.
  /// An alternative `launcher` can be injected for unit tests.
  static Future<bool> sendEmail({
    String recipient = '',
    required String subject,
    required String body,
    Future<bool> Function(Uri uri, {LaunchMode mode})? launcher,
  }) async {
    final uri = buildMailtoUri(recipient: recipient, subject: subject, body: body);
    try {
      if (launcher != null) {
        return await launcher(uri, mode: LaunchMode.externalApplication);
      }
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Copies text string to system clipboard.
  static Future<void> copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }
}

