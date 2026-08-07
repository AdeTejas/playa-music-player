// Scratch: renders the RocinanteShipPainter into a tightly-cropped ASCII map
// so hull/detailing placement can be eyeballed without an image viewer.
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playa_clean/ui/rocinante_ship_painter.dart';

String _classify(double lum) {
  if (lum < 0.05) return ' ';
  if (lum < 0.13) return '.';
  if (lum < 0.24) return ':';
  if (lum < 0.38) return 'o';
  if (lum < 0.58) return '#';
  return '@';
}

Future<void> _asciiShip({
  required double shipLen,
  required int cols,
  required int rows,
  required double canvasW,
  required double canvasH,
  required Offset center,
  bool plume = false,
  bool rotate = true,
  Color accent = const Color(0xFF00E5FF),
  double time = 4.0,
  double beat = 0.5,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, canvasW, canvasH),
    Paint()..color = const Color(0xFF05070B),
  );

  canvas.save();
  canvas.translate(center.dx, center.dy);
  if (rotate) canvas.rotate(pi / 2);

  RocinanteShipPainter(
    shipLen: shipLen,
    color: accent,
    timeSeconds: time,
    beatStrength: beat,
    drawPlume: plume,
    drawDiamonds: plume,
  ).paint(canvas, Size(shipLen, shipLen));
  canvas.restore();

  final image = await recorder.endRecording().toImage(canvasW.toInt(), canvasH.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();

  final cellW = (canvasW / cols).ceil();
  final cellH = (canvasH / rows).ceil();
  final buf = StringBuffer();
  buf.writeln(
      '     ${List.generate(cols, (i) => i % 10 == 0 ? (i ~/ 10).toString() : ' ').join()}');
  for (int r = 0; r < rows; r++) {
    final line = StringBuffer();
    for (int c = 0; c < cols; c++) {
      double lum = 0;
      int hits = 0;
      for (int dy = 0; dy < cellH && (r * cellH + dy) < canvasH; dy++) {
        for (int dx = 0; dx < cellW && (c * cellW + dx) < canvasW; dx++) {
          final x = c * cellW + dx;
          final y = r * cellH + dy;
          final i = ((y * canvasW + x) * 4).toInt();
          final rr = bytes[i];
          final gg = bytes[i + 1];
          final bb = bytes[i + 2];
          lum += 0.2126 * rr + 0.7152 * gg + 0.0722 * bb;
          hits++;
        }
      }
      lum = hits == 0 ? 0 : lum / hits / 255;
      line.write(_classify(lum));
    }
    buf.writeln('${r.toString().padLeft(3)} |$line|');
  }
  // ignore: avoid_print
  print('=== shipLen=$shipLen plume=$plume rotate=$rotate '
      'canvas=${canvasW.toInt()}x${canvasH.toInt()} cell=$cellW x $cellH ===');
  // ignore: avoid_print
  print(buf);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('ASCII Roci layout', (tester) async {
    await tester.runAsync(() async {
      // High-res hero pass, flying right, dorsal (local -X) on top.
      // Hull is 0.95*shipLen long, ~0.24*shipLen tall; fins reach +/-0.18*shipLen.
      await _asciiShip(
        shipLen: 500,
        cols: 175,
        rows: 66,
        canvasW: 700,
        canvasH: 330,
        center: const Offset(350, 165),
        plume: false,
      );
      // Full scene including plume (extends ~1.55*shipLen aft = to the left).
      await _asciiShip(
        shipLen: 360,
        cols: 200,
        rows: 56,
        canvasW: 1000,
        canvasH: 280,
        center: const Offset(640, 140),
        plume: true,
      );

      // Waveform cursor scale (standard): shipLen ~40.
      await _asciiShip(
        shipLen: 40,
        cols: 90,
        rows: 30,
        canvasW: 180,
        canvasH: 60,
        center: const Offset(108, 30),
        plume: true,
      );
      // Waveform cursor scale (compact): shipLen ~22.
      await _asciiShip(
        shipLen: 22,
        cols: 90,
        rows: 30,
        canvasW: 180,
        canvasH: 60,
        center: const Offset(108, 30),
        plume: true,
      );
    });
  });
}
