import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/api/api_headers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../core/config/app_config.dart';
import '../core/permissions/permission_service.dart';
import '../models/activity_detection_model.dart';
import '../models/firmware_release_model.dart';
import '../models/haptic_command_model.dart';
import '../models/log_entry_model.dart';
import '../models/step_data_model.dart';
import '../models/studio_command_model.dart';
import '../models/studio_session_model.dart';
import '../services/auth/auth_service.dart';
import '../services/background_surveillance_service.dart';
import '../services/ble/ble_connection_manager.dart';
import '../services/ble/ble_footwear_client.dart';
import '../services/fall_sensitivity_settings_service.dart';
import '../services/firmware/firmware_service.dart';
import '../services/gateway_coordinator.dart';
import '../services/inactivity_settings_service.dart';
import '../services/local_storage/step_storage_service.dart';
import '../services/mqtt/mqtt_gateway_service.dart';
import '../services/step_sync_service.dart';
import '../services/studio/studio_api_service.dart';
import '../ui/widgets/studio_session_dialog.dart';
import 'dashboard_ble_coordinator.dart';
import 'dashboard_firmware_coordinator.dart';
import 'dashboard_mqtt_coordinator.dart';
import 'dashboard_odometer_coordinator.dart';
import 'dashboard_studio_coordinator.dart';
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
  late final DashboardFirmwareCoordinator _firmwareCoordinator;
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

  late final DashboardBleCoordinator _bleCoordinator;
  late final DashboardStudioCoordinator _studioCoordinator;
  late final DashboardMqttCoordinator _mqttCoordinator;
  GatewayCoordinator? _coordinator;
  StreamSubscription<StudioSessionModel>? _studioSavedSub;
  StreamSubscription<StudioCommandModel>? _remoteStudioCommandSub;

  bool _isUserSeated = false;
  bool _isInitializingBleClient = false;
  final List<ActivityDetectionModel> _recentActivities = [];
  final StreamController<ActivityDetectionModel> _activityStreamController = StreamController<ActivityDetectionModel>.broadcast();
  DateTime? _lastInactivityToastTime;
  bool isRecordingDialogVisible = false;
  bool _isSensorCalibrated = false;
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
    DashboardBleCoordinator? bleCoordinator,
    DashboardStudioCoordinator? studioCoordinator,
    DashboardFirmwareCoordinator? firmwareCoordinator,
    DashboardMqttCoordinator? mqttCoordinator,
    this.onShowSnackBar,
    this.onDismissSnackBar,
    this.onShowRecordingDialog,
    this.onPermissionDeniedAction,
  })  : _audioFeedbackService = audioFeedbackService ?? StudioAudioFeedbackService(),
        _inactivitySettingsService = inactivitySettingsService ?? InactivitySettingsService(),
        _fallSensitivitySettingsService = fallSensitivitySettingsService ?? FallSensitivitySettingsService(),
        _ownsFallAlertController = fallAlertController == null {
    _firmwareCoordinator = firmwareCoordinator ??
        DashboardFirmwareCoordinator(
          firmwareService: firmwareService,
          authService: authService,
        );
    _mqttCoordinator = mqttCoordinator ??
        DashboardMqttCoordinator(
          deviceId: deviceId,
          authService: authService,
        );
    _bleCoordinator = bleCoordinator ??
        DashboardBleCoordinator(
          targetDeviceId: targetDeviceId,
          permissionService: _permissionService,
          onLog: (tag, msg, {Color? color}) => addLog(tag, msg, color: color),
          onStateUpdated: () {
            if (!_isDisposed) notifyListeners();
          },
          onStatusChanged: (status, device) {
            _surveillanceService.onBleStatusChanged(
              status,
              deviceName: device?.platformName ?? targetDeviceId,
            );
          },
          onDeviceReady: (device) => unawaited(onBleDeviceReady(device)),
          onDeviceDisconnected: () {
            setSensorCalibrated(false);
            _studioSavedSub?.cancel();
            if (_coordinator != null) {
              _coordinator?.stopRouting();
              _coordinator = null;
            } else {
              _mqttCoordinator.publishGatewayStatus(online: false);
            }
            if (_bleCoordinator.status == BleConnectionStatus.disconnected) {
              _odometerCoordinator.flushSteps();
            }
          },
        );
    _studioCoordinator = studioCoordinator ??
        DashboardStudioCoordinator(
          deviceId: deviceId,
          authService: authService,
          onLog: (tag, msg, {Color? color}) => addLog(tag, msg, color: color),
          onStateUpdated: () {
            if (!_isDisposed) notifyListeners();
          },
          onEnsureMqttConnected: () async {
            if (_mqttCoordinator.mqttService == null) {
              addLog('STUDIO', 'Initialisation et connexion au service MQTT AWS IoT...', color: Colors.indigo);
              await connectMqtt();
            } else if (!_mqttCoordinator.mqttService!.isConnected) {
              addLog('STUDIO', 'Reconnexion au service MQTT AWS IoT...', color: Colors.indigo);
              await _mqttCoordinator.mqttService!.connect();
            }
          },
          getCoordinator: () => _coordinator,
          onSetupCoordinator: _setupCoordinator,
          getBleClient: () => _bleCoordinator.bleClient,
          getBleStatus: () => _bleCoordinator.status,
          getIsSensorCalibrated: () => _isSensorCalibrated,
        );
    _hitlCoordinator = hitlCoordinator ??
        HitlCoordinator(
          mqttService: _mqttCoordinator.mqttService,
          studioApiService: _studioCoordinator.studioApiService,
          onLog: (msg, {bool isError = false}) {
            addLog('HITL', msg, color: isError ? Colors.red : Colors.teal);
          },
        );
    _hitlCoordinator.addListener(notifyListeners);
    _fallAlertController = fallAlertController ??
        FallAlertController(
          deviceId: deviceId,
          isMqttConnectedGetter: () => _mqttCoordinator.isMqttConnected || (_mqttCoordinator.mqttService?.isConnected ?? false),
          onLog: (tag, msg, {bool isError = false}) {
            addLog(tag, msg, color: isError ? Colors.red : Colors.deepOrange);
          },
          onSmsStatusReported: _reportSmsStatusToApi,
        );
    _fallAlertController.addListener(_onFallAlertUpdated);
  }

  // Getters
  FallAlertController get fallAlertController => _fallAlertController;
  DashboardBleCoordinator get bleCoordinator => _bleCoordinator;
  BleConnectionStatus get bleStatus => _bleCoordinator.status;
  Stream<BleConnectionStatus>? get bleStatusStream => _bleCoordinator.statusStream;
  BluetoothDevice? get connectedDevice => _bleCoordinator.connectedDevice;
  int get mtu => _bleCoordinator.mtu;
  bool get isMqttConnected => _mqttCoordinator.isMqttConnected;
  ValueNotifier<bool> get mqttConnectedNotifier => _mqttCoordinator.mqttConnectedNotifier;
  DashboardMqttCoordinator get mqttCoordinator => _mqttCoordinator;
  MqttGatewayService? get mqttService => _mqttCoordinator.mqttService;
  BleConnectionManager? get bleManager => _bleCoordinator.bleManager;
  BleFootwearClient? get bleClient => _bleCoordinator.bleClient;
  ValueNotifier<BleFootwearClient?> get bleClientNotifier => _bleCoordinator.bleClientNotifier;
  StepDataModel? get latestStepData => _odometerCoordinator.latestStepData;
  List<ActivityDetectionModel> get recentActivities => List.unmodifiable(_recentActivities);
  Stream<ActivityDetectionModel> get activityStream => _activityStreamController.stream;
  List<LogEntry> get logs => _logs;
  DashboardStudioCoordinator get studioCoordinator => _studioCoordinator;
  String get lastStudioActivityKey => _studioCoordinator.lastStudioActivityKey;
  String get lastStudioCustomLabel => _studioCoordinator.lastStudioCustomLabel;
  bool get isSensorCalibrated => _isSensorCalibrated;
  bool get isBleConnected =>
      _bleCoordinator.bleClient != null &&
      (_bleCoordinator.status == BleConnectionStatus.ready ||
          _bleCoordinator.status == BleConnectionStatus.connected);

  void setSensorCalibrated(bool calibrated) {
    if (_isSensorCalibrated != calibrated) {
      _isSensorCalibrated = calibrated;
      notifyListeners();
    }
  }


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
      _handleInactivityAlert(detection);
      return;
    }

    _recordRecentActivity(detection);

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

  void _handleInactivityAlert(ActivityDetectionModel detection) {
    final now = DateTime.now();
    if (_lastInactivityToastTime == null ||
        now.difference(_lastInactivityToastTime!).inSeconds >= 30) {
      _lastInactivityToastTime = now;
      onShowSnackBar?.call(
        _inactivitySettingsService.inactivityAlertMessage(isSeated: _isUserSeated),
        backgroundColor: Colors.deepOrange.shade700,
      );
    }
  }

  void _recordRecentActivity(ActivityDetectionModel detection) {
    _recentActivities.insert(0, detection);
    if (_recentActivities.length > 20) {
      _recentActivities.removeLast();
    }
    notifyListeners();
    _activityStreamController.add(detection);
  }

  GatewayCoordinator? get coordinator => _coordinator;
  FirmwareService get firmwareService => _firmwareCoordinator.firmwareService;
  DashboardFirmwareCoordinator get firmwareCoordinator => _firmwareCoordinator;
  FirmwareReleaseModel? get latestFirmwareRelease => _firmwareCoordinator.latestFirmwareRelease;
  String? get installedFirmwareVersion => _firmwareCoordinator.installedFirmwareVersion;
  DateTime? get installedFirmwareDate => _firmwareCoordinator.installedFirmwareDate;
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
    unawaited(_studioCoordinator.loadLastStudioActivity());

    _bleCoordinator.ensureBleManager();
    _initGateway();
  }

  Future<void> checkForFirmwareUpdate() async {
    await _firmwareCoordinator.checkForFirmwareUpdate(
      addLog: addLog,
      onShowSnackBar: onShowSnackBar,
    );
  }

  void setForegroundState(bool isForeground) {
    _odometerCoordinator.setForegroundState(isForeground);
  }

  void flushSteps() {
    _odometerCoordinator.flushSteps();
  }

  Future<void> _initGateway() async {
    addLog('INIT', 'Démarrage de la passerelle HealthKicks...');
    _bleCoordinator.ensureBleManager();
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
    if (_coordinator != null) {
      _coordinator?.stopRouting(notifyOffline: true);
      _coordinator = null;
    } else {
      _mqttCoordinator.publishDeviceStatus(online: false);
    }
    await _bleCoordinator.startAutoConnect(fromButton: fromButton);
  }

  Future<void> connectMqtt() async {
    await _mqttCoordinator.connectMqtt(
      addLog: addLog,
      onMqttStateChanged: (connected) {
        _fallAlertController.setMqttConnected(connected);
        if (!_isDisposed) notifyListeners();
      },
      onConnectionRestored: () async {
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

        if (isBleConnected) {
          addLog('GATEWAY', 'Reconnexion MQTT : re-synchronisation du statut BLE online...', color: Colors.green);
          _coordinator?.publishBleStatus(online: true);
        }
      },
      isBleConnectedGetter: () => isBleConnected,
      onBleOnlineSync: () async {
        if (_coordinator == null) {
          _setupCoordinator();
        } else {
          addLog('GATEWAY', 'MQTT connecté : synchronisation immédiate de la présence BLE online...', color: Colors.green);
          await _coordinator!.publishBleStatus(online: true);
        }
      },
    );
    _fallAlertController.attachMqttService(_mqttCoordinator.mqttService);
  }

  void _setupCoordinator() {
    final client = _bleCoordinator.bleClient;
    final mqtt = _mqttCoordinator.mqttService;
    if (client == null || mqtt == null) return;

    _coordinator?.stopRouting(notifyOffline: false);
    _studioSavedSub?.cancel();
    _remoteStudioCommandSub?.cancel();

    _hitlCoordinator.updateServices(
      mqttService: mqtt,
      studioApiService: _studioCoordinator.studioApiService,
    );

    _coordinator = GatewayCoordinator(
      bleClient: client,
      mqttService: mqtt,
      studioApiService: _studioCoordinator.studioApiService,
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
    final currentClient = _bleCoordinator.bleClient;
    if (currentClient != null && currentClient.device.remoteId == device.remoteId && currentClient.isReady) {
      return;
    }
    _isInitializingBleClient = true;

    addLog('BLE', 'Appareil connecté : ${device.platformName} (MTU: ${_bleCoordinator.mtu} octets)');

    try {
      setSensorCalibrated(false);
      final newClient = BleFootwearClient(
        device: device,
        onLog: (msg, {bool isError = false}) {
          addLog('BLE', msg, color: isError ? Colors.red : Colors.blueGrey);
        },
      );
      addLog('BLE', 'Découverte des services GATT en cours...');
      await newClient.initializeServices();
      _bleCoordinator.bleClient = newClient;
      notifyListeners();

      addLog(
        'BLE',
        'Souscription active : Activity (0002), Studio Control (0004), Burst (0005) | Haptique (0003) ${newClient.hasHaptic ? "prêt" : "non trouvé"}',
      );

      _firmwareCoordinator.syncConnectedDeviceFirmware(
        device: device,
        client: newClient,
        addLog: addLog,
        onShowSnackBar: onShowSnackBar,
      );

      newClient.activityStream.listen(handleActivityDetection);

      newClient.studioStatusStream.listen((statusMsg) {
        addLog('STUDIO', 'Signal d\'état : $statusMsg');
        if (statusMsg.contains('CALIBRATION_OK')) {
          setSensorCalibrated(true);
        } else if (statusMsg.contains('CALIBRATION_ERROR')) {
          setSensorCalibrated(false);
        }
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

      newClient.burstResultStream.listen((result) {
        addLog(
          'BURST',
          'Réassemblage : ${result.framesRecovered}/${result.totalAnnounced} trames | CRC32 validé : ${result.isCrcValid}',
          color: result.isSuccess ? Colors.green : Colors.red,
        );
        if (_hitlCoordinator.isHitlActive) {
          _hitlCoordinator.attachBurstReadings(result.readings);
        }
      });

      newClient.stepDataStream.listen((stepData) {
        _odometerCoordinator.handleOdometerReading(stepData);
      });

      try {
        unawaited(_inactivitySettingsService.syncToBle(newClient));
      } catch (e) {
        addLog('BLE', 'Erreur sync paramètres inactivité : $e', color: Colors.orange);
      }

      try {
        unawaited(_fallSensitivitySettingsService.syncToBle(newClient));
      } catch (e) {
        addLog('BLE', 'Erreur sync seuil confiance chute : $e', color: Colors.orange);
      }

      try {
        _odometerCoordinator.flushSteps();
      } catch (e) {
        addLog('SYNC', 'Erreur synchronisation pas cloud : $e', color: Colors.orange);
      }

      try {
        if (_mqttCoordinator.mqttService != null) {
          _setupCoordinator();
        }
      } catch (e) {
        addLog('GATEWAY', 'Erreur initialisation coordinateur MQTT : $e', color: Colors.orange);
      }
    } catch (e) {
      addLog('BLE', 'Erreur initialisation client footwear : $e', color: Colors.red);
      _bleCoordinator.bleClient = null;
    } finally {
      _isInitializingBleClient = false;
    }
  }

  Future<void> sendTestHapticCommand() async {
    final client = _bleCoordinator.bleClient;
    final isConnected = client != null &&
        (_bleCoordinator.status == BleConnectionStatus.ready ||
            _bleCoordinator.status == BleConnectionStatus.connected) &&
        client.hasHaptic;

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
      await client.sendHapticCommand(command);
      addLog('HAPTIC', 'Écriture sur 0003 validée avec succès (GATT write OK).', color: Colors.green);
    } catch (e) {
      addLog('HAPTIC', 'Échec écriture sur 0003 : $e', color: Colors.red);
    }
  }

  Future<void> loadLastStudioActivity() => _studioCoordinator.loadLastStudioActivity();

  void rememberStudioActivity({
    required String activityKey,
    required String customLabel,
  }) => _studioCoordinator.rememberStudioActivity(
    activityKey: activityKey,
    customLabel: customLabel,
  );

  Future<StudioDatasetStats?> fetchStudioStats() => _studioCoordinator.fetchStudioStats();

  Future<bool> triggerStudioSession({
    required String label,
    required double durationSec,
  }) => _studioCoordinator.triggerStudioSession(
    label: label,
    durationSec: durationSec,
  );

  Future<void> setHitlActive(bool active) async {
    final activeClient = _bleCoordinator.bleClientNotifier.value ?? _bleCoordinator.bleClient;
    if (active) {
      _recentActivities.clear();
    }
    await _hitlCoordinator.setHitlActive(active, bleClient: activeClient);
    notifyListeners();
  }

  void clearRecentActivities() {
    _recentActivities.clear();
    notifyListeners();
  }

  Future<bool> confirmHitlItem(HitlDetectionItem item) async {
    return _hitlCoordinator.confirmAndPublish(item, deviceId: deviceId);
  }

  Future<void> calibrateSensor() async {
    final activeClient = _bleCoordinator.bleClientNotifier.value ?? _bleCoordinator.bleClient;
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
    await _bleCoordinator.disconnect();
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
      final headers = buildApiHeaders(
        token,
        method: 'POST',
        path: '/api/v1/fall-alerts/sms-status',
      );
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
    _bleCoordinator.dispose();
    _firmwareCoordinator.dispose();
    if (_isInitialized) {
      _inactivitySettingsService.dispose();
      _odometerCoordinator.dispose();
      _surveillanceService.dispose();
    }
    setSensorCalibrated(false);
    _studioSavedSub?.cancel();
    _remoteStudioCommandSub?.cancel();
    _coordinator?.stopRouting();
    _mqttCoordinator.dispose();
    super.dispose();
  }
}
