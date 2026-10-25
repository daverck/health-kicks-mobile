import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../core/constants/ble_constants.dart';
import '../../models/activity_detection_model.dart';
import '../../models/haptic_command_model.dart';
import '../../models/step_data_model.dart';
import '../firmware/firmware_service.dart';
import 'burst_reassembler.dart';

typedef BleLogCallback = void Function(String message, {bool isError});

/// GATT client for the HealthKicks smart footwear.
/// Orchestrates notification subscriptions and writes across all 5 characteristics.
class BleFootwearClient {
  final BluetoothDevice device;
  final BleLogCallback? onLog;
  final BurstReassembler _burstReassembler = BurstReassembler();

  BluetoothCharacteristic? _activityChar;
  BluetoothCharacteristic? _hapticChar;
  BluetoothCharacteristic? _studioControlChar;
  BluetoothCharacteristic? _studioBurstChar;
  BluetoothCharacteristic? _stepCounterChar;

  String? _firmwareVersion;
  DateTime? _firmwareBuildDate;
  String? _rawBuildString;

  String? get firmwareVersion => _firmwareVersion;
  DateTime? get firmwareBuildDate => _firmwareBuildDate;
  String? get rawBuildString => _rawBuildString;

  BluetoothCharacteristic? get activityCharacteristic => _activityChar;
  BluetoothCharacteristic? get hapticCharacteristic => _hapticChar;
  BluetoothCharacteristic? get studioControlCharacteristic => _studioControlChar;
  BluetoothCharacteristic? get studioBurstCharacteristic => _studioBurstChar;
  BluetoothCharacteristic? get stepCounterCharacteristic => _stepCounterChar;

  bool get hasHaptic => _hapticChar != null;
  bool get hasStudioControl => _studioControlChar != null;
  bool get hasActivityDetection => _activityChar != null;
  bool get hasStudioBurst => _studioBurstChar != null;
  bool get hasStepCounter => _stepCounterChar != null;
  bool get isReady => _hapticChar != null && _studioControlChar != null;

  final _activityController = StreamController<ActivityDetectionModel>.broadcast();
  Stream<ActivityDetectionModel> get activityStream => _activityController.stream;

  final _studioStatusController = StreamController<String>.broadcast();
  Stream<String> get studioStatusStream => _studioStatusController.stream;

  final _burstResultController = StreamController<BurstReassemblyResult>.broadcast();
  Stream<BurstReassemblyResult> get burstResultStream => _burstResultController.stream;

  final _stepDataController = StreamController<StepDataModel>.broadcast();
  Stream<StepDataModel> get stepDataStream => _stepDataController.stream;

  StepDataModel? _currentStepData;
  StepDataModel? get currentStepData => _currentStepData;

  BleFootwearClient({required this.device, this.onLog});

  /// Discovers services and subscribes to notifications for characteristics 0002, 0004, and 0005.
  Future<void> initializeServices() async {
    // Always discover services freshly on initialization to prevent stale GATT handles across reconnections
    final services = await device.discoverServices();
    final serviceGuid = Guid(BleConstants.footwearServiceUuid);

    final targetService = services.firstWhere(
      (s) => s.uuid == serviceGuid,
      orElse: () => throw StateError('Service HealthKicks Footwear ($serviceGuid) not found.'),
    );

    // Read DIS (Device Information Service 0x180A) in the same GATT pass if available
    for (final service in services) {
      final sUuid = service.uuid.toString().toLowerCase();
      if (sUuid == BleConstants.disServiceUuid || sUuid.contains('180a')) {
        for (final char in service.characteristics) {
          final cUuid = char.uuid.toString().toLowerCase();
          if (cUuid == BleConstants.firmwareRevisionCharUuid || cUuid.contains('2a26')) {
            try {
              final bytes = await char.read();
              _firmwareVersion = utf8.decode(bytes).replaceAll('\u0000', '').trim();
            } catch (_) {}
          } else if (cUuid == BleConstants.softwareRevisionCharUuid || cUuid.contains('2a28')) {
            try {
              final bytes = await char.read();
              _rawBuildString = utf8.decode(bytes).replaceAll('\u0000', '').trim();
              _firmwareBuildDate = FirmwareService.parseBuildTimestamp(_rawBuildString);
            } catch (_) {}
          }
        }
      }
    }

    for (final char in targetService.characteristics) {
      final uuidStr = char.uuid.toString().toLowerCase();

      if (uuidStr == BleConstants.activityDetectionCharUuid.toLowerCase()) {
        _activityChar = char;
        await _subscribeToActivityDetection(char);
      } else if (uuidStr == BleConstants.hapticCommandCharUuid.toLowerCase()) {
        _hapticChar = char;
      } else if (uuidStr == BleConstants.studioControlCharUuid.toLowerCase()) {
        _studioControlChar = char;
        await _subscribeToStudioControl(char);
      } else if (uuidStr == BleConstants.studioDataBurstCharUuid.toLowerCase()) {
        _studioBurstChar = char;
        await _subscribeToStudioBurst(char);
      } else if (uuidStr == BleConstants.stepCounterCharUuid.toLowerCase()) {
        _stepCounterChar = char;
        await _subscribeToStepCounter(char);
      }
    }
  }

  Future<void> _subscribeToActivityDetection(BluetoothCharacteristic char) async {
    final sub = char.onValueReceived.listen((bytes) {
      if (bytes.length >= 7) {
        try {
          final model = ActivityDetectionModel.fromBytes(bytes);
          _activityController.add(model);
        } catch (_) {}
      }
    });
    device.cancelWhenDisconnected(sub);
    await char.setNotifyValue(true);
  }

  Future<void> _subscribeToStudioControl(BluetoothCharacteristic char) async {
    final sub = char.onValueReceived.listen((bytes) {
      if (bytes.isNotEmpty) {
        final statusMsg = utf8.decode(bytes, allowMalformed: true).trim();
        onLog?.call('Studio Control notification (0004): "$statusMsg"', isError: false);
        _studioStatusController.add(statusMsg);
      }
    });
    device.cancelWhenDisconnected(sub);
    await char.setNotifyValue(true);
  }

  Future<void> _subscribeToStudioBurst(BluetoothCharacteristic char) async {
    final sub = char.onValueReceived.listen((bytes) {
      if (bytes.isNotEmpty) {
        onLog?.call('Burst packet received (size=${bytes.length} bytes)', isError: false);
        final result = _burstReassembler.processPacket(bytes);
        if (result != null) {
          onLog?.call(
            'Burst completion detected: ${result.framesRecovered}/${result.totalAnnounced} frames reassembled (CRC32: ${result.isCrcValid ? "OK" : "Failed"})',
            isError: !result.isSuccess,
          );
          _burstResultController.add(result);
        }
      }
    });
    device.cancelWhenDisconnected(sub);
    await char.setNotifyValue(true);
  }

  Future<void> _subscribeToStepCounter(BluetoothCharacteristic char) async {
    final sub = char.onValueReceived.listen((bytes) {
      if (bytes.length >= 13) {
        try {
          final model = StepDataModel.fromBytes(bytes);
          _currentStepData = model;
          _stepDataController.add(model);
          onLog?.call(
            'Step Counter: ${model.totalSteps} steps (Walk: ${model.walkSteps}, Run: ${model.runSteps}, Stairs: ${model.stairsSteps}, SPM: ${model.cadenceSpm})',
            isError: false,
          );
        } catch (e) {
          onLog?.call('Failed to decode step counter payload: $e', isError: true);
        }
      }
    });
    device.cancelWhenDisconnected(sub);
    await char.setNotifyValue(true);
  }

  /// Writes a tactile haptic vibration command (4 bytes Big-Endian).
  Future<void> sendHapticCommand(HapticCommandModel command) async {
    if (_hapticChar == null) {
      throw StateError('Haptic Command characteristic not initialized.');
    }
    final bytes = Uint8List(4);
    bytes[0] = command.patternId;
    bytes[1] = command.intensity;
    bytes[2] = (command.durationMs >> 8) & 0xFF;
    bytes[3] = command.durationMs & 0xFF;
    await _hapticChar!.write(bytes, withoutResponse: false);
    onLog?.call('Haptic command sent: int=${command.intensity}, dur=${command.durationMs}ms', isError: false);
  }

  /// Sends the prolonged inactivity reminder configuration (`SET_INACTIVITY <0|1> <threshold_sec> <cooldown_sec>`).
  Future<void> sendInactivityConfig({
    required bool enabled,
    required int thresholdSec,
    required int cooldownSec,
  }) async {
    if (_studioControlChar == null) {
      throw StateError('Device & Studio Control characteristic not initialized.');
    }
    final cmd = 'SET_INACTIVITY ${enabled ? 1 : 0} $thresholdSec $cooldownSec';
    await _studioControlChar!.write(utf8.encode(cmd), withoutResponse: false);
    onLog?.call(
      'Inactivity config sent: $cmd',
      isError: false,
    );
  }

  /// Sends the fall impact threshold configuration (`SET_FALL_IMPACT [impactMs2]`) to the footwear.
  Future<void> sendFallImpactConfig(double impactMs2) async {
    if (_studioControlChar == null) {
      throw StateError('Studio Control characteristic not initialized.');
    }
    final cmd = 'SET_FALL_IMPACT ${impactMs2.toStringAsFixed(1)}';
    await _studioControlChar!.write(utf8.encode(cmd), withoutResponse: false);
    onLog?.call('Fall impact config sent: $cmd', isError: false);
  }

  /// Sends the HITL mode configuration (`SET_HITL <0|1>`) to the footwear.
  Future<void> sendHitlConfig(bool enabled) async {
    if (_studioControlChar == null) {
      throw StateError('Studio Control characteristic not initialized.');
    }
    final cmd = 'SET_HITL ${enabled ? 1 : 0}';
    await _studioControlChar!.write(utf8.encode(cmd), withoutResponse: false);
    onLog?.call('HITL mode config sent: $cmd', isError: false);
  }

  /// Triggers a Studio recording session (`START <label> <sec> <id>`).
  Future<void> startStudioSession({
    required String label,
    required double durationSec,
    required String sessionId,
  }) async {
    if (_studioControlChar == null) {
      throw StateError('Studio Control characteristic not initialized.');
    }
    _burstReassembler.reset();
    final cmd = 'START $label ${durationSec.toStringAsFixed(1)} $sessionId';
    await _studioControlChar!.write(utf8.encode(cmd), withoutResponse: false);
  }

  /// Cancels an ongoing Studio session.
  Future<void> cancelStudioSession() async {
    if (_studioControlChar == null) return;
    try {
      await _studioControlChar!
          .write(utf8.encode('CANCEL'), withoutResponse: false)
          .timeout(const Duration(milliseconds: 1000));
    } catch (_) {
      // Ignore if BLE characteristic write fails or times out during disconnection
    }
  }

  /// Ends the active Studio recording and asks the footwear to transmit its samples.
  Future<void> finishStudioSession() async {
    if (_studioControlChar == null) {
      throw StateError('Studio Control characteristic not initialized.');
    }
    await _studioControlChar!.write(
      utf8.encode('FINISH'),
      withoutResponse: false,
    );
  }

  /// Sends zero/tilt calibration command to the footwear (ASCII "CALIBRATE" on Characteristic 0004).
  Future<void> sendCalibrateZeroCommand() async {
    if (_studioControlChar == null) {
      throw StateError('Device & Studio Control characteristic not initialized.');
    }
    await _studioControlChar!.write(utf8.encode('CALIBRATE'), withoutResponse: false);
    onLog?.call('Tilt calibration command ("CALIBRATE") sent via Device & Studio Control characteristic.', isError: false);
  }

  void dispose() {
    _activityController.close();
    _studioStatusController.close();
    _burstResultController.close();
    _stepDataController.close();
  }
}
