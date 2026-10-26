import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/api/api_headers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/config/app_config.dart';
import '../core/constants/ble_constants.dart';
import '../core/permissions/permission_service.dart';
import '../models/activity_detection_model.dart';
import '../models/firmware_release_model.dart';
import '../models/haptic_command_model.dart';
import '../models/log_entry_model.dart';
import '../models/step_data_model.dart';
import '../models/studio_command_model.dart';
import '../models/studio_session_model.dart';
import '../services/auth/auth_service.dart';
import '../services/auth/iot_credentials_repository.dart';
import '../services/auth/token_storage_service.dart';
import '../services/background_surveillance_service.dart';
import '../services/ble/ble_connection_manager.dart';
import '../services/ble/ble_footwear_client.dart';
import '../services/firmware/firmware_service.dart';
import '../services/gateway_coordinator.dart';
import '../services/inactivity_settings_service.dart';
import '../services/fall_sensitivity_settings_service.dart';
import '../services/local_storage/step_storage_service.dart';
import '../services/mqtt/mqtt_gateway_service.dart';
import '../services/step_sync_service.dart';
import '../services/studio/studio_api_service.dart';
import '../ui/widgets/studio_session_dialog.dart';
import 'dashboard_odometer_coordinator.dart';
import 'package:flutter/services.dart';
import '../models/hitl/hitl_detection_item.dart';
import '../services/audio/studio_audio_feedback_service.dart';
import '../services/hitl/hitl_coordinator.dart';
import 'fall_alert_controller.dart';

/// Business controller managing the background lifecycle, BLE connection,
/// MQTT synchronization, Fall Alerting, and Studio motion capture routing for the Gateway Dashboard.
class GatewayDashboardController extends ChangeNotifier {
  final String deviceId;
  final String targetDeviceId;
  final AuthService? authService;
  final FirmwareService _firmwareService;
  late final HitlCoordinator _hitlCoordinator;
  HitlCoordinator get hitlCoordinator => _hitlCoordinator;
  final StudioAudioFeedbackService _audioFeedbackService;
  late final FallAlertController _fallAlertController;
  final bool _ownsFallAlertController;

  final PermissionService _permissionService = PermissionService();
  late final BackgroundSurveillanceService _surveillanceService;
  late final DashboardOdometerCoordinator _odometerCoordinator;
  final InactivitySettingsService _inactivitySettingsService;
  final FallSensitivitySettingsService _fallSensitivitySettingsService;

  IotCredentialsRepository? _credentialsRepo;
  BleConnectionManager? _bleManager;
  BleFootwearClient? _bleClient;
  final ValueNotifier<BleFootwearClient?> _bleClientNotifier = ValueNotifier<BleFootwearClient?>(null);
  MqttGatewayService? _mqttService;
  GatewayCoordinator? _coordinator;
  StudioApiService? _studioApiService;
  StreamSubscription<StudioSessionModel>? _studioSavedSub;
  StreamSubscription<StudioCommandModel>? _remoteStudioCommandSub;

  BleConnectionStatus _bleStatus = BleConnectionStatus.disconnected;
  BluetoothDevice? _connectedDevice;
  int _mtu = 23;
  bool _mqttConnected = false;
  bool _isUserSeated = false;
  final ValueNotifier<bool> _mqttConnectedNotifier = ValueNotifier<bool>(false);
  bool _isInitializingBleClient = false;
  FirmwareReleaseModel? _latestFirmwareRelease;
  String? _installedFirmwareVersion;
  DateTime? _installedFirmwareDate;
  String? _announcedFirmwareReleaseVersion;
  final List<ActivityDetectionModel> _recentActivities = [];
  final StreamController<ActivityDetectionModel> _activityStreamController = StreamController<ActivityDetectionModel>.broadcast();
  DateTime? _lastInactivityToastTime;
  bool isRecordingDialogVisible = false;
  String _lastStudioActivityKey = 'walk';
  String _lastStudioCustomLabel = '';
  final List<LogEntry> _logs = [];
  bool _isDisposed = false;
  bool _isInitialized = false;

  // Callbacks to UI
  void Function(String message, {Color? backgroundColor})? onShowSnackBar;
  VoidCallback? onDismissSnackBar;
  void Function({required String label, required double durationSec})? onShowRecordingDialog;
  VoidCallback? onPermissionDeniedAction;

  GatewayDashboardController({
    this.deviceId = 'HK-2',
    this.targetDeviceId = 'HealthKicks-HK-2',
    this.authService,
    FirmwareService? firmwareService,
    FallAlertController? fallAlertController,
    HitlCoordinator? hitlCoordinator,
    StudioAudioFeedbackService? audioFeedbackService,
    InactivitySettingsService? inactivitySettingsService,
    FallSensitivitySettingsService? fallSensitivitySettingsService,
    this.onShowSnackBar,
    this.onDismissSnackBar,
    this.onShowRecordingDialog,
    this.onPermissionDeniedAction,
  })  : _firmwareService = firmwareService ?? FirmwareService(),
        _audioFeedbackService = audioFeedbackService ?? StudioAudioFeedbackService(),
        _inactivitySettingsService = inactivitySettingsService ?? InactivitySettingsService(),
        _fallSensitivitySettingsService = fallSensitivitySettingsService ?? FallSensitivitySettingsService(),
        _ownsFallAlertController = fallAlertController == null {
    _hitlCoordinator = hitlCoordinator ??
        HitlCoordinator(
          mqttService: _mqttService,
          studioApiService: _studioApiService,
          onLog: (msg, {bool isError = false}) {
            addLog('HITL', msg, color: isError ? Colors.red : Colors.teal);
          },
        );
    _hitlCoordinator.addListener(notifyListeners);
    _fallAlertController = fallAlertController ??
        FallAlertController(
          deviceId: deviceId,
          isMqttConnectedGetter: () => _mqttConnected || (_mqttService?.isConnected ?? false),
          onLog: (tag, msg, {bool isError = false}) {
            addLog(tag, msg, color: isError ? Colors.red : Colors.deepOrange);
          },
          onSmsStatusReported: _reportSmsStatusToApi,
        );
    _fallAlertController.addListener(_onFallAlertUpdated);
  }

  // Getters
  FallAlertController get fallAlertController => _fallAlertController;
  BleConnectionStatus get bleStatus => _bleStatus;
  Stream<BleConnectionStatus>? get bleStatusStream => _bleManager?.statusStream;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  int get mtu => _mtu;
  bool get isMqttConnected => _mqttConnected;
  ValueNotifier<bool> get mqttConnectedNotifier => _mqttConnectedNotifier;
  BleConnectionManager? get bleManager => _bleManager;
  BleFootwearClient? get bleClient => _bleClient;
  ValueNotifier<BleFootwearClient?> get bleClientNotifier => _bleClientNotifier;
  StepDataModel? get latestStepData => _odometerCoordinator.latestStepData;
  List<ActivityDetectionModel> get recentActivities => List.unmodifiable(_recentActivities);
  Stream<ActivityDetectionModel> get activityStream => _activityStreamController.stream;
  List<LogEntry> get logs => _logs;
  String get lastStudioActivityKey => _lastStudioActivityKey;
  String get lastStudioCustomLabel => _lastStudioCustomLabel;


  @visibleForTesting
  void handleActivityDetection(ActivityDetectionModel detection) {
    if (detection.activityCategory != ActivityCategory.other) {
      _isUserSeated = detection.isSeated;
    }

    final isMovementActive = !detection.isSedentary && detection.eventType != 'inactivity_alert';
    if (isMovementActive) {
      // Automatically cancel any active inactivity alert / toast
      onDismissSnackBar?.call();
    }

    if (detection.eventType == 'inactivity_alert') {
      final now = DateTime.now();
      if (_lastInactivityToastTime == null ||
          now.difference(_lastInactivityToastTime!).inSeconds >= 30) {
        _lastInactivityToastTime = now;
        onShowSnackBar?.call(
          _inactivitySettingsService.inactivityAlertMessage(isSeated: _isUserSeated),
          backgroundColor: Colors.deepOrange.shade700,
        );
      }
      return;
    }

    _recentActivities.insert(0, detection);
    if (_recentActivities.length > 20) {
      _recentActivities.removeLast();
    }
    notifyListeners();
    _activityStreamController.add(detection);

    addLog(
      'ACTIVITY',
      '${detection.eventType.toUpperCase()} (${detection.confidencePercent}%) | Chute=${detection.isFall} | Haptique=${detection.isHapticTriggered}',
    );

    if (_hitlCoordinator.isHitlActive) {
      _hitlCoordinator.registerDetection(detection);
      unawaited(HapticFeedback.mediumImpact());
      unawaited(_audioFeedbackService.playCountdownBeep());
    }

    unawaited(_fallAlertController.onActivityDetected(
      detection,
      overrideDeviceId: deviceId,
    ));
  }
  GatewayCoordinator? get coordinator => _coordinator;
  FirmwareService get firmwareService => _firmwareService;
  StepStorageService get stepStorageService => _odometerCoordinator.storageService;
  StepSyncService get stepSyncService => _odometerCoordinator.syncService;
  DashboardOdometerCoordinator get odometerCoordinator => _odometerCoordinator;
  InactivitySettingsService get inactivitySettingsService => _inactivitySettingsService;
  FallSensitivitySettingsService get fallSensitivitySettingsService => _fallSensitivitySettingsService;
  BackgroundSurveillanceService get surveillanceService => _surveillanceService;

  void _onFallAlertUpdated() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  void initialize() {
    if (_isInitialized || _isDisposed) return;
    _isInitialized = true;
    unawaited(checkForFirmwareUpdate());

    _surveillanceService = BackgroundSurveillanceService(
      onLog: (tag, msg, {bool isError = false}) {
        addLog(tag, msg, color: isError ? Colors.red : Colors.cyan);
      },
    );
    _surveillanceService.initialize();

    unawaited(_inactivitySettingsService.loadSettings());
    unawaited(_fallSensitivitySettingsService.loadSettings());

    _odometerCoordinator = DashboardOdometerCoordinator(
      deviceId: deviceId,
      authService: authService,
      onLog: (tag, msg, {Color? color}) => addLog(tag, msg, color: color),
      onStepDataUpdated: () {
        if (!_isDisposed) notifyListeners();
      },
    );
    _odometerCoordinator.initialize();
    unawaited(loadLastStudioActivity());

    _ensureBleManager();
    _initGateway();
  }

  Future<void> checkForFirmwareUpdate() async {
    if (_isDisposed) return;
    String? installedVersion;
    DateTime? installedDate;
    try {
      installedVersion = await _firmwareService.getLocalInstalledVersion();
      installedDate = await _firmwareService.getLocalInstalledDate();
      _installedFirmwareVersion = installedVersion;
      _installedFirmwareDate = installedDate;
    } catch (e) {
      addLog('FIRMWARE', 'Version locale non disponible : $e', color: Colors.orange);
    }
    if (_isDisposed) return;

    try {
      String? token;
      try {
        token = await authService?.getValidAccessToken();
      } catch (e) {
        addLog('FIRMWARE', 'Jeton API indisponible, tentative de vérification publique : $e', color: Colors.orange);
      }
      if (_isDisposed) return;

      final release = await _firmwareService.fetchLatestRelease(
        backendUrl: authService?.backendBaseUrl,
        token: token,
      );
      if (_isDisposed) return;

      _latestFirmwareRelease = release;
      addLog('FIRMWARE', 'Vérification automatique terminée : ${release.version}.');
      _notifyIfFirmwareUpdateAvailable(
        installedVersion: _installedFirmwareVersion ?? installedVersion,
        installedDate: _installedFirmwareDate ?? installedDate,
      );
    } catch (e) {
      if (!_isDisposed) {
        addLog('FIRMWARE', 'Échec de la vérification automatique du firmware : $e', color: Colors.red);
      }
    }
  }

  void _notifyIfFirmwareUpdateAvailable({
    required String? installedVersion,
    required DateTime? installedDate,
  }) {
    if (_isDisposed) return;
    final release = _latestFirmwareRelease;
    if (release == null) return;

    if (installedVersion == null && installedDate == null) {
      addLog('FIRMWARE', 'Version installée inconnue ; comparaison reportée à la connexion BLE.');
      return;
    }

    final isNewer = _firmwareService.isCloudReleaseNewer(
      cloudReleaseDate: release.releaseDate,
      installedDate: installedDate,
      cloudVersion: release.version,
      installedVersion: installedVersion,
    );
    if (!isNewer || _announcedFirmwareReleaseVersion == release.version) return;

    _announcedFirmwareReleaseVersion = release.version;
    addLog('FIRMWARE', 'Nouveau firmware disponible : ${release.version}.', color: Colors.orange);
    onShowSnackBar?.call(
      'Nouveau firmware disponible (${release.version}). Consultez Paramètres > Mise à jour du firmware.',
      backgroundColor: Colors.orange.shade800,
    );
  }

  void setForegroundState(bool isForeground) {
    _odometerCoordinator.setForegroundState(isForeground);
  }

  void flushSteps() {
    _odometerCoordinator.flushSteps();
  }

  void _ensureBleManager() {
    if (_bleManager != null) return;

    _bleManager = BleConnectionManager(
      permissionService: _permissionService,
      onLog: (msg) {
        final isError = msg.contains('Erreur') || msg.contains('refusé') || msg.contains('Échec');
        addLog(
          msg.startsWith('[PERM]') ? 'PERM' : 'BLE',
          msg.replaceFirst(RegExp(r'^\[(BLE|PERM)\]\s*'), ''),
          color: isError ? Colors.red : null,
        );
      },
    );

    _bleStatus = _bleManager!.status;
    _connectedDevice = _bleManager!.connectedDevice;
    _mtu = _bleManager!.negotiatedMtu;
    _bleManager!.addListener(_onBleManagerUpdated);

    _bleManager!.statusStream.listen((status) {
      if (_isDisposed) return;
      _bleStatus = status;
      _connectedDevice = _bleManager?.connectedDevice;
      _mtu = _bleManager?.negotiatedMtu ?? 23;
      notifyListeners();

      _surveillanceService.onBleStatusChanged(
        status,
        deviceName: _bleManager?.connectedDevice?.platformName ?? targetDeviceId,
      );

      addLog('BLE', 'Statut connexion : ${status.name}');
      if (status == BleConnectionStatus.disconnected || status == BleConnectionStatus.scanning) {
        _studioSavedSub?.cancel();
        if (_coordinator != null) {
          _coordinator?.stopRouting();
          _coordinator = null;
        } else {
          _mqttService?.publishGatewayStatus(online: false);
        }
        _bleClient?.dispose();
        _bleClient = null;
        _bleClientNotifier.value = null;
        if (status == BleConnectionStatus.disconnected) {
          _odometerCoordinator.flushSteps();
        }
      } else if (status == BleConnectionStatus.ready && _bleManager?.connectedDevice != null) {
        onBleDeviceReady(_bleManager!.connectedDevice!);
      }
    });
  }

  void _onBleManagerUpdated() {
    if (_isDisposed) return;
    _bleStatus = _bleManager!.status;
    _connectedDevice = _bleManager!.connectedDevice;
    _mtu = _bleManager!.negotiatedMtu;
    notifyListeners();
  }

  Future<void> _initGateway() async {
    addLog('INIT', 'Démarrage de la passerelle HealthKicks...');
    _ensureBleManager();
    unawaited(connectMqtt());
    unawaited(_fallAlertController.requestSmsPermission());

    try {
      final perms = await _permissionService.requestDetailedBlePermissions(
        onLog: (msg) => addLog('PERM', msg),
      );
      addLog(
        'PERM',
        perms.isGranted ? 'Permissions BLE accordées (${perms.details}).' : 'Permissions BLE incomplètes (${perms.details}).',
        color: perms.isGranted ? Colors.green : Colors.orange,
      );

      if (perms.isGranted) {
        await startBleScan(fromButton: false);
      } else if (perms.isPermanentlyDenied) {
        onPermissionDeniedAction?.call();
      }
    } catch (e) {
      addLog('PERM', 'Vérification des permissions : $e', color: Colors.orange);
      await startBleScan(fromButton: false);
    }
  }

  Future<void> startBleScan({bool fromButton = false}) async {
    if (fromButton) {
      addLog('UI', 'Bouton Re-scanner pressé');
    }

    _ensureBleManager();
    _bleStatus = BleConnectionStatus.scanning;
    _connectedDevice = null;
    notifyListeners();

    if (_coordinator != null) {
      _coordinator?.stopRouting(notifyOffline: true);
      _coordinator = null;
    } else {
      _mqttService?.publishDeviceStatus(online: false);
    }
    _bleClient?.dispose();
    _bleClient = null;
    _bleClientNotifier.value = null;

    try {
      await _bleManager?.disconnect();
    } catch (_) {}

    addLog('BLE', 'Démarrage du scan large pour "$targetDeviceId" ou Service GATT...');
    try {
      await _bleManager!.startAutoConnect(
        targetDeviceId: targetDeviceId,
        timeout: BleConstants.defaultScanTimeout,
        onLog: (msg) {
          final isError = msg.contains('Erreur') || msg.contains('refusé') || msg.contains('Échec');
          addLog(
            'BLE',
            msg,
            color: isError ? Colors.red : (msg.contains('Connecté') ? Colors.green : Colors.blueGrey),
          );
        },
      );
    } catch (e) {
      addLog('BLE', 'Erreur de scan : $e', color: Colors.red);
    }
  }

  Future<void> connectMqtt() async {
    try {
      _credentialsRepo ??= IotCredentialsRepository(
        backendBaseUrl: AppConfig.backendBaseUrl,
        tokenStorage: TokenStorageService(),
        authService: authService,
        onLog: (msg, {bool isError = false}) {
          addLog('AUTH', msg, color: isError ? Colors.red : Colors.cyan);
        },
      );

      var currentUserId = authService?.currentUserId;
      if (currentUserId == null || currentUserId.isEmpty) {
        currentUserId = await TokenStorageService().getUserIdFromToken();
      }

      if (currentUserId == null || currentUserId.isEmpty) {
        for (int i = 0; i < 6 && (currentUserId == null || currentUserId.isEmpty); i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (_isDisposed) return;
          currentUserId = authService?.currentUserId;
          if (currentUserId == null || currentUserId.isEmpty) {
            currentUserId = await TokenStorageService().getUserIdFromToken();
          }
        }
      }

      if (currentUserId == null || currentUserId.isEmpty || currentUserId == 'unknown') {
        addLog(
          'MQTT',
          'Connexion MQTT différée : utilisateur non authentifié ou userId introuvable.',
          color: Colors.amber,
        );
        _mqttConnected = false;
        _mqttConnectedNotifier.value = false;
        _fallAlertController.setMqttConnected(false);
        notifyListeners();
        return;
      }

      if (_mqttService != null && _mqttService!.userId != currentUserId) {
        _mqttService?.disconnect();
        _mqttService = null;
      }

      _mqttService ??= MqttGatewayService(
        deviceId: deviceId,
        userId: currentUserId,
        credentialsRepository: _credentialsRepo!,
        onLog: (msg, {bool isError = false}) {
          addLog('MQTT', msg, color: isError ? Colors.red : Colors.teal);
        },
        onConnectionRestored: () {
          if (_isDisposed) return;
          _mqttConnected = true;
          _mqttConnectedNotifier.value = true;
          _fallAlertController.setMqttConnected(true);
          notifyListeners();

          if (authService?.currentUser == null && authService != null) {
            unawaited(authService!.refreshCurrentUser().then((refreshed) {
              if (!refreshed && !_isDisposed) {
                addLog(
                  'AUTH',
                  'Impossible de recharger le profil utilisateur après la reconnexion cloud.',
                  color: Colors.orange,
                );
              }
            }));
          }

          if (_bleClient != null && (_bleStatus == BleConnectionStatus.ready || _bleStatus == BleConnectionStatus.connected)) {
            addLog('GATEWAY', 'Reconnexion MQTT : re-synchronisation du statut BLE online...', color: Colors.green);
            _coordinator?.publishBleStatus(online: true);
          }
        },
      );

      _fallAlertController.attachMqttService(_mqttService);

      final connected = await _mqttService!.connect();
      _mqttConnected = connected;
      _mqttConnectedNotifier.value = connected;
      _fallAlertController.setMqttConnected(connected);
      notifyListeners();

      if (connected) {
        final isBleReady = _bleClient != null && (_bleStatus == BleConnectionStatus.ready || _bleStatus == BleConnectionStatus.connected);

        if (isBleReady) {
          if (_coordinator == null) {
            _setupCoordinator();
          } else {
            addLog('GATEWAY', 'MQTT connecté : synchronisation immédiate de la présence BLE online...', color: Colors.green);
            await _coordinator!.publishBleStatus(online: true);
          }
        } else if (_bleStatus == BleConnectionStatus.scanning || _bleStatus == BleConnectionStatus.disconnected) {
          addLog('GATEWAY', 'MQTT connecté et BLE en mode scan/déconnecté : notification statut offline...', color: Colors.grey);
          await _mqttService!.publishDeviceStatus(online: false);
        }
      }
    } catch (e) {
      addLog('MQTT', 'Erreur MQTT inattendue : $e', color: Colors.red);
      _mqttConnected = false;
      _mqttConnectedNotifier.value = false;
      _fallAlertController.setMqttConnected(false);
      notifyListeners();
    }
  }

  void _setupCoordinator() {
    if (_bleClient == null || _mqttService == null) return;

    _coordinator?.stopRouting(notifyOffline: false);
    _studioSavedSub?.cancel();
    _remoteStudioCommandSub?.cancel();

    _studioApiService ??= StudioApiService(
      backendBaseUrl: AppConfig.backendBaseUrl,
      tokenStorage: TokenStorageService(),
      authService: authService,
      onLog: (msg, {bool isError = false}) {
        addLog('STUDIO', msg, color: isError ? Colors.red : Colors.green);
      },
    );

    _coordinator = GatewayCoordinator(
      bleClient: _bleClient!,
      mqttService: _mqttService!,
      studioApiService: _studioApiService,
      deviceId: deviceId,
      onLog: (msg, {bool isError = false}) {
        addLog('GATEWAY', msg, color: isError ? Colors.red : Colors.green);
      },
    );

    _studioSavedSub = _coordinator!.studioSessionSavedStream.listen((savedSession) {
      final shortId = savedSession.sessionId.length > 8 ? savedSession.sessionId.substring(0, 8) : savedSession.sessionId;
      addLog(
        'STUDIO',
        'Session Studio $shortId synchronisée (${savedSession.readings.length} trames)',
        color: const Color(0xFF0F766E),
      );
    });

    _remoteStudioCommandSub = _coordinator!.remoteStudioCommandStream.listen((command) {
      if (!isRecordingDialogVisible) {
        onShowRecordingDialog?.call(
          label: command.label,
          durationSec: command.durationSec,
        );
      }
    });

    _coordinator!.startRouting();
    addLog('GATEWAY', 'Routage bidirectionnel BLE <-> MQTT + Sync REST activé.', color: Colors.green);
  }

  Future<void> onBleDeviceReady(BluetoothDevice device) async {
    if (_isInitializingBleClient) return;
    if (_bleClient != null && _bleClient!.device.remoteId == device.remoteId && _bleClient!.isReady) {
      return;
    }
    _isInitializingBleClient = true;

    addLog('BLE', 'Appareil connecté : ${device.platformName} (MTU: $_mtu octets)');

    try {
      _bleClient?.dispose();
      _bleClient = BleFootwearClient(
        device: device,
        onLog: (msg, {bool isError = false}) {
          addLog('BLE', msg, color: isError ? Colors.red : Colors.blueGrey);
        },
      );
      addLog('BLE', 'Découverte des services GATT en cours...');
      await _bleClient!.initializeServices();
      _bleClientNotifier.value = _bleClient;
      notifyListeners();

      addLog(
        'BLE',
        'Souscription active : Activity (0002), Studio Control (0004), Burst (0005) | Haptique (0003) ${_bleClient!.hasHaptic ? "prêt" : "non trouvé"}',
      );

      if (_bleClient?.firmwareVersion != null && _bleClient!.firmwareVersion!.isNotEmpty) {
        addLog('BLE', 'Firmware détecté : ${_bleClient!.firmwareVersion} (${_bleClient!.rawBuildString ?? ""})');
        _installedFirmwareVersion = _bleClient!.firmwareVersion;
        _installedFirmwareDate = _bleClient!.firmwareBuildDate ?? _installedFirmwareDate;
        _notifyIfFirmwareUpdateAvailable(
          installedVersion: _installedFirmwareVersion,
          installedDate: _installedFirmwareDate,
        );
        _firmwareService.saveLocalInstalledFirmware(
          installedDate: _bleClient!.firmwareBuildDate ?? DateTime.now().toUtc(),
          version: _bleClient!.firmwareVersion!,
        );
      } else {
        unawaited(_firmwareService.readDeviceFirmwareInfo(device).then((info) {
          if (info.version != null && info.version!.isNotEmpty) {
            addLog('BLE', 'Firmware détecté : ${info.version} (${info.rawBuildString ?? ""})');
            _installedFirmwareVersion = info.version;
            _installedFirmwareDate = info.buildDate ?? _installedFirmwareDate;
            _notifyIfFirmwareUpdateAvailable(
              installedVersion: _installedFirmwareVersion,
              installedDate: _installedFirmwareDate,
            );
            _firmwareService.saveLocalInstalledFirmware(
              installedDate: info.buildDate ?? DateTime.now().toUtc(),
              version: info.version!,
            );
          }
        }));
      }

      _bleClient!.activityStream.listen(handleActivityDetection);

      _bleClient!.studioStatusStream.listen((statusMsg) {
        addLog('STUDIO', 'Signal d\'état : $statusMsg');
        if ((statusMsg.startsWith('COUNTDOWN') || statusMsg.startsWith('RECORDING')) && !isRecordingDialogVisible) {
          double dur = _coordinator?.currentStudioDurationSec ?? 5.0;
          if (statusMsg.startsWith('RECORDING')) {
            final parts = statusMsg.split(' ');
            if (parts.length >= 2) {
              dur = double.tryParse(parts[1]) ?? dur;
            }
          }
          onShowRecordingDialog?.call(
            label: _coordinator?.currentStudioLabel ?? (_coordinator?.isStudioRecordingActive == true ? 'Activité' : 'Studio'),
            durationSec: dur,
          );
        }
      });

      _bleClient!.burstResultStream.listen((result) {
        addLog(
          'BURST',
          'Réassemblage : ${result.framesRecovered}/${result.totalAnnounced} trames | CRC32 validé : ${result.isCrcValid}',
          color: result.isSuccess ? Colors.green : Colors.red,
        );
        if (_hitlCoordinator.isHitlActive) {
          _hitlCoordinator.attachBurstReadings(result.readings);
        }
      });

      _bleClient!.stepDataStream.listen((stepData) {
        _odometerCoordinator.handleOdometerReading(stepData);
      });

      try {
        unawaited(_inactivitySettingsService.syncToBle(_bleClient!));
      } catch (e) {
        addLog('BLE', 'Erreur sync paramètres inactivité : $e', color: Colors.orange);
      }

      try {
        unawaited(_fallSensitivitySettingsService.syncToBle(_bleClient!));
      } catch (e) {
        addLog('BLE', 'Erreur sync sensibilité chute : $e', color: Colors.orange);
      }

      try {
        _odometerCoordinator.flushSteps();
      } catch (e) {
        addLog('SYNC', 'Erreur synchronisation pas cloud : $e', color: Colors.orange);
      }

      try {
        if (_mqttService != null) {
          _setupCoordinator();
        }
      } catch (e) {
        addLog('GATEWAY', 'Erreur initialisation coordinateur MQTT : $e', color: Colors.orange);
      }
    } catch (e) {
      addLog('BLE', 'Erreur initialisation GATT : $e', color: Colors.red);
    } finally {
      _isInitializingBleClient = false;
    }
  }

  Future<void> sendTestHapticCommand() async {
    final isConnected = _bleClient != null && (_bleStatus == BleConnectionStatus.ready || _bleStatus == BleConnectionStatus.connected) && _bleClient!.hasHaptic;

    if (!isConnected) {
      addLog('HAPTIC', 'Chaussure non connectée : impossible d\'émettre la commande.', color: Colors.red);
      return;
    }

    const command = HapticCommandModel(
      commandId: 'manual-test-vib',
      patternId: 0,
      intensity: 200,
      durationMs: 400,
    );

    try {
      addLog('HAPTIC', 'Écriture sur 0003 (Intensité: ${command.intensity}, Durée: ${command.durationMs} ms)...');
      await _bleClient!.sendHapticCommand(command);
      addLog('HAPTIC', 'Écriture sur 0003 validée avec succès (GATT write OK).', color: Colors.green);
    } catch (e) {
      addLog('HAPTIC', 'Échec écriture sur 0003 : $e', color: Colors.red);
    }
  }

  Future<void> loadLastStudioActivity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = prefs.getString(StudioSessionDialog.prefLastActivityKey);
      final custom = prefs.getString(StudioSessionDialog.prefLastCustomLabel);
      if (key != null && StudioSessionDialog.defaultActivities.any((a) => a.key == key)) {
        _lastStudioActivityKey = key;
        if (custom != null) _lastStudioCustomLabel = custom;
        notifyListeners();
      }
    } catch (_) {}
  }

  void rememberStudioActivity({
    required String activityKey,
    required String customLabel,
  }) {
    _lastStudioActivityKey = activityKey;
    if (activityKey == 'custom') {
      _lastStudioCustomLabel = customLabel;
    }
    notifyListeners();
  }

  Future<void> triggerStudioSession({
    required String label,
    required double durationSec,
  }) async {
    final isConnected =
        _bleClient != null && (_bleStatus == BleConnectionStatus.ready || _bleStatus == BleConnectionStatus.connected) && _bleClient!.hasStudioControl;

    if (!isConnected) {
      addLog('STUDIO', 'Chaussure non connectée ou service Studio indisponible.', color: Colors.red);
      return;
    }

    addLog('STUDIO', 'Démarrage session Studio (${durationSec.toStringAsFixed(1)}s, label: $label)...');

    try {
      if (_mqttService == null) {
        addLog('STUDIO', 'Initialisation et connexion au service MQTT AWS IoT...', color: Colors.indigo);
        await connectMqtt();
      } else if (!_mqttService!.isConnected) {
        addLog('STUDIO', 'Reconnexion au service MQTT AWS IoT...', color: Colors.indigo);
        await _mqttService!.connect();
      }

      _setupCoordinator();

      if (_coordinator != null) {
        addLog('STUDIO', 'Réservation REST de la session auprès du backend FastAPI (/commands/studio/start)...');
        await _coordinator!.triggerStudioSession(
          label: label,
          durationSec: durationSec,
        );
      } else {
        _studioApiService ??= StudioApiService(
          backendBaseUrl: AppConfig.backendBaseUrl,
          tokenStorage: TokenStorageService(),
          authService: authService,
          onLog: (msg, {bool isError = false}) {
            addLog('STUDIO', msg, color: isError ? Colors.red : Colors.green);
          },
        );

        String sessionId;
        try {
          addLog('STUDIO', 'Réservation REST directe auprès du backend FastAPI...');
          final resp = await _studioApiService!.startStudioSession(
            deviceId: deviceId,
            label: label,
            durationSec: durationSec,
          );
          sessionId = resp.sessionId;
          addLog('STUDIO', 'Session réservée : $sessionId', color: Colors.green);
        } catch (e) {
          sessionId = const Uuid().v4();
          addLog('STUDIO', 'Erreur réservation REST ($e), fallback local : $sessionId', color: Colors.orange);
        }

        await _bleClient!.startStudioSession(
          label: label,
          durationSec: durationSec,
          sessionId: sessionId,
        );
      }
      addLog('STUDIO', 'Ordre START envoyé à la chaussure. En attente du flux burst...', color: Colors.indigo);
    } catch (e) {
      addLog('STUDIO', 'Échec lancement session Studio : $e', color: Colors.red);
    }
  }

  Future<void> setHitlActive(bool active) async {
    final activeClient = _bleClientNotifier.value ?? _bleClient;
    await _hitlCoordinator.setHitlActive(active, bleClient: activeClient);
    notifyListeners();
  }

  Future<bool> confirmHitlItem(HitlDetectionItem item) async {
    return _hitlCoordinator.confirmAndPublish(item, deviceId: targetDeviceId);
  }

  Future<void> calibrateSensor() async {
    final activeClient = _bleClientNotifier.value ?? _bleClient;
    if (activeClient != null) {
      addLog('CONFIG', 'Envoi ordre de calibration d\'assiette (CALIBRATE)...');
      await activeClient.sendCalibrateZeroCommand();
      final activeCalib = ActivityDetectionModel(
        stateCode: 0xFD,
        eventType: 'calibration',
        confidencePercent: 100,
        timestampEpochSec: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        isFall: false,
        isHapticTriggered: false,
      );
      _recentActivities.insert(0, activeCalib);
      if (_recentActivities.length > 20) {
        _recentActivities.removeLast();
      }
      notifyListeners();
      _activityStreamController.add(activeCalib);
    }
  }

  void addLog(String tag, String message, {Color? color}) {
    if (_isDisposed) return;
    _logs.add(LogEntry(
      timestamp: DateTime.now(),
      tag: tag,
      message: message,
      color: color ?? _colorForTag(tag),
    ));
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  Color _colorForTag(String tag) {
    switch (tag) {
      case 'UI':
        return Colors.blueGrey;
      case 'BLE':
        return Colors.blue;
      case 'MQTT':
        return Colors.teal;
      case 'CONFIG':
        return Colors.cyan;
      case 'ACTIVITY':
        return Colors.orange;
      case 'FALL_ALERT':
        return Colors.deepOrange;
      case 'BURST':
      case 'CRC32':
        return Colors.purple;
      case 'HAPTIC':
        return Colors.amber;
      case 'STUDIO':
        return Colors.indigo;
      case 'GATEWAY':
        return Colors.green;
      case 'ERROR':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Future<void> flushImmediateSync() async {
    await _odometerCoordinator.syncService.flushImmediateSync(deviceId: deviceId);
  }

  Future<void> disconnectBle() async {
    await _bleManager?.disconnect();
  }

  Future<void> _reportSmsStatusToApi(
    int notificationId,
    bool sent,
    String? errorMessage,
  ) async {
    try {
      final token = await authService?.getValidAccessToken();
      final baseUrl = authService?.backendBaseUrl ?? AppConfig.backendBaseUrl;
      final uri = Uri.parse('$baseUrl/api/v1/fall-alerts/sms-status');
      final headers = buildApiHeaders(token);
      final body = jsonEncode({
        'notification_id': notificationId,
        'sms_status': sent ? 'SENT' : 'FAILED',
        'error_message': errorMessage,
        'sent_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      });
      final res = await http
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        addLog(
          'FALL_ALERT',
          'Statut SMS notif #$notificationId synchronisé avec succès via API REST direct.',
        );
      } else {
        addLog(
          'FALL_ALERT',
          'Réponse API ($baseUrl/api/v1/fall-alerts/sms-status) code ${res.statusCode} pour statut SMS notif #$notificationId',
          color: Colors.orange,
        );
      }
    } catch (e) {
      addLog(
        'FALL_ALERT',
        'Erreur synchronisation API REST statut SMS : $e',
        color: Colors.orange,
      );
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _fallAlertController.removeListener(_onFallAlertUpdated);
    if (_ownsFallAlertController) {
      _fallAlertController.dispose();
    }
    _activityStreamController.close();
    _bleManager?.removeListener(_onBleManagerUpdated);
    if (_isInitialized) {
      _inactivitySettingsService.dispose();
    _fallSensitivitySettingsService.dispose();
      _odometerCoordinator.dispose();
      _surveillanceService.dispose();
    }
    _studioSavedSub?.cancel();
    _remoteStudioCommandSub?.cancel();
    _coordinator?.stopRouting();
    _bleClient?.dispose();
    _bleClient = null;
    _bleClientNotifier.dispose();
    _bleManager?.dispose();
    _mqttService?.disconnect();
    _mqttConnectedNotifier.dispose();
    super.dispose();
  }
}
