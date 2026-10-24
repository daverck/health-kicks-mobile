import 'dart:async';
import 'package:flutter/material.dart';

import '../../controllers/gateway_dashboard_controller.dart';
import '../../core/config/app_config.dart';
import '../../core/permissions/permission_service.dart';
import '../../screens/fall_alert_screen.dart';
import '../../services/auth/auth_service.dart';
import '../../services/auth/token_storage_service.dart';
import '../../services/ble/ble_connection_manager.dart';
import '../../services/event_history_service.dart';
import '../../services/locale_service.dart';
import '../../services/theme_service.dart';
import '../widgets/dashboard/dashboard_app_bar.dart';
import '../widgets/dashboard/dashboard_quick_actions.dart';
import '../widgets/gateway_status_row.dart';
import '../widgets/recent_activities_card.dart';
import '../widgets/step_counter_card.dart';
import '../widgets/studio_recording_dialog.dart';
import '../widgets/studio_session_dialog.dart';
import 'detection_events_history_screen.dart';
import 'event_logs_screen.dart';
import 'settings_screen.dart';
import 'steps_history_screen.dart';

/// Primary dashboard screen orchestrating the BLE-MQTT mobile edge gateway.
///
/// Responsibilities:
/// - **BLE Footwear Connection**: Scans, auto-reconnects, and consumes GATT telemetry from the ESP32-S3 shoe.
/// - **Cloud MQTT Synchronization**: Relays sensor events and IMU frames over AWS IoT Core WebSockets SigV4.
/// - **Fall Alerting**: Displays full-screen emergency overlay upon live fall detection and coordinates status updates.
/// - **Studio & Calibration**: Triggers IMU calibration and biomechanical motion capture sessions.
/// - **Step Counter & Odometer**: Computes daily steps via differential monotonic odometer storage.
/// - **Background Surveillance**: Coordinates foreground/background life cycle state across app transitions.
class GatewayDashboardScreen extends StatefulWidget {
  final AuthService? authService;
  final ThemeService? themeService;
  final LocaleService? localeService;
  final VoidCallback? onLogout;
  final GatewayDashboardController? controller;

  const GatewayDashboardScreen({
    super.key,
    this.authService,
    this.themeService,
    this.localeService,
    this.onLogout,
    this.controller,
  });

  @override
  State<GatewayDashboardScreen> createState() => _GatewayDashboardScreenState();
}

class _GatewayDashboardScreenState extends State<GatewayDashboardScreen> with WidgetsBindingObserver {
  final PermissionService _permissionService = PermissionService();
  late final GatewayDashboardController _controller;
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _ownsController = true;
      _controller = GatewayDashboardController(
        authService: widget.authService,
        onShowSnackBar: (msg, {backgroundColor}) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: backgroundColor,
            ),
          );
        },
        onShowRecordingDialog: ({required label, required durationSec}) {
          _showActiveRecordingDialog(label: label, durationSec: durationSec);
        },
        onPermissionDeniedAction: () {
          _permissionService.openSettings();
        },
      );
      _controller.initialize();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final isForeground = state == AppLifecycleState.resumed;
    _controller.setForegroundState(isForeground);

    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      unawaited(_controller.flushImmediateSync());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _showActiveRecordingDialog({
    required String label,
    required double durationSec,
  }) {
    if (_controller.isRecordingDialogVisible || !mounted || _controller.bleClient == null) return;
    _controller.isRecordingDialogVisible = true;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StudioRecordingDialog(
        label: label,
        durationSec: durationSec,
        studioStatusStream: _controller.bleClient!.studioStatusStream,
        sessionSavedStream: _controller.coordinator?.studioSessionSavedStream,
        connectionStatusStream: _controller.bleStatusStream,
        onCancel: () async {
          try {
            await _controller.bleClient?.cancelStudioSession();
          } catch (_) {}
        },
        onFinish: () async {
          await _controller.bleClient?.finishStudioSession();
        },
      ),
    ).then((_) {
      _controller.isRecordingDialogVisible = false;
    });
  }

  void _showStudioSessionDialog() {
    final isConnected = _controller.bleClient != null &&
        (_controller.bleStatus == BleConnectionStatus.ready || _controller.bleStatus == BleConnectionStatus.connected) &&
        _controller.bleClient!.hasStudioControl;

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => StudioSessionDialog(
        initialActivityKey: _controller.lastStudioActivityKey,
        initialCustomLabel: _controller.lastStudioCustomLabel,
        onActivitySaved: ({
          required String activityKey,
          required String customLabel,
        }) =>
            _controller.rememberStudioActivity(
          activityKey: activityKey,
          customLabel: customLabel,
        ),
        onStartSession: ({required String label, required double durationSec}) async {
          // Note: StudioSessionDialog._onConfirm already popped itself, so do not pop dialogCtx here.
          if (!isConnected) {
            _controller.addLog('STUDIO', 'Chaussure non connectée ou service Studio indisponible.', color: Colors.red);
            return;
          }
          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            _showActiveRecordingDialog(label: label, durationSec: durationSec);
          }
          try {
            await _controller.triggerStudioSession(label: label, durationSec: durationSec);
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
            }
          }
        },
      ),
    );
  }

  void _openEventLogsScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventLogsScreen(
          logs: _controller.logs,
          onClearLogs: () => setState(() => _controller.logs.clear()),
          deviceId: _controller.deviceId,
          deviceName: _controller.connectedDevice?.platformName.isNotEmpty == true ? _controller.connectedDevice!.platformName : _controller.targetDeviceId,
          bleStatus: _controller.bleStatus.name,
          mtu: _controller.mtu,
          mqttConnected: _controller.isMqttConnected,
        ),
      ),
    );
  }

  void _openStepsHistoryScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StepsHistoryScreen(
          storageService: _controller.stepStorageService,
          syncService: _controller.stepSyncService,
          deviceId: _controller.deviceId,
        ),
      ),
    );
  }

  void _openDetectionEventsHistoryScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetectionEventsHistoryScreen(
          service: EventHistoryService(
            backendBaseUrl: AppConfig.backendBaseUrl,
            tokenStorage: TokenStorageService(),
            authService: widget.authService,
          ),
          deviceId: _controller.deviceId,
          liveActivities: _controller.recentActivities,
          activityStream: _controller.activityStream,
        ),
      ),
    );
  }

  void _openSettingsScreen() {
    final isConnected =
        _controller.bleClient != null && (_controller.bleStatus == BleConnectionStatus.ready || _controller.bleStatus == BleConnectionStatus.connected);

    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          authService: widget.authService,
          surveillanceService: _controller.surveillanceService,
          inactivitySettingsService: _controller.inactivitySettingsService,
          themeService: widget.themeService,
          localeService: widget.localeService,
          firmwareService: _controller.firmwareService,
          bleManager: _controller.bleManager,
          bleClient: _controller.bleClient,
          bleClientNotifier: _controller.bleClientNotifier,
          isFootwearConnected: isConnected,
          studioStatusStream: _controller.bleClient?.studioStatusStream,
          bleStatus: _controller.bleStatus,
          isMqttConnected: _controller.isMqttConnected,
          isMqttConnectedNotifier: _controller.mqttConnectedNotifier,
          deviceName: _controller.connectedDevice?.platformName,
          targetDeviceId: _controller.targetDeviceId,
          mtu: _controller.mtu,
          onStartBleScan: () => _controller.startBleScan(fromButton: true),
          onDisconnectBle: () async {
            await _controller.disconnectBle();
          },
          onReconnectMqtt: _controller.connectMqtt,
          onCalibrateSensor: _controller.calibrateSensor,
          onOpenEventLogs: _openEventLogsScreen,
        ),
      ),
    )
        .then((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final listenables = <Listenable>[_controller, _controller.fallAlertController];
    if (widget.authService != null) {
      listenables.add(widget.authService!);
    }

    return ListenableBuilder(
      listenable: Listenable.merge(listenables),
      builder: (context, _) {
        final role = widget.authService?.currentUser?.role;
        final isClinicianOrAdmin = role == 'admin' || role == 'clinician';
        final showFallOverlay = _controller.fallAlertController.isAlertScreenVisible;

        return Stack(
          children: [
            Scaffold(
              appBar: DashboardAppBar(
                onOpenSettings: _openSettingsScreen,
                onLogout: widget.onLogout,
              ),
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1. Discreet Status Indicators (Tappable to Settings)
                      GatewayStatusRow(
                        deviceId: _controller.deviceId,
                        bleStatus: _controller.bleStatus,
                        bleClient: _controller.bleClient,
                        connectedDevice: _controller.connectedDevice,
                        targetDeviceId: _controller.targetDeviceId,
                        mtu: _controller.mtu,
                        isMqttConnected: _controller.isMqttConnected,
                        awsRegion: AppConfig.awsRegion,
                        onTapSettings: _openSettingsScreen,
                      ),
                      const SizedBox(height: 10),

                      // 2. Step Counter Card
                      StepCounterCard(
                        stepData: _controller.latestStepData,
                        onOpenHistory: _openStepsHistoryScreen,
                      ),
                      const SizedBox(height: 10),

                      // 3. Recent Activities History Card
                      RecentActivitiesCard(
                        activities: _controller.recentActivities,
                        onViewAll: _openDetectionEventsHistoryScreen,
                      ),
                      const SizedBox(height: 10),

                      // 4. Action Test Controls
                      DashboardQuickActions(
                        onSendTestHaptic: _controller.sendTestHapticCommand,
                        isClinicianOrAdmin: isClinicianOrAdmin,
                        onOpenStudio: _showStudioSessionDialog,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (showFallOverlay)
              Positioned.fill(
                child: FallAlertScreen(
                  controller: _controller.fallAlertController,
                ),
              ),
          ],
        );
      },
    );
  }
}
