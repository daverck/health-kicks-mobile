import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:healthkicks_mobile/models/log_entry_model.dart';
import 'package:healthkicks_mobile/services/log_export_service.dart';

void main() {
  group('LogEntry Model', () {
    test('correctly formats timestamp with leading zeros', () {
      final entry = LogEntry(
        timestamp: DateTime(2026, 9, 17, 9, 5, 3, 42),
        tag: 'BLE',
        message: 'Périphérique connecté',
        color: Colors.blue,
      );

      expect(entry.formattedTimestamp, '09:05:03.042');
      expect(entry.toFormattedLine(), '[09:05:03.042] [BLE] Périphérique connecté');
    });
  });

  group('LogExportService.formatLogs', () {
    test('formats report with log entries and complete metadata', () {
      final exportDate = DateTime(2026, 9, 17, 14, 30, 0);
      final logs = [
        LogEntry(
          timestamp: DateTime(2026, 9, 17, 14, 25, 10, 100),
          tag: 'BLE',
          message: 'Scan démarré',
        ),
        LogEntry(
          timestamp: DateTime(2026, 9, 17, 14, 25, 12, 250),
          tag: 'MQTT',
          message: 'Connecté avec succès',
        ),
      ];

      final report = LogExportService.formatLogs(
        logs: logs,
        deviceId: 'HK-2',
        deviceName: 'HealthKicks-HK-2',
        bleStatus: 'ready',
        mtu: 247,
        mqttConnected: true,
        exportDate: exportDate,
      );

      expect(report, contains('=== Journal d\'événements HealthKicks ==='));
      expect(report, contains('Périphérique : HK-2 (HealthKicks-HK-2)'));
      expect(report, contains('Statut BLE : ready (MTU: 247)'));
      expect(report, contains('Statut MQTT : Connecté'));
      expect(report, contains('Date d\'export : 2026-09-17T14:30:00'));
      expect(report, contains('Nombre d\'événements : 2'));
      expect(report, contains('[14:25:10.100] [BLE] Scan démarré'));
      expect(report, contains('[14:25:12.250] [MQTT] Connecté avec succès'));
      expect(report, contains('========================================'));
    });

    test('handles empty log with explicit mention', () {
      final report = LogExportService.formatLogs(
        logs: [],
        deviceId: 'HK-2',
        bleStatus: 'disconnected',
        mqttConnected: false,
        exportDate: DateTime(2026, 9, 17, 10, 0, 0),
      );

      expect(report, contains('Nombre d\'événements : 0'));
      expect(report, contains('(Aucun événement enregistré)'));
      expect(report, contains('Statut MQTT : Déconnecté'));
    });
  });

  group('LogExportService.buildMailtoUri', () {
    test('builds mailto URI with RFC 3986 parameter encoding', () {
      final uri = LogExportService.buildMailtoUri(
        recipient: 'support@healthkicks.fr',
        subject: 'Journal HealthKicks & Diagnostic',
        body: 'Ligne 1\nLigne 2 avec caractères accentués : éàç',
      );

      expect(uri.scheme, 'mailto');
      expect(uri.path, 'support@healthkicks.fr');
      expect(uri.queryParameters['subject'], 'Journal HealthKicks & Diagnostic');
      expect(uri.queryParameters['body'], 'Ligne 1\nLigne 2 avec caractères accentués : éàç');
    });

    test('allows leaving recipient empty for selection in mail client', () {
      final uri = LogExportService.buildMailtoUri(
        recipient: '  ',
        subject: 'Diagnostic HK',
        body: 'Logs...',
      );

      expect(uri.scheme, 'mailto');
      expect(uri.path, '');
      expect(uri.queryParameters['subject'], 'Diagnostic HK');
    });
  });

  group('LogExportService.sendEmail', () {
    test('invokes launcher with constructed URI and externalApplication mode', () async {
      Uri? capturedUri;
      LaunchMode? capturedMode;

      final success = await LogExportService.sendEmail(
        recipient: 'test@example.com',
        subject: 'Test Subject',
        body: 'Test Body',
        launcher: (uri, {mode = LaunchMode.platformDefault}) async {
          capturedUri = uri;
          capturedMode = mode;
          return true;
        },
      );

      expect(success, isTrue);
      expect(capturedUri?.scheme, 'mailto');
      expect(capturedUri?.path, 'test@example.com');
      expect(capturedMode, LaunchMode.externalApplication);
    });

    test('catches exceptions and returns false on launch failure', () async {
      final success = await LogExportService.sendEmail(
        recipient: 'test@example.com',
        subject: 'Test Subject',
        body: 'Test Body',
        launcher: (uri, {mode = LaunchMode.platformDefault}) async {
          throw Exception('No email client found');
        },
      );

      expect(success, isFalse);
    });
  });
}

