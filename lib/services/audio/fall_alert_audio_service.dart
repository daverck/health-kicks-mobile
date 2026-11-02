import 'dart:io';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Audio service responsible for triggering a repeating emergency siren sound
/// when a fall alert transitions to the escalated phase (ESCALATING / EXHAUSTED).
/// The siren automatically stops when the alert is cancelled or acknowledged.
class FallAlertAudioService {
  final AudioPlayer? _audioPlayer;
  bool _isPlaying = false;

  bool get isPlaying => _isPlaying;

  /// Generates a two-tone emergency siren WAV buffer (repeating 880 Hz and 660 Hz pulses).
  static final Uint8List _escalationSirenBytes = _generateSirenWav();

  FallAlertAudioService({
    AudioPlayer? audioPlayer,
    bool? enableAudio,
  }) : _audioPlayer = audioPlayer ?? _resolveDefaultPlayer(enableAudio);

  static AudioPlayer? _resolveDefaultPlayer(bool? enableAudio) {
    if (enableAudio == false) return null;
    if (enableAudio == null && !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
      return null;
    }
    try {
      return AudioPlayer();
    } catch (_) {
      return null;
    }
  }

  /// Builds a 1.2-second alternating two-tone alarm (0.6s at 880Hz, 0.6s at 660Hz)
  /// tailored for seamless looping with ReleaseMode.loop.
  static Uint8List _generateSirenWav({
    int sampleRate = 22050,
    double volume = 0.85,
  }) {
    const toneDurationSec = 0.3;
    const toneCount = 4; // High - Low - High - Low (1.2s total)
    const totalDurationSec = toneDurationSec * toneCount;
    final numSamples = (sampleRate * totalDurationSec).round();
    final dataSize = numSamples * 2;
    final totalSize = 44 + dataSize;
    final bytes = Uint8List(totalSize);
    final byteData = ByteData.sublistView(bytes);

    // RIFF chunk descriptor
    bytes[0] = 0x52; // 'R'
    bytes[1] = 0x49; // 'I'
    bytes[2] = 0x46; // 'F'
    bytes[3] = 0x46; // 'F'
    byteData.setUint32(4, 36 + dataSize, Endian.little);
    bytes[8] = 0x57; // 'W'
    bytes[9] = 0x41; // 'A'
    bytes[10] = 0x56; // 'V'
    bytes[11] = 0x45; // 'E'

    // "fmt " subchunk
    bytes[12] = 0x66; // 'f'
    bytes[13] = 0x6d; // 'm'
    bytes[14] = 0x74; // 't'
    bytes[15] = 0x20; // ' '
    byteData.setUint32(16, 16, Endian.little);
    byteData.setUint16(20, 1, Endian.little); // PCM
    byteData.setUint16(22, 1, Endian.little); // Mono
    byteData.setUint32(24, sampleRate, Endian.little);
    byteData.setUint32(28, sampleRate * 2, Endian.little);
    byteData.setUint16(32, 2, Endian.little);
    byteData.setUint16(34, 16, Endian.little); // 16 bits

    // "data" subchunk
    bytes[36] = 0x64; // 'd'
    bytes[37] = 0x61; // 'a'
    bytes[38] = 0x74; // 't'
    bytes[39] = 0x61; // 'a'
    byteData.setUint32(40, dataSize, Endian.little);

    final maxAmplitude = 32767.0 * volume.clamp(0.0, 1.0);
    final toneSamples = (sampleRate * toneDurationSec).round();

    for (int i = 0; i < numSamples; i++) {
      final toneIndex = (i ~/ toneSamples) % 2;
      // Alternate between 882 Hz (clean integer cycles with 22050) and 630 Hz
      final double freq = toneIndex == 0 ? 882.0 : 630.0;
      final double sampleVal = math.sin(2.0 * math.pi * freq * (i / sampleRate));
      final int pcm16 = (sampleVal * maxAmplitude).round().clamp(-32768, 32767);
      byteData.setInt16(44 + (i * 2), pcm16, Endian.little);
    }

    return bytes;
  }

  /// Starts repeating the escalation alarm sound in a continuous loop.
  Future<void> startEscalationAlarm() async {
    if (_isPlaying) return;
    _isPlaying = true;
    final player = _audioPlayer;
    if (player == null) return;
    try {
      await player.stop().timeout(const Duration(milliseconds: 250), onTimeout: () {});
      await player.setReleaseMode(ReleaseMode.loop).timeout(const Duration(milliseconds: 250), onTimeout: () {});
      await player.play(BytesSource(_escalationSirenBytes)).timeout(const Duration(milliseconds: 250), onTimeout: () {});
    } catch (_) {
      // Gracefully handled if audio device is unavailable
    }
  }

  /// Stops the emergency alarm immediately.
  Future<void> stopAlarm() async {
    if (!_isPlaying) return;
    _isPlaying = false;
    final player = _audioPlayer;
    if (player == null) return;
    try {
      await player.stop().timeout(const Duration(milliseconds: 250), onTimeout: () {});
    } catch (_) {
      // Gracefully handled
    }
  }

  /// Disposes audio player resources.
  Future<void> dispose() async {
    _isPlaying = false;
    final player = _audioPlayer;
    if (player == null) return;
    try {
      await player.stop().timeout(const Duration(milliseconds: 250), onTimeout: () {});
      await player.dispose().timeout(const Duration(milliseconds: 250), onTimeout: () {});
    } catch (_) {
      // Gracefully handled
    }
  }
}
