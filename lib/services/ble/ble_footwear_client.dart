import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../core/constants/ble_constants.dart';
import '../../models/activity_detection_model.dart';
import '../../models/haptic_command_model.dart';
import 'burst_reassembler.dart';

typedef BleLogCallback = void Function(String message, {bool isError});

/// Client GATT pour la chaussure connectée HealthKicks.
/// Orchestre les souscriptions aux notifications et les écritures sur les 4 caractéristiques.
class BleFootwearClient {
  final BluetoothDevice device;
  final BleLogCallback? onLog;
  final BurstReassembler _burstReassembler = BurstReassembler();

  BluetoothCharacteristic? _activityChar;
  BluetoothCharacteristic? _hapticChar;
  BluetoothCharacteristic? _studioControlChar;
  BluetoothCharacteristic? _studioBurstChar;

  BluetoothCharacteristic? get activityCharacteristic => _activityChar;
  BluetoothCharacteristic? get hapticCharacteristic => _hapticChar;
  BluetoothCharacteristic? get studioControlCharacteristic => _studioControlChar;
  BluetoothCharacteristic? get studioBurstCharacteristic => _studioBurstChar;

  bool get hasHaptic => _hapticChar != null;
  bool get hasStudioControl => _studioControlChar != null;
  bool get hasActivityDetection => _activityChar != null;
  bool get hasStudioBurst => _studioBurstChar != null;
  bool get isReady => _hapticChar != null && _studioControlChar != null;

  final _activityController = StreamController<ActivityDetectionModel>.broadcast();
  Stream<ActivityDetectionModel> get activityStream => _activityController.stream;

  final _studioStatusController = StreamController<String>.broadcast();
  Stream<String> get studioStatusStream => _studioStatusController.stream;

  final _burstResultController = StreamController<BurstReassemblyResult>.broadcast();
  Stream<BurstReassemblyResult> get burstResultStream => _burstResultController.stream;

  BleFootwearClient({required this.device, this.onLog});

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
        onLog?.call('[BLE] Notification Studio Control (0004) : "$statusMsg"', isError: false);
        _studioStatusController.add(statusMsg);
      }
    });
    device.cancelWhenDisconnected(sub);
    await char.setNotifyValue(true);
  }

  Future<void> _subscribeToStudioBurst(BluetoothCharacteristic char) async {
    final sub = char.onValueReceived.listen((bytes) {
      if (bytes.isNotEmpty) {
        onLog?.call('[BLE] Paquet Burst reçu (taille=${bytes.length} octets)', isError: false);
        final result = _burstReassembler.processPacket(bytes);
        if (result != null) {
          onLog?.call(
            '[BLE] Fin du Burst détectée : ${result.framesRecovered}/${result.totalAnnounced} trames réassemblées (CRC32: ${result.isCrcValid ? "OK" : "Échec"})',
            isError: !result.isSuccess,
          );
          _burstResultController.add(result);
        }
      }
    });
    device.cancelWhenDisconnected(sub);
    await char.setNotifyValue(true);
  }

  /// Écrit une commande de vibration haptique (4 octets Big-Endian).
  Future<void> sendHapticCommand(HapticCommandModel command) async {
    if (_hapticChar == null) {
      throw StateError('Caractéristique Haptic Command non initialisée.');
    }
    final bytes = Uint8List(4);
    bytes[0] = command.patternId;
    bytes[1] = command.intensity;
    bytes[2] = (command.durationMs >> 8) & 0xFF;
    bytes[3] = command.durationMs & 0xFF;
    await _hapticChar!.write(bytes, withoutResponse: false);
    onLog?.call('[BLE] Commande haptique émise: int=${command.intensity}, dur=${command.durationMs}ms', isError: false);
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
