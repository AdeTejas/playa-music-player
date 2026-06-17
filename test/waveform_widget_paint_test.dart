import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playa_clean/services/waveform_envelope_service.dart';
import 'package:playa_clean/ui/waveform_widget.dart';

void main() {
  testWidgets('PreciseWaveformPainter paints at progress zero without error', (
    tester,
  ) async {
    final data = WaveformEnvelopeService.instance.proceduralFallback(
      r'C:\music\track.mp3',
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CustomPaint(
          painter: PreciseWaveformPainter(
            waveformData: data,
            progress: 0,
            timeSeconds: 0,
            playedColor: const Color(0xFF00E5FF),
          ),
          size: const Size(400, 64),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('PreciseWaveformPainter paints mid-track without error', (
    tester,
  ) async {
    final data = WaveformEnvelopeService.instance.proceduralFallback(
      r'C:\music\track.mp3',
    );

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CustomPaint(
          painter: PreciseWaveformPainter(
            waveformData: data,
            progress: 0.42,
            timeSeconds: 12.5,
            playedColor: const Color(0xFF00E5FF),
            bpm: 128,
          ),
          size: const Size(400, 64),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}