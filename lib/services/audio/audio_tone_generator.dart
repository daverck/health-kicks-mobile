import 'dart:math' as math;
import 'dart:typed_data';

/// Generates in-memory PCM 16-bit Mono WAV audio buffers for sound cues.
class AudioToneGenerator {
  /// Generates a valid mono 16-bit PCM WAV byte buffer for a sine wave tone.
  static Uint8List generateSineWaveWav({
    required double frequencyHz,
    required double durationSec,
    int sampleRate = 22050,
    double volume = 0.6,
    bool applyEnvelope = true,
  }) {
    final numSamples = (sampleRate * durationSec).round();
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
    byteData.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    byteData.setUint16(20, 1, Endian.little); // AudioFormat (1 for PCM)
    byteData.setUint16(22, 1, Endian.little); // NumChannels (1 = Mono)
    byteData.setUint32(24, sampleRate, Endian.little); // SampleRate
    byteData.setUint32(28, sampleRate * 2, Endian.little); // ByteRate (sampleRate * 1 * 16 / 8)
    byteData.setUint16(32, 2, Endian.little); // BlockAlign (1 * 16 / 8)
    byteData.setUint16(34, 16, Endian.little); // BitsPerSample (16 bits)

    // "data" subchunk
    bytes[36] = 0x64; // 'd'
    bytes[37] = 0x61; // 'a'
    bytes[38] = 0x74; // 't'
    bytes[39] = 0x61; // 'a'
    byteData.setUint32(40, dataSize, Endian.little);

    final maxAmplitude = 32767.0 * volume.clamp(0.0, 1.0);
    final attackReleaseSamples = math.min((sampleRate * 0.015).round(), numSamples ~/ 4);

    for (int i = 0; i < numSamples; i++) {
      double envelope = 1.0;
      if (applyEnvelope && attackReleaseSamples > 0) {
        if (i < attackReleaseSamples) {
          envelope = i / attackReleaseSamples;
        } else if (i > numSamples - attackReleaseSamples) {
          envelope = (numSamples - i) / attackReleaseSamples;
        }
      }

      final double sampleVal = math.sin(2.0 * math.pi * frequencyHz * (i / sampleRate));
      final int pcm16 = (sampleVal * maxAmplitude * envelope).round().clamp(-32768, 32767);
      byteData.setInt16(44 + (i * 2), pcm16, Endian.little);
    }

    return bytes;
  }
}
