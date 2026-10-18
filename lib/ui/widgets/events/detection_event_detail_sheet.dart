import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/detection_event.dart';

/// Modal bottom sheet displaying complete technical and biomechanical metrics of an event.
class DetectionEventDetailSheet extends StatelessWidget {
  final DetectionEvent event;

  const DetectionEventDetailSheet({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fullDateStr = DateFormat('dd/MM/yyyy HH:mm:ss').format(event.timestamp);

    return Padding(
      padding: EdgeInsets.only(
        left: 20.0,
        right: 20.0,
        top: 16.0,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24.0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header with Icon & Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: event.color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(event.icon, color: event.color, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.localizedTitle(context),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Dispositif : ${event.deviceId}',
                      style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: event.color,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  event.severity.name.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(),

          // Details Matrix
          _buildDetailRow(context, 'Horodatage précis', fullDateStr),
          _buildDetailRow(
            context,
            'Pic d\'impact',
            event.peakImpactG != null ? '${event.peakImpactG!.toStringAsFixed(2)} g' : 'Non mesuré',
            highlight: event.peakImpactG != null && event.peakImpactG! >= 2.0,
          ),
          _buildDetailRow(
            context,
            'Confiance ML',
            event.confidence != null ? '${(event.confidence! * 100).toStringAsFixed(1)} %' : 'N/A',
          ),
          _buildDetailRow(
            context,
            'Validation clinique',
            event.isValidated ? 'Confirmé / Validé' : 'En attente de qualification',
            highlightColor: event.isValidated ? Colors.green : null,
          ),
          if (event.id.isNotEmpty) _buildDetailRow(context, 'ID Événement', event.id),

          // Metadata block if present
          if (event.metadata != null && event.metadata!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'MÉTADONNÉES TECHNIQUES',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                event.metadata.toString(),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ],

          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    BuildContext context,
    String label,
    String value, {
    bool highlight = false,
    Color? highlightColor,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: highlightColor ?? (highlight ? Colors.red : null),
            ),
          ),
        ],
      ),
    );
  }
}

