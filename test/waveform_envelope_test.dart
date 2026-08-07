import 'package:flutter_test/flutter_test.dart';

import 'package:playa_clean/services/waveform_envelope_service.dart';

double _mean(List<double> values) {
  if (values.isEmpty) return 0.0;
  return values.reduce((a, b) => a + b) / values.length;
}

void main() {
  test('native extract cap allows long audiobook chapters', () {
    expect(
      WaveformEnvelopeService.maxNativeExtractBytes,
      greaterThanOrEqualTo(400 * 1024 * 1024),
    );
  });

  test('extract timeout scales with file size', () {
    final small = WaveformEnvelopeService.extractTimeoutFor(20 * 1024 * 1024);
    final chapter =
        WaveformEnvelopeService.extractTimeoutFor(125 * 1024 * 1024);
    final huge = WaveformEnvelopeService.extractTimeoutFor(400 * 1024 * 1024);

    expect(small, const Duration(seconds: 9));
    expect(chapter, const Duration(seconds: 15));
    expect(huge, const Duration(seconds: 28));
    expect(huge.inSeconds, lessThanOrEqualTo(90));
  });

  test('extract timeout is floored and capped', () {
    expect(
      WaveformEnvelopeService.extractTimeoutFor(0).inSeconds,
      8,
    );
    expect(
      WaveformEnvelopeService.extractTimeoutFor(4096 * 1024 * 1024).inSeconds,
      90,
    );
  });

  test('fast extract cap covers duration-budgeted decodes', () {
    // Native self-budget for an 81-min chapter is duration/8 + 45s = 653s;
    // the Dart cap (900s) must sit above it and above any byte-based need.
    expect(WaveformEnvelopeService.fastExtractCap.inSeconds, 900);
    expect(
      WaveformEnvelopeService.fastExtractCap,
      greaterThan(const Duration(seconds: 653)),
    );
    expect(
      WaveformEnvelopeService.fastExtractCap,
      greaterThan(WaveformEnvelopeService.extractTimeoutFor(400 * 1024 * 1024)),
    );
  });

  test('procedural fallback is deterministic per path', () {
    const path = r'C:\Music\Alpha Drive.mp3';
    final a = WaveformEnvelopeService.instance.proceduralFallback(path);
    final b = WaveformEnvelopeService.instance.proceduralFallback(path);

    expect(a, b);
    expect(a.length, WaveformEnvelopeService.defaultSamples);
  });

  test('procedural fallback differs across paths', () {
    final a = WaveformEnvelopeService.instance.proceduralFallback('a.mp3');
    final b = WaveformEnvelopeService.instance.proceduralFallback('b.mp3');

    expect(a, isNot(equals(b)));
  });

  test('procedural fallback values are bounded', () {
    final data = WaveformEnvelopeService.instance.proceduralFallback('bound.mp3');
    for (final v in data) {
      expect(v, greaterThanOrEqualTo(0.05));
      expect(v, lessThanOrEqualTo(1.0));
    }
  });

  test('procedural fallback has an intro ramp quieter than the body', () {
    final data = WaveformEnvelopeService.instance.proceduralFallback('intro.mp3');
    final introCount = (data.length * 0.03).floor();
    final introMean = _mean(data.sublist(0, introCount));
    final bodyMean = _mean(data.sublist(introCount, (data.length * 0.85).floor()));

    expect(introMean, lessThan(bodyMean * 0.8));
  });

  test('procedural fallback has an outro fade quieter than the body', () {
    final data = WaveformEnvelopeService.instance.proceduralFallback('outro.mp3');
    final outroStart = (data.length * 0.95).floor();
    final outroMean = _mean(data.sublist(outroStart));
    final bodyMean = _mean(data.sublist(0, (data.length * 0.85).floor()));

    expect(outroMean, lessThan(bodyMean * 0.8));
  });

  test('empty path falls back to a deterministic envelope', () {
    final a = WaveformEnvelopeService.instance.proceduralFallback('   ');
    final b = WaveformEnvelopeService.instance.proceduralFallback('');

    expect(a, b);
    expect(a.isNotEmpty, isTrue);
  });
}
