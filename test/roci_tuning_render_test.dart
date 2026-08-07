// Scratch render harness: paints the shared RocinanteShipPainter at several
// accents / scales and writes PNGs to the temp opencode dir for eyeballing.
// Also prints lightweight pixel stats so shape/glow changes can be verified
// without an image viewer. NOT a real test — regenerated as needed.
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playa_clean/ui/rocinante_ship_painter.dart';

const _outDir = r'C:\Users\Green\AppData\Local\Temp\opencode';

class _Stats {
  final int footprint;
  final int bright;
  final int accent;
  const _Stats(this.footprint, this.bright, this.accent);
}

Future<_Stats> _imageStats(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  int foot = 0, bright = 0, accent = 0;
  for (int i = 0; i < bytes.length; i += 4) {
    final r = bytes[i];
    final g = bytes[i + 1];
    final b = bytes[i + 2];
    final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    if (lum > 26) foot++;
    if (lum > 128) bright++;
    if (r > g && r > b && r > 80 && (r - g).abs() > 30) accent++;
  }
  return _Stats(foot, bright, accent);
}

Future<void> _render(
  String name, {
  required double shipLen,
  Color accent = const Color(0xFF00E5FF),
  double time = 4.0,
  double beat = 0.6,
  bool plume = true,
  bool diamonds = true,
}) async {
  const w = 640.0;
  const h = 360.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  canvas.drawRect(
    const Rect.fromLTWH(0, 0, w, h),
    Paint()..color = const Color(0xFF070A0F),
  );

  canvas.save();
  canvas.translate(w / 2, h / 2 + shipLen * 0.05);
  canvas.rotate(pi / 2);

  RocinanteShipPainter(
    shipLen: shipLen,
    color: accent,
    timeSeconds: time,
    beatStrength: beat,
    drawPlume: plume,
    drawDiamonds: diamonds,
  ).paint(canvas, Size(shipLen, shipLen));

  canvas.restore();

  final picture = recorder.endRecording();
  final image = await picture.toImage(w.toInt(), h.toInt());
  final stats = await _imageStats(image);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  if (bytes == null) throw StateError('png encode failed');
  final file = File('$_outDir\\$name.png');
  await file.writeAsBytes(bytes.buffer.asUint8List());
  // ignore: avoid_print
  print('rendered $_outDir\\$name.png '
      'foot=${stats.footprint} bright=${stats.bright} red=${stats.accent}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('render Roci tuning matrix', (tester) async {
    await tester.runAsync(() async {
      // Large hero renders across accents / thrust.
      await _render('roci_hero_cyan', shipLen: 260, accent: const Color(0xFF00E5FF));
      await _render('roci_hero_gold', shipLen: 260, accent: const Color(0xFFC9A86A));
      await _render('roci_hero_red', shipLen: 260, accent: const Color(0xFFEF4444));
      await _render('roci_beat_00', shipLen: 260, beat: 0.0);
      await _render('roci_beat_10', shipLen: 260, beat: 1.0);
      // Actual in-app scales.
      await _render('roci_wave_scale', shipLen: 68);
      await _render('roci_compact_scale', shipLen: 43);
      await _render('roci_screensaver_scale', shipLen: 30, plume: false);
    });
  });
}
