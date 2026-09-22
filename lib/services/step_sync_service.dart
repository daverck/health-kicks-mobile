import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';
import 'auth/auth_service.dart';
import 'auth/token_storage_service.dart';
import 'local_storage/step_storage_service.dart';

typedef StepSyncLogCallback = void Function(String message, {bool isError});

/// Synchronization service responsible for pushing offline step snapshots to the backend.
class StepSyncService {
  final StepStorageService _storageService;
  final TokenStorageService _tokenStorage;
  final AuthService? _authService;
  final String _backendBaseUrl;
  final http.Client _httpClient;
  final StepSyncLogCallback? onLog;

  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  StepSyncService({
    required StepStorageService storageService,
    TokenStorageService? tokenStorage,
    AuthService? authService,
    String? backendBaseUrl,
    http.Client? httpClient,
    this.onLog,
  })  : _storageService = storageService,
        _tokenStorage = tokenStorage ?? TokenStorageService(),
        _authService = authService,
        _backendBaseUrl = (backendBaseUrl ?? AppConfig.backendBaseUrl).trim().replaceAll(RegExp(r'/+$'), ''),
        _httpClient = httpClient ?? http.Client();

  /// Gathers unsynced days from SQLite and POSTs them to `/api/v1/steps/sync`.
  Future<bool> syncPendingSteps({required String deviceId}) async {
    if (_isSyncing) {
      onLog?.call('Synchronisation des pas déjà en cours...', isError: false);
      return false;
    }

    _isSyncing = true;
    try {
      final unsyncedDays = await _storageService.getUnsyncedDays();
      if (unsyncedDays.isEmpty) {
        onLog?.call('Aucun pas en attente de synchronisation.', isError: false);
        return true;
      }

      onLog?.call('Synchronisation de ${unsyncedDays.length} jour(s) de pas...', isError: false);
      String? token = await _tokenStorage.getAccessToken();

      bool allSuccess = true;
      final syncedDates = <String>[];

      for (final dayData in unsyncedDays) {
        final date = dayData['date'] as String;
        final activities = dayData['activities'] as List<Map<String, dynamic>>;

        final payload = {
          'device_id': deviceId,
          'date': date,
          'activities': activities,
        };

        final uri = Uri.parse('$_backendBaseUrl/api/v1/steps/sync');
        Map<String, String> buildHeaders(String? currentToken) => {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              if (currentToken != null && currentToken.isNotEmpty) 'Authorization': 'Bearer $currentToken',
            };

        try {
          var response = await _httpClient
              .post(
                uri,
                headers: buildHeaders(token),
                body: jsonEncode(payload),
              )
              .timeout(const Duration(seconds: 12));

          // Handle 401 token refresh
          if (response.statusCode == 401 && _authService != null) {
            onLog?.call('Jeton expiré lors du sync des pas (HTTP 401), rafraîchissement...', isError: false);
            final refreshed = await _authService.refreshToken();
            if (refreshed) {
              token = await _tokenStorage.getAccessToken();
              response = await _httpClient
                  .post(
                    uri,
                    headers: buildHeaders(token),
                    body: jsonEncode(payload),
                  )
                  .timeout(const Duration(seconds: 12));
            }
          }

          if (response.statusCode >= 200 && response.statusCode < 300) {
            syncedDates.add(date);
            onLog?.call('Pas synchronisés pour $date (HTTP ${response.statusCode})', isError: false);
          } else {
            allSuccess = false;
            onLog?.call('Échec synchronisation $date: HTTP ${response.statusCode} - ${response.body}', isError: true);
          }
        } on SocketException catch (e) {
          allSuccess = false;
          onLog?.call('Pas de connexion réseau pour synchroniser $date: $e', isError: true);
          break; // Stop loop if network is down
        } on TimeoutException {
          allSuccess = false;
          onLog?.call('Délai d\'attente dépassé pour $date', isError: true);
          break;
        } catch (e) {
          allSuccess = false;
          onLog?.call('Erreur inattendue synchronisation $date: $e', isError: true);
        }
      }

      if (syncedDates.isNotEmpty) {
        await _storageService.markDaysSynced(syncedDates);
      }

      return allSuccess;
    } finally {
      _isSyncing = false;
    }
  }
}

