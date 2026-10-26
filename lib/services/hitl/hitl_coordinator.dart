import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../models/activity_detection_model.dart';
import '../../models/hitl/hitl_detection_item.dart';
import '../../models/imu_reading_model.dart';
import '../ble/ble_footwear_client.dart';
import '../mqtt/mqtt_gateway_service.dart';
import '../studio/studio_api_service.dart';

const _uuid = Uuid();

/// Coordinator managing Human-in-the-Loop (HITL) mode:
/// - Maintains a local FIFO buffer of the last 15 unconfirmed detections.
/// - Pairs incoming BLE Activity notifications with corresponding 76-sample IMU bursts.
/// - Facilitates user reclassification and publishes confirmed sessions marked with `is_hitl = true`.
class HitlCoordinator extends ChangeNotifier {
  static const int maxFifoCapacity = 15;

  final List<HitlDetectionItem> _items = [];
  bool _isHitlActive = false;

  final MqttGatewayService? _mqttService;
  final StudioApiService? _studioApiService;
  final void Function(String message, {bool isError})? onLog;

  HitlCoordinator({
    MqttGatewayService? mqttService,
    StudioApiService? studioApiService,
    this.onLog,
  })  : _mqttService = mqttService,
        _studioApiService = studioApiService;

  bool get isHitlActive => _isHitlActive;
  List<HitlDetectionItem> get items => List.unmodifiable(_items);
  int get itemCount => _items.length;

  /// Activates or deactivates HITL mode, optionally synchronizing with the connected footwear.
  Future<void> setHitlActive(bool active, {BleFootwearClient? bleClient}) async {
    _isHitlActive = active;
    if (!active) {
      _items.clear();
    }
    if (bleClient != null && bleClient.hasStudioControl) {
      try {
        await bleClient.sendHitlConfig(active);
        onLog?.call('Mode HITL synchronisé avec la chaussure : ${active ? "ACTIF" : "INACTIF"}');
      } catch (e) {
        onLog?.call('Erreur synchronisation BLE mode HITL : $e', isError: true);
      }
    }
    notifyListeners();
  }

  /// Registers a newly detected activity into the FIFO queue.
  HitlDetectionItem registerDetection(ActivityDetectionModel detection) {
    final item = HitlDetectionItem(
      id: _uuid.v4(),
      timestamp: detection.effectiveTimestamp,
      detectedLabel: detection.eventType,
      confidencePercent: detection.confidencePercent,
      isFall: detection.isFall,
      rawDetection: detection,
    );

    _items.insert(0, item);
    if (_items.length > maxFifoCapacity) {
      _items.removeLast();
    }
    notifyListeners();
    return item;
  }

  /// Pairs an incoming 76-sample IMU burst with the most recent pending detection item.
  void attachBurstReadings(List<ImuReadingModel> readings, {String? sessionId}) {
    if (_items.isEmpty || readings.isEmpty) return;

    for (final item in _items) {
      if (!item.isBurstReady && item.readings.isEmpty) {
        item.readings = List.from(readings);
        item.isBurstReady = true;
        onLog?.call(
          'Salve HITL (${readings.length} trames) associée à la détection "${item.detectedLabel}" (${item.id.substring(0, 8)})',
        );
        notifyListeners();
        break;
      }
    }
  }

  /// Modifies the activity label chosen by the clinician/admin.
  void updateItemLabel(String itemId, String newLabel) {
    final index = _items.indexWhere((i) => i.id == itemId);
    if (index != -1) {
      _items[index].selectedLabel = newLabel;
      notifyListeners();
    }
  }

  /// Discards a detection item without publishing.
  void dismissItem(String itemId) {
    _items.removeWhere((i) => i.id == itemId);
    notifyListeners();
  }

  /// Confirms and publishes the HITL session to AWS IoT Core (DynamoDB) and the backend API (Aurora).
  Future<bool> confirmAndPublish(
    HitlDetectionItem item, {
    required String deviceId,
  }) async {
    final index = _items.indexWhere((i) => i.id == item.id);
    if (index == -1) return false;

    _items[index].isPublishing = true;
    notifyListeners();

    try {
      final session = item.toStudioSession(
        deviceId: deviceId,
        sessionId: _uuid.v4(),
        durationSec: 4.0,
      );

      // 1. MQTT publication towards AWS IoT Core & DynamoDB
      if (_mqttService != null) {
        await _mqttService.publishStudioSession(session);
      }

      // 2. REST API registration if available
      if (_studioApiService != null) {
        try {
          await _studioApiService.startStudioSession(
            deviceId: deviceId,
            label: session.label,
            durationSec: session.durationSec,
          );
        } catch (_) {
          // REST registration is best-effort; raw telemetry MQTT is primary source of truth
        }
      }

      onLog?.call(
        'Session HITL confirmée et publiée avec succès [${session.label}] (${session.sessionId.substring(0, 8)})',
      );

      final idx = _items.indexWhere((i) => i.id == item.id);
      if (idx != -1) {
        _items[idx].isPublishing = false;
        _items[idx].isSynchronized = true;
      }
      notifyListeners();
      return true;
    } catch (e) {
      onLog?.call('Erreur lors de la publication de la session HITL : $e', isError: true);
      final idx = _items.indexWhere((i) => i.id == item.id);
      if (idx != -1) {
        _items[idx].isPublishing = false;
        notifyListeners();
      }
      return false;
    }
  }

  /// Clears the FIFO buffer.
  void clear() {
    _items.clear();
    notifyListeners();
  }
}

