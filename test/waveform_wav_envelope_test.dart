import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:playa_clean/services/waveform_envelope_service.dart';

double _mean(List<double> values) {
  if (values.isEmpty) return 0.0;
  return values.reduce((a, b) => a + b) / values.length;
}

/// Builds a RIFF/WAVE container with interleaved 16-bit signed PCM samples.
Uint8List _buildWavPcm16({
  required int channels,
  required int sampleRate,
  required List<int> samples,
}) {
  final dataLen = samples.length * 2;
  final b = BytesBuilder();
  void text(String s) => b.add(s.codeUnits);
  void le16(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
  void le32(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  text('RIFF');
  le32(36 + dataLen);
  text('WAVE');
  text('fmt ');
  le32(16);
  le16(1); // PCM
  le16(channels);
  le32(sampleRate);
  le32(sampleRate * channels * 2);
  le16(channels * 2);
  le16(16);
  text('data');
  le32(dataLen);
  for (final s in samples) {
    le16(s & 0xFFFF);
  }
  return b.toBytes();
}

/// Builds a WAV with 32-bit IEEE float samples.
Uint8List _buildWavFloat32({
  required int sampleRate,
  required List<double> samples,
}) {
  final dataLen = samples.length * 4;
  final bytes = Uint8List(44 + dataLen);
  final bd = ByteData.sublistView(bytes);
  void text(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      bd.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  bd.setUint32(4, 36 + dataLen, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  bd.setUint32(16, 16, Endian.little);
  bd.setUint16(20, 3, Endian.little); // IEEE float
  bd.setUint16(22, 1, Endian.little); // mono
  bd.setUint32(24, sampleRate, Endian.little);
  bd.setUint32(28, sampleRate * 4, Endian.little);
  bd.setUint16(32, 4, Endian.little);
  bd.setUint16(34, 32, Endian.little);
  text(36, 'data');
  bd.setUint32(40, dataLen, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    bd.setFloat32(44 + i * 4, samples[i], Endian.little);
  }
  return bytes;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sampleRate = 44100;
  final loudSine = List<int>.generate(
    sampleRate,
    (i) => (20000 * sin(2 * pi * 1000 * i / sampleRate)).round(),
  );
  final silence = List<int>.filled(sampleRate, 0);

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('waveform_wav_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('extracts a real envelope from 16-bit PCM WAV', () async {
    final path = '${tempDir.path}/loud_then_silence.wav';
    File(path)
        .writeAsBytesSync(_buildWavPcm16(
          channels: 1,
          sampleRate: sampleRate,
          samples: [...loudSine, ...silence],
        ));

    final envelope = await WaveformEnvelopeService.instance.loadEnvelope(
      path,
      samples: 200,
    );

    expect(envelope.length, 200);
    final firstHalf = _mean(envelope.sublist(0, 80));
    final secondHalf = _mean(envelope.sublist(120));
    expect(firstHalf, greaterThan(0.6));
    expect(secondHalf, lessThan(0.15));
  });

  test('extracts a real envelope from float32 WAV', () async {
    final path = '${tempDir.path}/float.wav';
    File(path).writeAsBytesSync(_buildWavFloat32(
      sampleRate: sampleRate,
      samples: [
        ...List.generate(
          sampleRate,
          (i) => 0.8 * sin(2 * pi * 440 * i / sampleRate),
        ),
        ...List.filled(sampleRate, 0.0),
      ],
    ));

    final envelope = await WaveformEnvelopeService.instance.loadEnvelope(
      path,
      samples: 200,
    );

    expect(envelope.length, 200);
    final firstHalf = _mean(envelope.sublist(0, 80));
    final secondHalf = _mean(envelope.sublist(120));
    expect(firstHalf, greaterThan(0.6));
    expect(secondHalf, lessThan(0.15));
  });

  test('stereo 24-bit WAV decodes', () async {
    final samples = <int>[];
    for (var i = 0; i < 12000; i++) {
      final v = (12000 * sin(2 * pi * 660 * i / sampleRate)).round();
      samples..add(v)..add(-v); // interleave L/R
    }
    final path = '${tempDir.path}/stereo24.wav';
    final b = BytesBuilder();
    void text(String s) => b.add(s.codeUnits);
    void le16(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
    void le32(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
    void le24(int v) => b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF]);
    final dataLen = samples.length * 3;
    text('RIFF');
    le32(36 + dataLen);
    text('WAVE');
    text('fmt ');
    le32(16);
    le16(1);
    le16(2); // stereo
    le32(sampleRate);
    le32(sampleRate * 6);
    le16(6);
    le16(24);
    text('data');
    le32(dataLen);
    for (final s in samples) {
      le24(s & 0xFFFFFF);
    }
    File(path).writeAsBytesSync(b.toBytes());

    final envelope = await WaveformEnvelopeService.instance.loadEnvelope(
      path,
      samples: 100,
    );

    expect(envelope.length, 100);
    expect(_mean(envelope), greaterThan(0.3));
  });

  test('non-WAV file falls back to procedural envelope', () async {
    final path = '${tempDir.path}/track.mp3';
    File(path).writeAsBytesSync(utf8.encode('ID3 fake data'));

    final envelope = await WaveformEnvelopeService.instance.loadEnvelope(
      path,
      samples: 120,
    );
    final procedural =
        WaveformEnvelopeService.instance.proceduralFallback(path, samples: 120);

    expect(envelope, procedural);
    expect(envelope.length, 120);
  });
}
