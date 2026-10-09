import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'audio_tone_generator.dart';

/// Service managing audio feedback during Studio recording sessions:
/// - Distinct acoustic beeps on each countdown step.
/// - Continuous audio tone during the entire active recording window.
/// - Smooth shutdown upon recording completion or cancellation.
class StudioAudioFeedbackService {
  final AudioPlayer? _countdownPlayer;
  final AudioPlayer? _continuousPlayer;

  bool _isContinuousPlaying = false;
  bool get isContinuousPlaying => _isContinuousPlaying;

  int _countdownBeepsPlayed = 0;
  int get countdownBeepsPlayed => _countdownBeepsPlayed;

  static final Uint8List _countdownBeepBytes = AudioToneGenerator.generateSineWaveWav(
    frequencyHz: 650,
    durationSec: 0.15,
    volume: 0.75,
    applyEnvelope: true,
  );

  static final Uint8List _continuousToneBytes = AudioToneGenerator.generateSineWaveWav(
    frequencyHz: 882, // 882 Hz divides 22050 Hz into exact 25 integer cycles for seamless loop
    durationSec: 1.0,
    volume: 0.55,
    applyEnvelope: false,
  );

  static final Uint8List _finishedChimeBytes = AudioToneGenerator.generateSineWaveWav(
    frequencyHz: 1174, // High D6 pitch confirmation
    durationSec: 0.2,
    volume: 0.7,
    applyEnvelope: true,
  );

  StudioAudioFeedbackService({
    AudioPlayer? countdownPlayer,
    AudioPlayer? continuousPlayer,
    bool? enableAudio,
  })  : _countdownPlayer = countdownPlayer ?? _resolveDefaultPlayer(enableAudio),
        _continuousPlayer = continuousPlayer ?? _resolveDefaultPlayer(enableAudio);

  static AudioPlayer? _resolveDefaultPlayer(bool? enableAudio) {
    if (enableAudio == false) return null;
    // In headless Flutter test environments without audio backend, avoid instantiating native players
    if (enableAudio == null && !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
      return null;
    }
    try {
      return AudioPlayer();
    } catch (_) {
      return null;
    }
  }

  /// Emits a single crisp audio beep for a countdown tick.
  Future<void> playCountdownBeep() async {
    _countdownBeepsPlayed++;
    final player = _countdownPlayer;
    if (player == null) return;
    try {
      await player.stop().timeout(const Duration(milliseconds: 250), onTimeout: () {});
      await player.setReleaseMode(ReleaseMode.stop).timeout(const Duration(milliseconds: 250), onTimeout: () {});
      await player.play(BytesSource(_countdownBeepBytes)).timeout(const Duration(milliseconds: 250), onTimeout: () {});
    } catch (_) {
      // Gracefully ignored on platforms without audio driver or in headless tests.
    }
  }

  /// Starts emitting the continuous sound signal for the active recording phase.
  Future<void> startContinuousRecordingTone() async {
    if (_isContinuousPlaying) return;
    _isContinuousPlaying = true;
    final player = _continuousPlayer;
    if (player == null) return;
    try {
      await player.stop().timeout(const Duration(milliseconds: 250), onTimeout: () {});
      await player.setReleaseMode(ReleaseMode.loop).timeout(const Duration(milliseconds: 250), onTimeout: () {});
      await player.play(BytesSource(_continuousToneBytes)).timeout(const Duration(milliseconds: 250), onTimeout: () {});
    } catch (_) {
      // Gracefully ignored
    }
  }

  /// Stops the continuous sound signal immediately.
  Future<void> stopContinuousTone() async {
    if (!_isContinuousPlaying) return;
    _isContinuousPlaying = false;
    final player = _continuousPlayer;
    if (player == null) return;
    try {
      await player.stop().timeout(const Duration(milliseconds: 250), onTimeout: () {});
    } catch (_) {
      // Gracefully ignored
    }
  }

  /// Plays a short success chime when session finishes.
  Future<void> playFinishedChime() async {
    await stopContinuousTone();
    final player = _countdownPlayer;
    if (player == null) return;
    try {
      await player.stop().timeout(const Duration(milliseconds: 250), onTimeout: () {});
      await player.setReleaseMode(ReleaseMode.stop).timeout(const Duration(milliseconds: 250), onTimeout: () {});
      await player.play(BytesSource(_finishedChimeBytes)).timeout(const Duration(milliseconds: 250), onTimeout: () {});
    } catch (_) {
      // Gracefully ignored
    }
  }

  /// Cleans up audio players and active audio streams.
  Future<void> dispose() async {
    await stopContinuousTone();
    try {
      await _countdownPlayer?.dispose().timeout(const Duration(milliseconds: 250), onTimeout: () {});
      await _continuousPlayer?.dispose().timeout(const Duration(milliseconds: 250), onTimeout: () {});
    } catch (_) {
      // Gracefully ignored
    }
  }
}
