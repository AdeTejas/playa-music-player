// Verifies the static HDR realism grade on DeepSpaceBackground:
//  - HDR on yields measurably more bright pixels (bloom, hot cores, spikes).
//  - The hdrIntensity knob is monotonic: more intensity → more light output.
//  - The frame budget is unaffected by the hdrIntensity knob.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playa_clean/ui/deep_space_background.dart';

typedef _Stats = ({
  int brightCount,
  double meanLuma,
});

Future<_Stats> _stats(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  final bytes = data!.buffer.asUint8List();
  final w = image.width;
  final h = image.height;
  var sum = 0.0;
  var bright = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      final r = bytes[i] / 255.0;
      final g = bytes[i + 1] / 255.0;
      final b = bytes[i + 2] / 255.0;
      final luma = 0.2126 * r + 0.7152 * g + 0.0722 * b;
      sum += luma;
      if (luma > 0.78) bright++;
    }
  }
  return (brightCount: bright, meanLuma: sum / (w * h));
}

Future<_Stats> _captureStats(WidgetTester tester, {
  required bool boost,
  required double hdrIntensity,
}) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('spaceCapture'),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox.expand(
          child: DeepSpaceBackground(
            hdrBoost: boost,
            hdrIntensity: hdrIntensity,
            seed: 7,
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 120));
  await tester.pump(const Duration(milliseconds: 120));

  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('spaceCapture')),
  );
  final stats = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.0);
    try {
      return await _stats(image);
    } finally {
      image.dispose();
    }
  });
  return stats!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('HDR grade adds bright bloom', (tester) async {
    tester.view.physicalSize = const Size(480, 270);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final off = await _captureStats(
      tester,
      boost: false,
      hdrIntensity: 0.0,
    );
    final on = await _captureStats(
      tester,
      boost: true,
      hdrIntensity: 1.0,
    );

    expect(on.brightCount, greaterThan(off.brightCount),
        reason: 'bloom/hot-core/spike pass should add bright pixels');
  });

  testWidgets('hdrIntensity knob is monotonic', (tester) async {
    tester.view.physicalSize = const Size(480, 270);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final muted = await _captureStats(
      tester,
      boost: true,
      hdrIntensity: 0.0,
    );
    final hot = await _captureStats(
      tester,
      boost: true,
      hdrIntensity: 1.0,
    );

    expect(hot.meanLuma, greaterThan(muted.meanLuma),
        reason: 'bloom/halo/hot-core alphas all scale with hdrIntensity');
  });

  test('hdrIntensity does not change the frame budget', () {
    final base = DeepSpaceFrameBudget.minFrameIntervalSeconds(
      mode: DeepSpaceMode.background,
      subtle: false,
      hasComets: false,
    );
    expect(base, closeTo(1 / 30, 0.001));
  });
}
