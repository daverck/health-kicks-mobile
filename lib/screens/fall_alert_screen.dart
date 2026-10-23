import 'package:flutter/material.dart';
import '../controllers/fall_alert_controller.dart';

/// Full-screen high-contrast emergency overlay displayed when a live fall is detected.
/// Contract reference: contracts/fall_alerting.md (Sections 3.B & 7.B)
class FallAlertScreen extends StatelessWidget {
  final FallAlertController controller;

  const FallAlertScreen({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.state ?? 'PENDING';
        final isAcknowledged = state == 'ACKNOWLEDGED';
        final isExhausted = state == 'EXHAUSTED';

        final Color bgColor;
        if (isAcknowledged) {
          bgColor = const Color(0xFF065F46); // Deep reassuring emerald
        } else if (isExhausted) {
          bgColor = const Color(0xFF7F1D1D); // Critical crimson
        } else {
          bgColor = const Color(0xFF991B1B); // High-contrast emergency red
        }

        return Material(
          color: bgColor,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: IntrinsicHeight(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildHeader(state),
                            const SizedBox(height: 16),
                            _buildBody(state),
                            const SizedBox(height: 20),
                            _buildActions(state),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(String state) {
    IconData icon;
    String title;

    switch (state) {
      case 'ACKNOWLEDGED':
        icon = Icons.verified_user_rounded;
        title = 'Prise en charge confirmée';
        break;
      case 'EXHAUSTED':
        icon = Icons.phone_in_talk_rounded;
        title = 'Aucun proche n\'a répondu — Appeler le 112';
        break;
      case 'ESCALATING':
        icon = Icons.notifications_active_rounded;
        title = 'Alerte envoyée à vos proches';
        break;
      case 'PENDING':
      default:
        icon = Icons.warning_amber_rounded;
        title = 'Chute détectée — Ça va ?';
        break;
    }

    return Column(
      children: [
        Icon(
          icon,
          size: 64,
          color: Colors.white,
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            height: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildBody(String state) {
    if (state == 'PENDING') {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 140,
            height: 140,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.15),
              border: Border.all(color: Colors.white, width: 4),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${controller.remainingSeconds}',
                  key: const Key('fall_alert_countdown_value'),
                  style: const TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1.0,
                  ),
                ),
                const Text(
                  'secondes',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Sans réponse de votre part, une alerte sera envoyée à vos proches d\'urgence.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
        ],
      );
    }

    if (state == 'ESCALATING') {
      final rank = controller.currentContactRank;
      final total = controller.contactsTotal;
      final String statusText;
      if (rank > 0 && total > 0) {
        statusText =
            'Alerte envoyée au proche n°$rank sur $total — En attente de confirmation…';
      } else if (rank > 0) {
        statusText =
            'Alerte envoyée au proche n°$rank — En attente de confirmation…';
      } else {
        statusText = 'Alerte transmise — En attente de confirmation…';
      }

      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white38, width: 1.5),
        ),
        child: Column(
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(
              statusText,
              key: const Key('fall_alert_escalating_text'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1.35,
              ),
            ),
          ],
        ),
      );
    }

    if (state == 'ACKNOWLEDGED') {
      final name = (controller.acknowledgedByName != null &&
              controller.acknowledgedByName!.trim().isNotEmpty)
          ? controller.acknowledgedByName!.trim()
          : 'Un proche';

      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white54, width: 2),
        ),
        child: Text(
          'Rassurez-vous : $name a pris en charge votre alerte',
          key: const Key('fall_alert_acknowledged_text'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            height: 1.35,
          ),
        ),
      );
    }

    // EXHAUSTED
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amberAccent, width: 2),
      ),
      child: const Text(
        'Aucun proche n\'a pu confirmer la prise en charge dans le délai imparti. Contactez immédiatement les secours.',
        key: Key('fall_alert_exhausted_text'),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          height: 1.35,
        ),
      ),
    );
  }

  Widget _buildActions(String state) {
    if (state == 'ACKNOWLEDGED') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 64,
            child: ElevatedButton.icon(
              key: const Key('fall_alert_dismiss_button'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF065F46),
                textStyle: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: controller.dismissAlertScreen,
              icon: const Icon(Icons.check_circle_outline, size: 28),
              label: const Text('Fermer l\'écran'),
            ),
          ),
          const SizedBox(height: 12),
          _buildCall112Button(isPrimary: false),
        ],
      );
    }

    if (state == 'EXHAUSTED') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCall112Button(isPrimary: true),
          const SizedBox(height: 16),
          SizedBox(
            height: 58,
            child: OutlinedButton.icon(
              key: const Key('fall_alert_cancel_button'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white70, width: 2),
                textStyle: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: controller.dismissAlertScreen,
              icon: const Icon(Icons.check_rounded, size: 24),
              label: const Text('Je vais bien (Annuler l\'alerte)'),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. "Je vais bien (Annuler l'alerte)" - prominent green button
        SizedBox(
          height: 68,
          child: ElevatedButton.icon(
            key: const Key('fall_alert_cancel_button'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              foregroundColor: Colors.white,
              textStyle: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: controller.cancelByUser,
            icon: const Icon(Icons.thumb_up_alt_rounded, size: 28),
            label: const Text('Je vais bien (Annuler l\'alerte)'),
          ),
        ),
        const SizedBox(height: 14),

        // 2. "J'ai besoin d'aide maintenant" (only during PENDING)
        if (state == 'PENDING') ...[
          SizedBox(
            height: 64,
            child: ElevatedButton.icon(
              key: const Key('fall_alert_confirm_button'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF991B1B),
                textStyle: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: controller.confirmEmergencyNow,
              icon: const Icon(Icons.sos_rounded, size: 28),
              label: const Text('J\'ai besoin d\'aide maintenant'),
            ),
          ),
          const SizedBox(height: 14),
        ],

        // 3. "Appeler le 112"
        _buildCall112Button(isPrimary: false),
      ],
    );
  }

  Widget _buildCall112Button({required bool isPrimary}) {
    return SizedBox(
      height: isPrimary ? 76 : 58,
      child: ElevatedButton.icon(
        key: const Key('fall_alert_call_112_button'),
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? Colors.amberAccent.shade400 : Colors.black54,
          foregroundColor: isPrimary ? Colors.black : Colors.white,
          side: isPrimary
              ? BorderSide.none
              : const BorderSide(color: Colors.white54, width: 1.5),
          textStyle: TextStyle(
            fontSize: isPrimary ? 24 : 18,
            fontWeight: FontWeight.w900,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: controller.callEmergency112,
        icon: Icon(Icons.phone_forwarded_rounded, size: isPrimary ? 32 : 24),
        label: const Text('Appeler le 112'),
      ),
    );
  }
}
