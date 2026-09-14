import 'package:flutter/material.dart';
import '../../services/auth/auth_service.dart';

/// Écran d'authentification utilisateur HealthKicks via SSO (Google / Microsoft Azure).
class LoginScreen extends StatefulWidget {
  final AuthService authService;
  final VoidCallback onLoginSuccess;

  const LoginScreen({
    super.key,
    required this.authService,
    required this.onLoginSuccess,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;

  Future<void> _handleSsoLogin(Future<bool> Function() ssoAction, String providerName) async {
    setState(() {
      _isLoading = true;
    });

    final success = await ssoAction();

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    if (!success && widget.authService.lastError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.authService.lastError!),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  void _showDevBackendDialog() {
    final controller = TextEditingController(text: widget.authService.backendBaseUrl);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.tune, size: 20),
            SizedBox(width: 8),
            Text('URL API Backend'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ajustez l\'adresse IP hôte de votre backend FastAPI de développement.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'URL Backend FastAPI',
                hintText: 'http://192.168.1.127:8000',
                prefixIcon: Icon(Icons.api),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final newUrl = controller.text.trim();
              if (newUrl.isNotEmpty) {
                widget.authService.updateBackendBaseUrl(newUrl);
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('URL Backend mise à jour : $newUrl')),
                );
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final isServiceLoading = widget.authService.state == AuthState.loading || _isLoading;
    final errorMessage = widget.authService.lastError;

    return Scaffold(
      appBar: AppBar(
        title: const Text('HealthKicks Auth'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Régler URL Backend',
            onPressed: _showDevBackendDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. Logo & Titre
                  Icon(
                    Icons.monitor_heart,
                    size: 72,
                    color: primaryColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'HealthKicks',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Plateforme d\'analyse biomécanique & passerelle IoT',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Message d'erreur éventuel
                  if (errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.red, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              errorMessage,
                              style: TextStyle(color: Colors.red.shade900, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Indicateur de chargement actif
                  if (isServiceLoading) ...[
                    const Center(
                      child: Column(
                        children: [
                          CircularProgressIndicator(strokeWidth: 3),
                          SizedBox(height: 16),
                          Text(
                            'Authentification en cours...',
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Boutons d'authentification SSO
                  OutlinedButton.icon(
                    icon: const Icon(Icons.g_mobiledata, size: 28),
                    label: const Text(
                      'Continuer avec Google',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: isServiceLoading
                        ? null
                        : () => _handleSsoLogin(
                              widget.authService.signInWithGoogle,
                              'Google',
                            ),
                  ),
                  const SizedBox(height: 14),

                  OutlinedButton.icon(
                    icon: const Icon(Icons.window, size: 20),
                    label: const Text(
                      'Continuer avec Microsoft / Azure',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: isServiceLoading
                        ? null
                        : () => _handleSsoLogin(
                              widget.authService.signInWithAzure,
                              'Microsoft Azure',
                            ),
                  ),
                  const SizedBox(height: 48),

                  // Indicateur backend actif
                  Text(
                    'Serveur Backend : ${widget.authService.backendBaseUrl}',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


