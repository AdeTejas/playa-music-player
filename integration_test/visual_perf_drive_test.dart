// On-device frame-time probe for the Now Playing heavy scenes.
//
// Run in PROFILE mode on a real device so numbers reflect release-tier GPU
// rasterization (debug Dart is far too slow to be meaningful):
//
//   flutter drive --profile \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/visual_perf_drive_test.dart \
//     -d <device-id>
//
// Drives the two hottest production painters — full-HDR DeepSpaceBackground and
// the standard-mode PreciseWaveformPainter (Rocinante hero) — individually and
// combined, at full screen. Frames are forced through the engine with explicit
// tester.pump calls because the integration binding only presents frames on
// pump (vsync-driven frames are suppressed while a test body awaits), and
// engine FrameTiming reports are captured via addTimingsCallback. Build/raster
// averages are printed per scene. Assertions are deliberately minimal (frames
// must be captured) — budgets are applied after the hot paths are optimized.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:playa_clean/ui/deep_space_background.dart';
import 'package:playa_clean/ui/waveform_widget.dart';

enum _Scene { deepSpace, waveform, combined }

class _PerfProbe extends StatefulWidget {
  const _PerfProbe(this.scene);

  final _Scene scene;

  @override
  State<_PerfProbe> createState() => _PerfProbeState();
}

class _PerfProbeState extends State<_PerfProbe>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  final List<double> _data = List<double>.generate(
    240,
    (i) => (0.25 + 0.45 * (0.5 + 0.5 * sin(i * 0.35)) + 0.2 * Random(i).nextDouble())
        .clamp(0.12, 1.0),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * 6.0;
        final progress = 0.35 + 0.25 * sin(_controller.value * 2 * pi);
        final waveform = SizedBox.expand(
          child: CustomPaint(
            painter: PreciseWaveformPainter(
              waveformData: _data,
              progress: progress,
              timeSeconds: t,
              playedColor: const Color(0xFF00E5FF),
              unplayedColor: const Color(0xFF00E5FF).withValues(alpha: 0.1),
              bpm: 128,
              displayMode: WaveformDisplayMode.standard,
            ),
          ),
        );
        const deepSpace = DeepSpaceBackground(
          hdrBoost: true,
          hdrIntensity: 1.0,
          seed: 7,
        );
        switch (widget.scene) {
          case _Scene.deepSpace:
            return deepSpace;
          case _Scene.waveform:
            return waveform;
          case _Scene.combined:
            return Stack(
              fit: StackFit.expand,
              children: [deepSpace, waveform],
            );
        }
      },
    );
  }
}

Future<void> _measure(WidgetTester tester, _Scene scene) async {
  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: _PerfProbe(scene))),
  );

  // Warmup: let the deep-space nebula/far-layer caches bake before timing.
  await Future<void>.delayed(const Duration(seconds: 2));

  final timings = <FrameTiming>[];
  final TimingsCallback watcher = timings.addAll;
  SchedulerBinding.instance.addTimingsCallback(watcher);
  for (var i = 0; i < 150; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  SchedulerBinding.instance.removeTimingsCallback(watcher);

  final total = timings.length;
  if (total == 0) {
    fail('no frame timings arrived from engine during pump loop ($scene)');
  }

  var buildSum = Duration.zero;
  var rasterSum = Duration.zero;
  var buildWorst = Duration.zero;
  var rasterWorst = Duration.zero;
  var missedBuild = 0;
  var missedRaster = 0;
  const budget = Duration(milliseconds: 16);
  for (final timing in timings) {
    final b = timing.buildDuration;
    final r = timing.rasterDuration;
    buildSum += b;
    rasterSum += r;
    if (b > buildWorst) buildWorst = b;
    if (r > rasterWorst) rasterWorst = r;
    if (b > budget) missedBuild++;
    if (r > budget) missedRaster++;
  }
  final avgBuildMs = buildSum.inMicroseconds / total / 1000;
  final avgRasterMs = rasterSum.inMicroseconds / total / 1000;
  // ignore: avoid_print
  print('--- $scene ($total frames) ---');
  // ignore: avoid_print
  print('build  avg=${avgBuildMs.toStringAsFixed(2)}ms '
      'worst=${(buildWorst.inMicroseconds / 1000).toStringAsFixed(2)}ms');
  // ignore: avoid_print
  print('raster avg=${avgRasterMs.toStringAsFixed(2)}ms '
      'worst=${(rasterWorst.inMicroseconds / 1000).toStringAsFixed(2)}ms');
  // ignore: avoid_print
  print('missed budgets: build=$missedBuild raster=$missedRaster');
  // ignore: avoid_print
  print('sustained ~${(1000 / (avgBuildMs + avgRasterMs)).toStringAsFixed(0)}fps');

  // Regression budgets (S24 Ultra, profile, full 1440x3120). ~1.3-1.4x the
  // observed steady-state averages — loose enough for device load variance,
  // tight enough to catch a hot path reverting (e.g. the 180k-op dither).
  final avgTotal = avgBuildMs + avgRasterMs;
  final cap = switch (scene) {
    _Scene.deepSpace => 50.0,
    _Scene.waveform => 40.0,
    _Scene.combined => 75.0,
  };
  expect(avgTotal, lessThan(cap),
      reason: '$scene avg frame time ${avgTotal.toStringAsFixed(1)}ms exceeds '
          '${cap.toStringAsFixed(0)}ms regression cap');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('device frame-time probe: Now Playing heavy scenes', (tester) async {
    await _measure(tester, _Scene.deepSpace);
    await _measure(tester, _Scene.waveform);
    await _measure(tester, _Scene.combined);
  });
}
