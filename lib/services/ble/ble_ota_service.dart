import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../core/constants/ble_constants.dart';

/// Lifecycle state for Over-The-Air BLE firmware flashing
enum BleOtaStatus {
  idle,
  preparing,
  transferring,
  finalizing,
  success,
  error,
  aborted,
}

/// Progress snapshot emitted during OTA transfer
class BleOtaProgress {
  final BleOtaStatus status;
  final int bytesSent;
  final int totalBytes;
  final double progress; // 0.0 to 1.0
  final double speedKbps;
  final Duration? estimatedTimeRemaining;
  final String? message;
  final int? errorCode;

  const BleOtaProgress({
    required this.status,
    this.bytesSent = 0,
    this.totalBytes = 0,
    this.progress = 0.0,
    this.speedKbps = 0.0,
    this.estimatedTimeRemaining,
    this.message,
    this.errorCode,
  });

  BleOtaProgress copyWith({
    BleOtaStatus? status,
    int? bytesSent,
    int? totalBytes,
    double? progress,
    double? speedKbps,
    Duration? estimatedTimeRemaining,
    String? message,
    int? errorCode,
  }) {
    return BleOtaProgress(
      status: status ?? this.status,
      bytesSent: bytesSent ?? this.bytesSent,
      totalBytes: totalBytes ?? this.totalBytes,
      progress: progress ?? this.progress,
      speedKbps: speedKbps ?? this.speedKbps,
      estimatedTimeRemaining: estimatedTimeRemaining ?? this.estimatedTimeRemaining,
      message: message ?? this.message,
      errorCode: errorCode ?? this.errorCode,
    );
  }
}

/// Service managing Over-The-Air (OTA) firmware binary transfer over BLE GATT.
/// Contract reference: contracts/ble_gatt_specs.md (Service 0010, Chars 0011 & 0012)
class BleOtaService {
  final StreamController<BleOtaProgress> _progressController =
      StreamController<BleOtaProgress>.broadcast();

  BleOtaProgress _currentProgress =
      const BleOtaProgress(status: BleOtaStatus.idle);

  bool _isAborted = false;
  StreamSubscription<List<int>>? _controlSubscription;

  Stream<BleOtaProgress> get progressStream => _progressController.stream;
  BleOtaProgress get currentProgress => _currentProgress;
  bool get isUpdating =>
      _currentProgress.status == BleOtaStatus.preparing ||
      _currentProgress.status == BleOtaStatus.transferring ||
      _currentProgress.status == BleOtaStatus.finalizing;

  void _emit(BleOtaProgress progress) {
    _currentProgress = progress;
    if (!_progressController.isClosed) {
      _progressController.add(progress);
    }
  }

  /// Translates firmware OTA error code to a readable diagnostic string
  static String formatErrorCode(int code) {
    switch (code) {
      case 0x01:
        return 'No inactive OTA partition found (0x01)';
      case 0x02:
        return 'Flash descriptor init failed (esp_ota_begin 0x02)';
      case 0x03:
        return 'Flash write failed (esp_ota_write 0x03)';
      case 0x04:
        return 'Payload byte count mismatch (0x04)';
      case 0x05:
        return 'Image validation/CRC failed (esp_ota_end 0x05)';
      case 0x06:
        return 'Switch active boot partition failed (0x06)';
      default:
        return 'Unknown firmware error code (0x${code.toRadixString(16)})';
    }
  }

  /// Cancels any ongoing OTA transfer
  void abort() {
    _isAborted = true;
    _emit(_currentProgress.copyWith(
      status: BleOtaStatus.aborted,
      message: 'Mise à jour annulée par l\'utilisateur.',
    ));
  }

  /// Starts streaming the binary firmware [firmwareBytes] to [device].
  Future<bool> startUpdate({
    required BluetoothDevice device,
    required Uint8List firmwareBytes,
    int pacingDelayMs = 6,
    int? forcedChunkSize,
  }) async {
    if (firmwareBytes.isEmpty) {
      _emit(const BleOtaProgress(
        status: BleOtaStatus.error,
        message: 'Le fichier binaire du firmware est vide.',
      ));
      return false;
    }

    _isAborted = false;
    _emit(BleOtaProgress(
      status: BleOtaStatus.preparing,
      totalBytes: firmwareBytes.length,
      message: 'Découverte du service OTA et négociation MTU...',
    ));

    try {
      // 1. Request preferred MTU for high-speed streaming
      try {
        await device.requestMtu(247).timeout(const Duration(seconds: 3));
      } catch (_) {
        // MTU request might not be supported on all platforms/OS versions; continue with current MTU
      }

      // 2. Discover GATT services
      final services = await device.discoverServices();
      BluetoothCharacteristic? controlChar;
      BluetoothCharacteristic? dataChar;

      for (final service in services) {
        if (service.uuid.toString().toLowerCase() ==
            BleConstants.otaServiceUuid.toLowerCase()) {
          for (final char in service.characteristics) {
            final uuidStr = char.uuid.toString().toLowerCase();
            if (uuidStr == BleConstants.otaControlCharUuid.toLowerCase()) {
              controlChar = char;
            } else if (uuidStr == BleConstants.otaDataCharUuid.toLowerCase()) {
              dataChar = char;
            }
          }
        }
      }

      if (controlChar == null || dataChar == null) {
        _emit(const BleOtaProgress(
          status: BleOtaStatus.error,
          message: 'Service OTA ou caractéristiques introuvables sur l\'appareil.',
        ));
        return false;
      }

      // 3. Set up notification listener on OTA Control characteristic
      final readyCompleter = Completer<bool>();
      final finalCompleter = Completer<bool>();
      int? reportedErrorCode;

      await controlChar.setNotifyValue(true);
      await _controlSubscription?.cancel();
      _controlSubscription = controlChar.lastValueStream.listen((value) {
        if (value.isEmpty) return;
        final opcode = value[0];

        if (opcode == BleConstants.otaRespReady) {
          if (!readyCompleter.isCompleted) {
            readyCompleter.complete(true);
          }
        } else if (opcode == BleConstants.otaRespSuccess) {
          if (!finalCompleter.isCompleted) {
            finalCompleter.complete(true);
          }
        } else if (opcode == BleConstants.otaRespError) {
          reportedErrorCode = (value.length > 1) ? value[1] : 0xFF;
          final errStr = formatErrorCode(reportedErrorCode!);
          if (!readyCompleter.isCompleted) {
            readyCompleter.completeError(Exception(errStr));
          }
          if (!finalCompleter.isCompleted) {
            finalCompleter.completeError(Exception(errStr));
          }
        }
      });

      // 4. Send OTA_BEGIN (0x01) with 4-byte Big-Endian file size
      final totalSize = firmwareBytes.length;
      final beginPacket = Uint8List(5);
      beginPacket[0] = BleConstants.otaCmdBegin;
      beginPacket[1] = (totalSize >> 24) & 0xFF;
      beginPacket[2] = (totalSize >> 16) & 0xFF;
      beginPacket[3] = (totalSize >> 8) & 0xFF;
      beginPacket[4] = totalSize & 0xFF;

      await controlChar.write(beginPacket, withoutResponse: false);

      // 5. Await OTA_READY (timeout after 10 seconds)
      _emit(_currentProgress.copyWith(
        message: 'En attente de la préparation de la mémoire Flash...',
      ));

      try {
        await readyCompleter.future.timeout(const Duration(seconds: 10));
      } on TimeoutException {
        _emit(const BleOtaProgress(
          status: BleOtaStatus.error,
          message: 'Délai d\'attente dépassé pour la confirmation OTA_READY.',
        ));
        return false;
      }

      if (_isAborted) {
        await _sendAbort(controlChar);
        return false;
      }

      // 6. Compute optimal chunk size based on negotiated MTU
      final activeMtu = device.mtuNow;
      final chunkSize = forcedChunkSize ?? max(20, min(activeMtu - 3, 244));
      final totalChunks = (totalSize / chunkSize).ceil();

      _emit(BleOtaProgress(
        status: BleOtaStatus.transferring,
        bytesSent: 0,
        totalBytes: totalSize,
        progress: 0.0,
        message: 'Transfert du binaire en cours ($totalChunks paquets)...',
      ));

      final stopwatch = Stopwatch()..start();
      int bytesSent = 0;

      // 7. Stream raw data chunks without response
      for (int i = 0; i < totalSize; i += chunkSize) {
        if (_isAborted) {
          await _sendAbort(controlChar);
          return false;
        }

        final end = min(i + chunkSize, totalSize);
        final chunk = firmwareBytes.sublist(i, end);

        await dataChar.write(chunk, withoutResponse: true);
        bytesSent += chunk.length;

        // Calculate speed & estimated remaining duration
        final elapsedSeconds = stopwatch.elapsedMilliseconds / 1000.0;
        final speedKbps = elapsedSeconds > 0 ? (bytesSent / 1024.0) / elapsedSeconds : 0.0;
        final remainingBytes = totalSize - bytesSent;
        final estimatedSec = (speedKbps > 0) ? (remainingBytes / 1024.0) / speedKbps : null;

        _emit(BleOtaProgress(
          status: BleOtaStatus.transferring,
          bytesSent: bytesSent,
          totalBytes: totalSize,
          progress: bytesSent / totalSize,
          speedKbps: speedKbps,
          estimatedTimeRemaining: estimatedSec != null
              ? Duration(seconds: estimatedSec.ceil())
              : null,
          message: 'Transfert en cours (${(bytesSent / 1024).toStringAsFixed(0)} / ${(totalSize / 1024).toStringAsFixed(0)} Ko)...',
        ));

        // Pacing delay to avoid saturating BLE buffer queues
        if (pacingDelayMs > 0) {
          await Future.delayed(Duration(milliseconds: pacingDelayMs));
        }
      }

      stopwatch.stop();

      // 8. Finalize update by sending OTA_END (0x02)
      _emit(_currentProgress.copyWith(
        status: BleOtaStatus.finalizing,
        bytesSent: totalSize,
        progress: 1.0,
        message: 'Vérification de l\'intégrité de l\'image et bascule de boot...',
      ));

      await controlChar.write([BleConstants.otaCmdEnd], withoutResponse: false);

      // 9. Await OTA_SUCCESS confirmation (timeout 15 seconds)
      try {
        await finalCompleter.future.timeout(const Duration(seconds: 15));
      } on TimeoutException {
        _emit(const BleOtaProgress(
          status: BleOtaStatus.error,
          message: 'Délai dépassé lors de la validation finale du firmware.',
        ));
        return false;
      }

      _emit(BleOtaProgress(
        status: BleOtaStatus.success,
        bytesSent: totalSize,
        totalBytes: totalSize,
        progress: 1.0,
        message: 'Mise à jour réussie ! Redémarrage de la chaussure en cours...',
      ));

      return true;
    } catch (e) {
      _emit(BleOtaProgress(
        status: BleOtaStatus.error,
        message: 'Erreur pendant la mise à jour OTA : $e',
      ));
      return false;
    } finally {
      await _controlSubscription?.cancel();
      _controlSubscription = null;
    }
  }

  Future<void> _sendAbort(BluetoothCharacteristic controlChar) async {
    try {
      await controlChar.write([BleConstants.otaCmdAbort], withoutResponse: false);
    } catch (_) {}
    _emit(_currentProgress.copyWith(
      status: BleOtaStatus.aborted,
      message: 'Mise à jour interrompue.',
    ));
  }

  void dispose() {
    _controlSubscription?.cancel();
    _controlSubscription = null;
    _progressController.close();
  }
}
