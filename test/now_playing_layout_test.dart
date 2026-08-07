import 'package:flutter_test/flutter_test.dart';
import 'package:playa_clean/ui/now_playing_layout.dart';
import 'package:playa_clean/ui/waveform_widget.dart';

void main() {
  test('music portrait metrics use 8pt grid and standard ship fill', () {
    const layout = NowPlayingLayoutMetrics(
      isLandscape: false,
      isAudiobook: false,
      hasWaveform: true,
    );

    expect(NowPlayingLayoutMetrics.waveformPortrait % 8, 0);
    expect(NowPlayingLayoutMetrics.waveformLandscape % 8, 0);
    expect(NowPlayingLayoutMetrics.turntableScale, greaterThan(0.0));
    expect(layout.waveformMode, WaveformDisplayMode.standard);
    expect(layout.expectedShipLength, 96 * 0.7125);
  });

  test('turntable scale is applied once in portrait', () {
    const layout = NowPlayingLayoutMetrics(
      isLandscape: false,
      isAudiobook: false,
      hasWaveform: true,
    );

    const viewportH = 700.0;
    const viewportW = 360.0;
    final dock = layout.dockHeight;
    final side = layout.turntableSide(
      maxWidth: viewportW,
      maxHeight: viewportH,
      viewportHeight: viewportH,
    );

    const rawCap = viewportH * NowPlayingLayoutMetrics.turntableMaxPortraitShare;
    final rawBudget = viewportH - dock;
    final expectedRaw = [viewportW, rawBudget, rawCap].reduce((a, b) => a < b ? a : b);
    expect(side, closeTo(expectedRaw * NowPlayingLayoutMetrics.turntableScale, 0.01));
  });

  test('landscape turntable uses panel min side', () {
    const layout = NowPlayingLayoutMetrics(
      isLandscape: true,
      isAudiobook: false,
      hasWaveform: true,
    );

    final side = layout.turntableSide(maxWidth: 400, maxHeight: 300);
    expect(side, closeTo(300 * NowPlayingLayoutMetrics.turntableScale, 0.01));
  });

  test('dock scale grows into leftover viewport', () {
    const layout = NowPlayingLayoutMetrics(
      isLandscape: false,
      isAudiobook: false,
      hasWaveform: true,
    );

    final intrinsic = layout.dockHeight;
    final roomy = layout.dockScaleFor(intrinsic * 1.2);
    final tight = layout.dockScaleFor(intrinsic * 0.7);

    expect(roomy, greaterThan(1.0));
    expect(tight, lessThan(1.0));
    expect(roomy, lessThanOrEqualTo(NowPlayingLayoutMetrics.dockMaxUpscale));
  });

  test('audiobook uses calm waveform mode', () {
    const layout = NowPlayingLayoutMetrics(
      isLandscape: false,
      isAudiobook: true,
      hasWaveform: true,
    );

    expect(layout.waveformMode, WaveformDisplayMode.calm);
    expect(layout.shipFill, NowPlayingLayoutMetrics.shipFillCalm);
  });
}