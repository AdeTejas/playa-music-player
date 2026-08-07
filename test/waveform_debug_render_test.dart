// Scratch debug harness: renders PreciseWaveformPainter at several progress /
// mode states and writes PNGs to the temp opencode dir for eyeballing.
// NOT a real test — regenerate as needed.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playa_clean/services/waveform_envelope_service.dart';
import 'package:playa_clean/ui/waveform_widget.dart';

const _tempDir = r'C:\Users\Green\AppData\Local\Temp\opencode\waveform';

Future<void> _capture(
  WidgetTester tester,
  Widget child,
  String name,
) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: ValueKey('capture_$name'),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: child,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));

  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(ValueKey('capture_$name')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.0);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('png encode failed');
    final out = File('$_tempDir\\$name.png');
    out.parent.createSync(recursive: true);
    await out.writeAsBytes(data.buffer.asUint8List());
    // ignore: avoid_print
    print('rendered ${out.path}');
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('render waveform debug matrix', (tester) async {
    tester.view.physicalSize = const Size(1200, 140);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final data = WaveformEnvelopeService.instance.proceduralFallback(
      r'C:\music\track.mp3',
    );

    Widget painter({
      required double progress,
      required double timeSeconds,
      double? bpm,
      WaveformDisplayMode mode = WaveformDisplayMode.standard,
    }) {
      return CustomPaint(
        painter: PreciseWaveformPainter(
          waveformData: data,
          progress: progress,
          timeSeconds: timeSeconds,
          playedColor: const Color(0xFF00E5FF),
          bpm: bpm,
          displayMode: mode,
        ),
        size: const Size(1200, 120),
      );
    }

    await _capture(
      tester,
      painter(progress: 0.0, timeSeconds: 0.0, bpm: 128),
      'std_p000_t00',
    );
    await _capture(
      tester,
      painter(progress: 0.25, timeSeconds: 12.5, bpm: 128),
      'std_p025_t12',
    );
    await _capture(
      tester,
      painter(progress: 0.5, timeSeconds: 25.0, bpm: 128),
      'std_p050_t25',
    );
    await _capture(
      tester,
      painter(progress: 0.75, timeSeconds: 37.5, bpm: 128),
      'std_p075_t37',
    );
    await _capture(
      tester,
      painter(progress: 0.95, timeSeconds: 47.5, bpm: 128),
      'std_p095_t47',
    );
    await _capture(
      tester,
      painter(progress: 0.5, timeSeconds: 25.0, bpm: 90),
      'std_p050_slow',
    );
    await _capture(
      tester,
      painter(
        progress: 0.5,
        timeSeconds: 25.0,
        bpm: 128,
        mode: WaveformDisplayMode.compact,
      ),
      'compact_p050',
    );
    await _capture(
      tester,
      painter(
        progress: 0.5,
        timeSeconds: 25.0,
        bpm: 128,
        mode: WaveformDisplayMode.calm,
      ),
      'calm_p050',
    );
    await _capture(
      tester,
      painter(
        progress: 0.5,
        timeSeconds: 25.0,
        bpm: 128,
        mode: WaveformDisplayMode.compact,
      ),
      'compact_no_diamonds',
    );
  });
}
