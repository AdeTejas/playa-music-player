import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playa_clean/ui/waveform_widget.dart';

void main() {
  testWidgets('PreciseWaveformPainter paints at progress zero without error', (
    tester,
  ) async {
    final data = List.generate(100, (i) => 0.5);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CustomPaint(
          painter: PreciseWaveformPainter(
            waveformData: data,
            progress: 0,
            timeSeconds: 0,
            playedColor: const Color(0xFF00E5FF),
            unplayedColor: const Color(0xFF00E5FF).withValues(alpha: 0.1),
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
    final data = List.generate(100, (i) => 0.5);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CustomPaint(
          painter: PreciseWaveformPainter(
            waveformData: data,
            progress: 0.42,
            timeSeconds: 12.5,
            playedColor: const Color(0xFF00E5FF),
            unplayedColor: const Color(0xFF00E5FF).withValues(alpha: 0.1),
            bpm: 128,
          ),
          size: const Size(400, 64),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('PreciseWaveformPainter paints standard mode', (
    tester,
  ) async {
    final data = List.generate(100, (i) => 0.5);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: CustomPaint(
          painter: PreciseWaveformPainter(
            waveformData: data,
            progress: 0.6,
            timeSeconds: 30.0,
            playedColor: const Color(0xFFFF8A3D),
            unplayedColor: const Color(0xFFFF8A3D).withValues(alpha: 0.1),
            bpm: 120,
            displayMode: WaveformDisplayMode.standard,
          ),
          size: const Size(400, 64),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });
}
