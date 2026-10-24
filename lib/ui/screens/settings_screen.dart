import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/localization/app_language.dart';
import '../../core/localization/app_localizations.dart';
import '../../services/auth/auth_service.dart';
import '../../services/background_surveillance_service.dart';
import '../../services/inactivity_settings_service.dart';
import '../../services/fall_sensitivity_settings_service.dart';
import '../../services/ble/ble_connection_manager.dart';
import '../../services/ble/ble_footwear_client.dart';
import '../../services/locale_service.dart';
import '../../services/theme_service.dart';
import '../../services/firmware/firmware_service.dart';
import '../../services/integrations/health_connect_service.dart';
import '../widgets/imu_calibration_dialog.dart';
import '../widgets/settings/settings_connection_status_card.dart';
import '../widgets/settings/settings_biomechanics_section.dart';
import '../widgets/settings/settings_account_section.dart';
import '../widgets/settings/settings_system_info_section.dart';
import 'firmware_update_screen.dart';

/// Screen allowing the user to configure mobile gateway settings,
/// BLE/MQTT connectivity actions, background surveillance, inactivity reminders, appearance/theme, language/region, and tilt calibration.
class SettingsScreen extends StatefulWidget {
  final AuthService? authService;
  final BackgroundSurveillanceService surveillanceService;
  final InactivitySettingsService? inactivitySettingsService;
  final FallSensitivitySettingsService? fallSensitivitySettingsService;
  final ThemeService? themeService;
  final LocaleService? localeService;
  final FirmwareService? firmwareService;
  final HealthConnectService? healthConnectService;
  final BleFootwearClient? bleClient;
  final ValueNotifier<BleFootwearClient?>? bleClientNotifier;
  final Future<void> Function()? onCalibrateSensor;
  final bool isFootwearConnected;
  final Stream<String>? studioStatusStream;

  final BleConnectionManager? bleManager;
  final Future<void> Function()? onStartBleScan;
  final Future<void> Function()? onDisconnectBle;
  final Future<void> Function()? onReconnectMqtt;
  final VoidCallback? onOpenEventLogs;
  final BleConnectionStatus bleStatus;
  final bool isMqttConnected;
  final ValueNotifier<bool>? isMqttConnectedNotifier;
  final String? deviceName;
  final String? targetDeviceId;
  final int mtu;

  const SettingsScreen({
    super.key,
    this.authService,
    required this.surveillanceService,
    this.inactivitySettingsService,
    this.fallSensitivitySettingsService,
    this.themeService,
    this.localeService,
    this.firmwareService,
    this.healthConnectService,
    this.bleManager,
    this.bleClient,
    this.bleClientNotifier,
    this.onCalibrateSensor,
    this.isFootwearConnected = false,
    this.studioStatusStream,
    this.onStartBleScan,
    this.onDisconnectBle,
    this.onReconnectMqtt,
    this.onOpenEventLogs,
    this.bleStatus = BleConnectionStatus.disconnected,
    this.isMqttConnected = false,
    this.isMqttConnectedNotifier,
    this.deviceName,
    this.targetDeviceId,
    this.mtu = 23,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final InactivitySettingsService _inactivityService;
  bool _ownsInactivityService = false;
  late final FallSensitivitySettingsService _fallSensitivityService;
  bool _ownsFallSensitivityService = false;
  late final ThemeService _themeService;
  bool _ownsThemeService = false;
  late final LocaleService _localeService;
  bool _ownsLocaleService = false;
  late final HealthConnectService _healthConnectService;

  late final FirmwareService _firmwareService;
  String? _installedFirmwareVersion;
  DateTime? _installedFirmwareDate;

  bool _isLocallyDisconnected = false;
  BleConnectionStatus? _previousBleStatus;

  @override
  void initState() {
    super.initState();
    _firmwareService = widget.firmwareService ?? FirmwareService();
    unawaited(_loadFirmwareInfo());

    if (widget.inactivitySettingsService != null) {
      _inactivityService = widget.inactivitySettingsService!;
    } else {
      _inactivityService = InactivitySettingsService();
      _ownsInactivityService = true;
      unawaited(_inactivityService.loadSettings());
    }

    if (widget.fallSensitivitySettingsService != null) {
      _fallSensitivityService = widget.fallSensitivitySettingsService!;
    } else {
      _fallSensitivityService = FallSensitivitySettingsService();
      _ownsFallSensitivityService = true;
      unawaited(_fallSensitivityService.loadSettings());
    }

    if (widget.themeService != null) {
      _themeService = widget.themeService!;
    } else {
      _themeService = ThemeService();
      _ownsThemeService = true;
      unawaited(_themeService.loadTheme());
    }

    if (widget.localeService != null) {
      _localeService = widget.localeService!;
    } else {
      _localeService = LocaleService();
      _ownsLocaleService = true;
      unawaited(_localeService.loadLocale());
    }

    _healthConnectService = widget.healthConnectService ?? HealthConnectService();
    unawaited(_healthConnectService.init());
  }

  Future<void> _loadFirmwareInfo() async {
    try {
      final savedVer = await _firmwareService.getLocalInstalledVersion();
      final savedDate = await _firmwareService.getLocalInstalledDate();
      if (mounted) {
        setState(() {
          _installedFirmwareVersion = savedVer;
          _installedFirmwareDate = savedDate;
        });
      }

      final activeClient = widget.bleClientNotifier?.value ?? widget.bleClient;
      if (activeClient?.firmwareVersion != null && activeClient!.firmwareVersion!.isNotEmpty) {
        if (mounted) {
          setState(() {
            _installedFirmwareVersion = activeClient.firmwareVersion;
            if (activeClient.firmwareBuildDate != null) {
              _installedFirmwareDate = activeClient.firmwareBuildDate;
            }
          });
        }
        return;
      }

      final activeDevice = activeClient?.device ?? widget.bleManager?.connectedDevice;
      if (activeDevice != null) {
        final info = await _firmwareService.readDeviceFirmwareInfo(activeDevice);
        if (info.version != null && info.version!.isNotEmpty) {
          if (mounted) {
            setState(() {
              _installedFirmwareVersion = info.version;
              if (info.buildDate != null) {
                _installedFirmwareDate = info.buildDate;
              }
            });
          }
          await _firmwareService.saveLocalInstalledFirmware(
            installedDate: info.buildDate ?? _installedFirmwareDate ?? DateTime.now().toUtc(),
            version: info.version!,
          );
        }
      }
    } catch (_) {}
  }

  String _formatFirmwareDate(DateTime? dt) {
    if (dt == null) return '';
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year;
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min';
  }

  String _getFirmwareSubtitle(bool isConnected) {
    if (_installedFirmwareVersion != null && _installedFirmwareVersion!.isNotEmpty) {
      final dateSuffix = _installedFirmwareDate != null ? ' (${_formatFirmwareDate(_installedFirmwareDate)})' : '';
      final stateSuffix = isConnected ? ' (Connecté)' : ' (Dernière version mémorisée)';
      return '$_installedFirmwareVersion$dateSuffix$stateSuffix';
    }
    return isConnected ? 'Lecture de la version en cours...' : 'Non disponible (connectez la chaussure)';
  }

  void _openFirmwareUpdateScreen() {
    final activeDevice = widget.bleClient?.device ?? widget.bleManager?.connectedDevice;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FirmwareUpdateScreen(
          device: activeDevice,
          currentFirmwareVersion: _installedFirmwareVersion ?? 'v1.2.0-esp32s3',
          firmwareService: _firmwareService,
          authService: widget.authService,
          bleManager: widget.bleManager,
          targetDeviceId: widget.targetDeviceId,
          onReconnect: widget.onStartBleScan,
        ),
      ),
    ).then((_) {
      if (mounted) {
        _loadFirmwareInfo();
      }
    });
  }

  @override
  void dispose() {
    if (_ownsInactivityService) {
      _inactivityService.dispose();
    }
    if (_ownsFallSensitivityService) {
      _fallSensitivityService.dispose();
    }
    if (_ownsThemeService) {
      _themeService.dispose();
    }
    if (_ownsLocaleService) {
      _localeService.dispose();
    }
    super.dispose();
  }

  void _showCalibrationDialog(BuildContext context, bool isConnected) {
    final activeBleClient = widget.bleClientNotifier?.value ?? widget.bleClient;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ImuCalibrationDialog(
        onCalibrate: activeBleClient != null
            ? activeBleClient.sendCalibrateZeroCommand
            : widget.onCalibrateSensor,
        isConnected: isConnected,
        studioStatusStream: activeBleClient?.studioStatusStream ?? widget.studioStatusStream,
      ),
    );
  }

  void _showLanguageSelector(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.language_rounded,
                      size: 24,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      l10n.languageTitle,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.languageDesc,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                ...AppLanguage.supported.map((lang) {
                  final isSelected = _localeService.currentLanguage.code == lang.code;
                  return ListTile(
                    leading: Text(lang.flag, style: const TextStyle(fontSize: 24)),
                    title: Text(
                      lang.nativeName,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(lang.name),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle_rounded, color: Colors.teal)
                        : null,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    selected: isSelected,
                    selectedTileColor:
                        Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    onTap: () {
                      _localeService.setLanguageCode(lang.code);
                      Navigator.of(modalContext).pop();
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          widget.surveillanceService,
          _inactivityService,
          if (widget.bleManager != null) widget.bleManager!,
          if (widget.bleClientNotifier != null) widget.bleClientNotifier!,
          if (widget.isMqttConnectedNotifier != null) widget.isMqttConnectedNotifier!,
        ]),
        builder: (context, _) {
          final currentBleStatus = widget.bleManager?.status ?? widget.bleStatus;
          if ((currentBleStatus == BleConnectionStatus.ready ||
                  currentBleStatus == BleConnectionStatus.connected) &&
              (_previousBleStatus != null &&
                  _previousBleStatus != BleConnectionStatus.ready &&
                  _previousBleStatus != BleConnectionStatus.connected)) {
            _isLocallyDisconnected = false;
          }
          _previousBleStatus = currentBleStatus;

          final isBleReady = !_isLocallyDisconnected &&
              (widget.bleManager != null
                  ? (currentBleStatus == BleConnectionStatus.ready ||
                      currentBleStatus == BleConnectionStatus.connected)
                  : (widget.isFootwearConnected ||
                      currentBleStatus == BleConnectionStatus.ready ||
                      currentBleStatus == BleConnectionStatus.connected));

          final isBleScanning = !_isLocallyDisconnected && currentBleStatus == BleConnectionStatus.scanning;
          final isBleConnecting = !_isLocallyDisconnected && currentBleStatus == BleConnectionStatus.connecting;
          final activeBleClient = widget.bleClientNotifier?.value ?? widget.bleClient;

          final currentMtu = widget.bleManager?.negotiatedMtu ?? widget.mtu;
          final String currentDeviceName = widget.bleManager?.connectedDevice?.platformName.isNotEmpty == true
              ? widget.bleManager!.connectedDevice!.platformName
              : (widget.deviceName ?? widget.targetDeviceId ?? 'HealthKicks-HK-2');

          final effectiveMqttConnected =
              widget.isMqttConnectedNotifier?.value ?? widget.isMqttConnected;

          final VoidCallback? onDisconnect = isBleReady
              ? () {
                  setState(() {
                    _isLocallyDisconnected = true;
                  });
                  if (widget.onDisconnectBle != null) {
                    widget.onDisconnectBle!();
                  } else if (widget.bleManager != null) {
                    widget.bleManager!.disconnect();
                  }
                }
              : null;

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              SettingsConnectionStatusCard(
                bleStatus: currentBleStatus,
                isBleReady: isBleReady,
                isBleScanning: isBleScanning,
                isBleConnecting: isBleConnecting,
                deviceName: currentDeviceName,
                mtu: currentMtu,
                onStartBleScan: widget.onStartBleScan != null
                    ? () {
                        setState(() => _isLocallyDisconnected = false);
                        widget.onStartBleScan!();
                      }
                    : null,
                onDisconnectBle: onDisconnect,
                onOpenCalibration: isBleReady && (activeBleClient != null || widget.onCalibrateSensor != null)
                    ? () => _showCalibrationDialog(context, isBleReady)
                    : null,
                isMqttConnected: effectiveMqttConnected,
                onReconnectMqtt: widget.onReconnectMqtt,
              ),
              SettingsBiomechanicsSection(
                surveillanceService: widget.surveillanceService,
                inactivityService: _inactivityService,
                fallSensitivityService: _fallSensitivityService,
                themeService: _themeService,
                localeService: _localeService,
                bleClient: activeBleClient,
                isBleReady: isBleReady,
                onOpenCalibrationDialog: () => _showCalibrationDialog(context, isBleReady),
                onOpenLanguageSelector: () => _showLanguageSelector(context),
                healthConnectService: _healthConnectService,
              ),
              SettingsAccountSection(
                authService: widget.authService,
                onLogout: () async {
                  await widget.authService?.logout();
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
              ),
              if (widget.onOpenEventLogs != null)
                ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: const Text('Journal d\'événements'),
                  subtitle: const Text('Consulter les événements récents'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: widget.onOpenEventLogs,
                ),
              SettingsSystemInfoSection(
                isBleReady: isBleReady,
                firmwareSubtitle: _getFirmwareSubtitle(isBleReady),
                onOpenFirmwareUpdateScreen: _openFirmwareUpdateScreen,
              ),
            ],
          );
        },
      ),
    );
  }
}
