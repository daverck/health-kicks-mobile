import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../core/constants/ble_constants.dart';
import '../../models/activity_detection_model.dart';
import '../../models/haptic_command_model.dart';
import 'burst_reassembler.dart';

/// Client GATT pour la chaussure connectée HealthKicks.
/// Orchestre les souscriptions aux notifications et les écritures sur les 4 caractéristiques.
class BleFootwearClient {
  final BluetoothDevice device;
  final BurstReassembler _burstReassembler = BurstReassembler();

  BluetoothCharacteristic? _activityChar;
  BluetoothCharacteristic? _hapticChar;
  BluetoothCharacteristic? _studioControlChar;
  BluetoothCharacteristic? _studioBurstChar;

  BluetoothCharacteristic? get activityCharacteristic => _activityChar;
  BluetoothCharacteristic? get studioBurstCharacteristic => _studioBurstChar;

  final _activityController = StreamController<ActivityDetectionModel>.broadcast();
  Stream<ActivityDetectionModel> get activityStream => _activityController.stream;

  final _studioStatusController = StreamController<String>.broadcast();
  Stream<String> get studioStatusStream => _studioStatusController.stream;

  final _burstResultController = StreamController<BurstReassemblyResult>.broadcast();
  Stream<BurstReassemblyResult> get burstResultStream => _burstResultController.stream;

  BleFootwearClient({required this.device});

  /// Découvre les services et s'abonne aux notifications des caractéristiques 0002, 0004 et 0005.
  Future<void> initializeServices() async {
    final services = await device.discoverServices();
    final serviceGuid = Guid(BleConstants.footwearServiceUuid);

    final targetService = services.firstWhere(
      (s) => s.uuid == serviceGuid,
      orElse: () => throw StateError('Service HealthKicks Footwear ($serviceGuid) introuvable.'),
    );

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
      }
    }
  }

  Future<void> _subscribeToActivityDetection(BluetoothCharacteristic char) async {
    await char.setNotifyValue(true);
    char.lastValueStream.listen((bytes) {
      if (bytes.length >= 7) {
        try {
          final model = ActivityDetectionModel.fromBytes(bytes);
          _activityController.add(model);
        } catch (_) {}
      }
    });
  }

  Future<void> _subscribeToStudioControl(BluetoothCharacteristic char) async {
    await char.setNotifyValue(true);
    char.lastValueStream.listen((bytes) {
      if (bytes.isNotEmpty) {
        final statusMsg = utf8.decode(bytes, allowMalformed: true).trim();
        _studioStatusController.add(statusMsg);
      }
    });
  }

  Future<void> _subscribeToStudioBurst(BluetoothCharacteristic char) async {
    await char.setNotifyValue(true);
    char.lastValueStream.listen((bytes) {
      if (bytes.isNotEmpty) {
        final result = _burstReassembler.processPacket(bytes);
        if (result != null) {
          _burstResultController.add(result);
        }
      }
    });
  }

  /// Écrit une commande de vibration haptique (4 octets Big-Endian).
  Future<void> sendHapticCommand(HapticCommandModel command) async {
    if (_hapticChar == null) {
      throw StateError('Caractéristique Haptic Command non initialisée.');
    }
    final bytes = command.toBleBytes();
    await _hapticChar!.write(bytes, withoutResponse: false);
  }

  /// Déclenche une session d'enregistrement Studio (START <label> <sec> <id>).
  Future<void> startStudioSession({
    required String label,
    required double durationSec,
    required String sessionId,
  }) async {
    if (_studioControlChar == null) {
      throw StateError('Caractéristique Studio Control non initialisée.');
    }
    _burstReassembler.reset();
    final cmd = 'START $label ${durationSec.toStringAsFixed(1)} $sessionId';
    await _studioControlChar!.write(utf8.encode(cmd), withoutResponse: false);
  }

  /// Annule une session Studio en cours.
  Future<void> cancelStudioSession() async {
    if (_studioControlChar == null) return;
    await _studioControlChar!.write(utf8.encode('CANCEL'), withoutResponse: false);
  }

  void dispose() {
    _activityController.close();
    _studioStatusController.close();
    _burstResultController.close();
  }
}
