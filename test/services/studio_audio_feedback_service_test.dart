import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:healthkicks_mobile/services/audio/audio_tone_generator.dart';
import 'package:healthkicks_mobile/services/audio/studio_audio_feedback_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioToneGenerator', () {
    test('generates valid 16-bit PCM Mono WAV byte buffer', () {
      final bytes = AudioToneGenerator.generateSineWaveWav(
        frequencyHz: 650,
        durationSec: 0.1,
        sampleRate: 22050,
        volume: 0.5,
        applyEnvelope: true,
      );

      expect(bytes, isA<Uint8List>());
      // RIFF header magic: 'RIFF'
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      // WAVE header magic: 'WAVE'
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      // Subchunk1 'fmt '
      expect(String.fromCharCodes(bytes.sublist(12, 16)), 'fmt ');
      // Subchunk2 'data'
      expect(String.fromCharCodes(bytes.sublist(36, 40)), 'data');

      // ByteData inspection
      final byteData = ByteData.sublistView(bytes);
      // PCM format (1)
      expect(byteData.getUint16(20, Endian.little), 1);
      // Mono channel (1)
      expect(byteData.getUint16(22, Endian.little), 1);
      // Sample rate
      expect(byteData.getUint32(24, Endian.little), 22050);
      // Bits per sample (16)
      expect(byteData.getUint16(34, Endian.little), 16);

      // Data size: 22050 * 0.1 = 2205 samples * 2 bytes = 4410 bytes
      final numSamples = (22050 * 0.1).round();
      final expectedDataSize = numSamples * 2;
      expect(byteData.getUint32(40, Endian.little), expectedDataSize);
      expect(bytes.length, 44 + expectedDataSize);
    });

    test('generates seamless loop buffer without envelope', () {
      final bytes = AudioToneGenerator.generateSineWaveWav(
        frequencyHz: 882,
        durationSec: 1.0,
        sampleRate: 22050,
        volume: 0.6,
        applyEnvelope: false,
      );

      final byteData = ByteData.sublistView(bytes);
      const expectedDataSize = 22050 * 2;
      expect(byteData.getUint32(40, Endian.little), expectedDataSize);
      expect(bytes.length, 44 + expectedDataSize);
    });
  });

  group('StudioAudioFeedbackService', () {
    test('initial state and methods run safely without platform exception', () async {
      final service = StudioAudioFeedbackService();

      expect(service.isContinuousPlaying, isFalse);
      expect(service.countdownBeepsPlayed, 0);

      // Verify playing countdown beep increments counter and catches missing plugin safely
      await service.playCountdownBeep();
      expect(service.countdownBeepsPlayed, 1);

      // Verify start continuous tone updates state
      await service.startContinuousRecordingTone();
      expect(service.isContinuousPlaying, isTrue);

      // Calling start again when already playing is a no-op
      await service.startContinuousRecordingTone();
      expect(service.isContinuousPlaying, isTrue);

      // Verify stop continuous tone resets state
      await service.stopContinuousTone();
      expect(service.isContinuousPlaying, isFalse);

      // Verify finished chime stops tone and runs safely
      await service.startContinuousRecordingTone();
      await service.playFinishedChime();
      expect(service.isContinuousPlaying, isFalse);

      // Verify dispose cleans up safely
      await service.dispose();
      expect(service.isContinuousPlaying, isFalse);
    });
  });
}
