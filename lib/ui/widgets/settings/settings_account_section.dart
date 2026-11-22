import 'package:material_ui/material_ui.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../services/auth/auth_service.dart';

/// Card widget visualizing authenticated user profile, role badge, session controls,
/// and App Store / Google Play compliant account self-deletion.
class SettingsAccountSection extends StatefulWidget {
  final AuthService? authService;
  final VoidCallback? onLogout;
  final Future<bool> Function()? onDeleteAccount;

  const SettingsAccountSection({
    super.key,
    this.authService,
    this.onLogout,
    this.onDeleteAccount,
  });

  @override
  State<SettingsAccountSection> createState() => _SettingsAccountSectionState();
}

class _SettingsAccountSectionState extends State<SettingsAccountSection> {
  bool _isDeleting = false;

  Future<void> _handleDeleteAccount() async {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.deleteAccountConfirmTitle,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            l10n.deleteAccountConfirmMessage,
            style: theme.textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.deleteAccountConfirmButton),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _isDeleting = true;
    });

    try {
      final success = widget.onDeleteAccount != null
          ? await widget.onDeleteAccount!()
          : await widget.authService?.deleteAccount() ?? false;

      if (!mounted) return;

      if (success) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.deleteAccountSuccess),
            backgroundColor: Colors.green.shade700,
          ),
        );
        if (nav.canPop()) {
          nav.pop();
        }
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.deleteAccountError),
            backgroundColor: theme.colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.authService?.currentUser;
    if (user == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 32),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            'COMPTE & PROFIL',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      ((user.name != null && user.name!.isNotEmpty) ? user.name![0] : 'U').toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name ?? 'Utilisateur',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Text(
                          user.email,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      user.role.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              if (widget.onLogout != null) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.logout, size: 16),
                    label: const Text('Se déconnecter'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: _isDeleting ? null : widget.onLogout,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                l10n.dangerZone,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.error,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: _isDeleting
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.error,
                          ),
                        )
                      : Icon(Icons.delete_forever, size: 18, color: theme.colorScheme.error),
                  label: Text(
                    l10n.deleteAccount,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5)),
                    foregroundColor: theme.colorScheme.error,
                  ),
                  onPressed: _isDeleting ? null : () => _handleDeleteAccount(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
