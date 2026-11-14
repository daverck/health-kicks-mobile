import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../core/constants/ble_constants.dart';
import '../core/permissions/permission_service.dart';
import '../services/ble/ble_connection_manager.dart';
import '../services/ble/ble_footwear_client.dart';

/// Delegate coordinator handling BLE scanning, device lifecycle, and characteristic clients.
class DashboardBleCoordinator {
  final String targetDeviceId;
  final PermissionService? permissionService;
  final void Function(String tag, String message, {Color? color}) onLog;
  final VoidCallback onStateUpdated;
  final void Function(BleConnectionStatus status, BluetoothDevice? device)? onStatusChanged;
  final void Function(BluetoothDevice device) onDeviceReady;
  final VoidCallback onDeviceDisconnected;

  BleConnectionManager? _bleManager;
  BleFootwearClient? _bleClient;
  final ValueNotifier<BleFootwearClient?> bleClientNotifier = ValueNotifier<BleFootwearClient?>(null);

  BleConnectionStatus _bleStatus = BleConnectionStatus.disconnected;
  BluetoothDevice? _connectedDevice;
  int _mtu = 23;
  bool _isDisposed = false;

  DashboardBleCoordinator({
    required this.targetDeviceId,
    this.permissionService,
    required this.onLog,
    required this.onStateUpdated,
    this.onStatusChanged,
    required this.onDeviceReady,
    required this.onDeviceDisconnected,
    this._bleManager,
  });

  BleConnectionStatus get status => _bleStatus;
  Stream<BleConnectionStatus>? get statusStream => _bleManager?.statusStream;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  int get mtu => _mtu;
  BleConnectionManager? get bleManager => _bleManager;
  BleFootwearClient? get bleClient => _bleClient;
  set bleClient(BleFootwearClient? client) {
    _bleClient = client;
    bleClientNotifier.value = client;
  }

  void ensureBleManager() {
    if (_bleManager != null) return;
    _bleManager = BleConnectionManager(
      permissionService: permissionService,
      onLog: (msg) {
        final isError = msg.contains('Erreur') || msg.contains('refusé') || msg.contains('Échec');
        onLog(
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
      onStateUpdated();

      onStatusChanged?.call(status, _connectedDevice);

      onLog('BLE', 'Statut connexion : ${status.name}');
      if (status == BleConnectionStatus.disconnected || status == BleConnectionStatus.scanning) {
        _bleClient?.dispose();
        _bleClient = null;
        bleClientNotifier.value = null;
        onDeviceDisconnected();
      } else if (status == BleConnectionStatus.ready && _bleManager?.connectedDevice != null) {
        onDeviceReady(_bleManager!.connectedDevice!);
      }
    });
  }

  void _onBleManagerUpdated() {
    if (_isDisposed) return;
    _bleStatus = _bleManager!.status;
    _connectedDevice = _bleManager!.connectedDevice;
    _mtu = _bleManager!.negotiatedMtu;
    onStateUpdated();
  }

  Future<void> startAutoConnect({bool fromButton = false, Duration? timeout}) async {
    if (fromButton) {
      onLog('UI', 'Bouton Re-scanner pressé');
    }
    ensureBleManager();
    _bleStatus = BleConnectionStatus.scanning;
    _connectedDevice = null;
    _bleClient?.dispose();
    _bleClient = null;
    bleClientNotifier.value = null;
    onStateUpdated();

    try {
      await _bleManager?.disconnect();
    } catch (_) {}

    onLog('BLE', 'Démarrage du scan large pour "$targetDeviceId" ou Service GATT...');
    try {
      await _bleManager!.startAutoConnect(
        targetDeviceId: targetDeviceId,
        timeout: timeout ?? BleConstants.defaultScanTimeout,
        onLog: (msg) {
          final isError = msg.contains('Erreur') || msg.contains('refusé') || msg.contains('Échec');
          onLog(
            'BLE',
            msg,
            color: isError ? Colors.red : (msg.contains('Connecté') ? Colors.green : Colors.blueGrey),
          );
        },
      );
    } catch (e) {
      onLog('BLE', 'Erreur de scan : $e', color: Colors.red);
    }
  }

  Future<void> disconnect() async {
    await _bleManager?.disconnect();
    _bleClient?.dispose();
    _bleClient = null;
    bleClientNotifier.value = null;
  }

  void dispose() {
    _isDisposed = true;
    _bleManager?.removeListener(_onBleManagerUpdated);
    _bleClient?.dispose();
    _bleClient = null;
    bleClientNotifier.dispose();
    _bleManager?.dispose();
  }
}
