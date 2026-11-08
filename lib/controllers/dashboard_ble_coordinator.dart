import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../services/ble/ble_connection_manager.dart';
import '../services/ble/ble_footwear_client.dart';

/// Delegate coordinator handling BLE scanning, device lifecycle, and characteristic clients.
class DashboardBleCoordinator {
  final String targetDeviceId;
  final void Function(String tag, String message, {Color? color}) onLog;
  final VoidCallback onStateUpdated;
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
    required this.onLog,
    required this.onStateUpdated,
    required this.onDeviceReady,
    required this.onDeviceDisconnected,
    BleConnectionManager? bleManager,
  }) : _bleManager = bleManager;

  BleConnectionStatus get status => _bleStatus;
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
      onLog: (msg) {
        onLog(
          msg.startsWith('[PERM]') ? 'PERM' : 'BLE',
          msg.replaceFirst(RegExp(r'^\[(BLE|PERM)\]\s*'), ''),
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

  Future<void> startAutoConnect({bool fromButton = false}) async {
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

    await _bleManager!.startAutoConnect(targetDeviceId: targetDeviceId);
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
    bleClientNotifier.value = null;
  }
}
