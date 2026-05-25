import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class TorchShipPainter extends CustomPainter {
  final double height;
  final double progress;
  final double timeSeconds;
  final Color color;
  final double? bpm;
  final bool drawPlume;

  const TorchShipPainter({
    required this.height,
    required this.progress,
    required this.timeSeconds,
    required this.color,
    this.bpm,
    this.drawPlume = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final shipLen = height;
    final shipWidth = shipLen * 0.25;

    final accent = color;
    final accentCool = accent;
    final accentWarm = Color.lerp(const Color(0xFFD84315), accent, 0.45) ?? accent;

    final beatStrength = _computeBeatStrength(timeSeconds, bpm);

    _drawSideIons(canvas, shipLen, shipWidth, accent, accentCool, timeSeconds, beatStrength);

    if (drawPlume) {
      _drawCorePlume(canvas, shipLen, shipWidth, accent, accentCool, timeSeconds, beatStrength);
    }

    final hullPath = _buildTorchHull(shipLen, shipWidth);

    canvas.drawPath(
      hullPath.shift(const Offset(3, 6)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    final hullPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(-shipWidth / 2, 0),
        Offset(shipWidth / 2, 0),
        [
          const Color(0xFF0D0D0D),
          const Color(0xFF4A4A4A),
          const Color(0xFF1A1A1A),
          const Color(0xFF050505),
        ],
        [0.0, 0.3, 0.6, 1.0],
      );
    canvas.drawPath(hullPath, hullPaint);

    canvas.drawPath(
      hullPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = shipLen * 0.015
        ..color = accent.withValues(alpha: (0.14 + 0.22 * beatStrength).clamp(0.0, 1.0))
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
    );

    _drawHeatshieldTiles(canvas, hullPath, shipLen, shipWidth, accentWarm, timeSeconds);

    _drawMarkings(canvas, hullPath, shipLen, shipWidth, accentWarm, accentCool);

    _drawEngineBell(canvas, shipLen, shipWidth, accentWarm, timeSeconds);

    _drawNavLights(canvas, shipLen, shipWidth, timeSeconds);
  }

  double _computeBeatStrength(double timeSeconds, double? bpm) {
    final effectiveBpm = (bpm != null && bpm > 0) ? bpm : 120.0;
    final cycle = 60.0 / effectiveBpm;
    final phase = (timeSeconds % cycle) / cycle;
    return 0.35 + 0.65 * ((cos(2 * pi * phase) + 1.0) / 2.0);
  }

  void _drawSideIons(Canvas canvas, double shipLen, double shipWidth, Color accent, Color accentCool, double t, double beat) {
    final flicker = 1.0 + 0.12 * beat + 0.05 * sin(t * 22.0) + 0.03 * cos(t * 41.0);
    final wobble = 1.0 + 0.06 * sin(t * 9.0) + 0.04 * sin(t * 15.0 + 0.9);
    final plumeLen = shipLen * 1.55 * flicker;

    Path buildDrivePlume({required double width, required double lenScale}) {
      final baseY = shipLen * 0.45;
      final len = plumeLen * lenScale;
      final tipY = baseY + len;
      final c1Y = baseY + len * 0.25;
      final c2Y = baseY + len * 0.65;
      final twist = sin(t * 11.0) * width * 0.08;
      final p = Path();
      p.moveTo(-width, baseY);
      p.cubicTo(-width * 0.55 + twist * 0.4, c1Y, -width * 0.25 * wobble + twist, c2Y, 0, tipY);
      p.cubicTo(width * 0.25 * wobble - twist, c2Y, width * 0.55 - twist * 0.4, c1Y, width, baseY);
      p.close();
      return p;
    }

    final haloPath = buildDrivePlume(width: shipWidth * 0.55, lenScale: 1.25);
    final outerHaze = buildDrivePlume(width: shipWidth * 0.78, lenScale: 1.48);

    canvas.drawPath(
      haloPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, shipLen * 0.45),
          Offset(0, shipLen * 0.45 + plumeLen * 1.35),
          [accentCool.withValues(alpha: 0.38), accent.withValues(alpha: 0.16), accent.withValues(alpha: 0.0)],
          [0.0, 0.55, 1.0],
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
        ..blendMode = BlendMode.plus,
    );

    canvas.drawPath(
      outerHaze,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, shipLen * 0.45),
          Offset(0, shipLen * 0.45 + plumeLen * 1.6),
          [accent.withValues(alpha: 0.12), accent.withValues(alpha: 0.04), Colors.transparent],
          [0.0, 0.4, 1.0],
        )
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
  }

  void _drawCorePlume(Canvas canvas, double shipLen, double shipWidth, Color accent, Color accentCool, double t, double beat) {
    final flicker = 1.0 + 0.12 * beat + 0.05 * sin(t * 22.0) + 0.03 * cos(t * 41.0);
    final wobble = 1.0 + 0.06 * sin(t * 9.0) + 0.04 * sin(t * 15.0 + 0.9);
    final plumeLen = shipLen * 1.55 * flicker;

    Path buildDrivePlume({required double width, required double lenScale}) {
      final baseY = shipLen * 0.45;
      final len = plumeLen * lenScale;
      final tipY = baseY + len;
      final c1Y = baseY + len * 0.25;
      final c2Y = baseY + len * 0.65;
      final twist = sin(t * 11.0) * width * 0.08;
      final p = Path();
      p.moveTo(-width, baseY);
      p.cubicTo(-width * 0.55 + twist * 0.4, c1Y, -width * 0.25 * wobble + twist, c2Y, 0, tipY);
      p.cubicTo(width * 0.25 * wobble - twist, c2Y, width * 0.55 - twist * 0.4, c1Y, width, baseY);
      p.close();
      return p;
    }

    final corePath = buildDrivePlume(width: shipWidth * 0.22, lenScale: 1.00);

    canvas.drawCircle(
      Offset(0, shipLen * 0.45),
      shipWidth * 0.18,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(0, shipLen * 0.45),
          shipWidth * 0.40,
          [Colors.white.withValues(alpha: 0.75), accentCool.withValues(alpha: 0.40), Colors.transparent],
          [0.0, 0.4, 1.0],
        )
        ..blendMode = BlendMode.plus,
    );

    canvas.drawPath(
      corePath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, shipLen * 0.45),
          Offset(0, shipLen * 0.45 + plumeLen * 0.95),
          [Colors.white.withValues(alpha: 0.95), accentCool.withValues(alpha: 0.78), accentCool.withValues(alpha: 0.0)],
          [0.0, 0.22, 1.0],
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
        ..blendMode = BlendMode.plus,
    );

    final diamondPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.65)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);
    const diamondCount = 5;
    for (int i = 1; i <= diamondCount; i++) {
      final dy = shipLen * 0.45 + (plumeLen * 0.18 * i);
      final wob = 0.85 + 0.20 * sin(timeSeconds * 7.0 + i);
      final w = shipWidth * 0.32 * (1.0 - (i / (diamondCount + 1))) * wob;
      canvas.drawOval(Rect.fromCenter(center: Offset(0, dy), width: w, height: w * 0.6), diamondPaint);
    }
  }

  void _drawMarkings(Canvas canvas, Path hullPath, double shipLen, double shipWidth, Color accentWarm, Color accentCool) {
    canvas.save();
    canvas.clipPath(hullPath);

    final stripePaint = Paint()
      ..color = accentWarm
      ..style = PaintingStyle.stroke
      ..strokeWidth = shipLen * 0.05;

    canvas.drawLine(Offset(-shipWidth, -shipLen * 0.3), Offset(shipWidth, -shipLen * 0.3), stripePaint);
    canvas.drawLine(Offset(-shipWidth, -shipLen * 0.35), Offset(shipWidth, -shipLen * 0.35), stripePaint..strokeWidth = shipLen * 0.02);

    canvas.drawRect(
      Rect.fromCenter(center: const Offset(0, 0), width: shipWidth, height: shipLen * 0.15),
      Paint()..color = accentWarm,
    );

    final panelPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    canvas.drawLine(Offset(-shipWidth * 0.3, -shipLen * 0.1), Offset(shipWidth * 0.3, -shipLen * 0.1), panelPaint);
    canvas.drawLine(Offset(-shipWidth * 0.3, shipLen * 0.1), Offset(shipWidth * 0.3, shipLen * 0.1), panelPaint);
    canvas.drawLine(Offset(0, -shipLen * 0.4), Offset(0, shipLen * 0.4), panelPaint);

    final wearPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(-shipWidth * 0.28, -shipLen * 0.18), Offset(shipWidth * 0.05, -shipLen * 0.19), wearPaint);
    canvas.drawLine(Offset(-shipWidth * 0.15, shipLen * 0.07), Offset(shipWidth * 0.32, shipLen * 0.08), wearPaint);
    canvas.drawOval(Rect.fromCenter(center: Offset(-shipWidth * 0.12, shipLen * 0.18), width: shipWidth * 0.22, height: shipLen * 0.06), wearPaint..color = Colors.black.withValues(alpha: 0.12));

    canvas.drawLine(Offset(-shipWidth * 0.2, 0), Offset(shipWidth * 0.2, 0), Paint()..color = Colors.white.withValues(alpha: 0.9)..strokeWidth = 1.0);

    canvas.drawRect(
      Rect.fromCenter(center: Offset(0, -shipLen * 0.25), width: shipWidth * 0.4, height: shipLen * 0.05),
      Paint()..color = accentCool.withValues(alpha: 0.92)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
    );

    canvas.drawRect(
      Rect.fromCenter(center: Offset(0, -shipLen * 0.45), width: shipWidth * 0.1, height: shipLen * 0.1),
      Paint()..color = const Color(0xFF111111),
    );

    final idPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.82)
      ..strokeWidth = shipLen * 0.012
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(-shipWidth * 0.16, -shipLen * 0.07), Offset(shipWidth * 0.16, -shipLen * 0.07), idPaint);
    canvas.drawLine(Offset(-shipWidth * 0.16, -shipLen * 0.035), Offset(shipWidth * 0.16, -shipLen * 0.035), idPaint..strokeWidth = shipLen * 0.007);

    final regPaint = Paint()..color = Colors.white.withValues(alpha: 0.65)..strokeWidth = 0.6;
    canvas.drawLine(Offset(-shipWidth * 0.20, shipLen * 0.215), Offset(-shipWidth * 0.09, shipLen * 0.215), regPaint);
    canvas.drawLine(Offset(shipWidth * 0.09, shipLen * 0.215), Offset(shipWidth * 0.20, shipLen * 0.215), regPaint);

    canvas.restore();
  }

  void _drawHeatshieldTiles(Canvas canvas, Path hullPath, double shipLen, double shipWidth, Color accentWarm, double t) {
    canvas.save();
    canvas.clipPath(hullPath);

    final tileW = shipWidth * 0.16;
    final tileH = shipLen * 0.035;
    const gap = 0.8;
    const cols = 3;
    const rows = 5;
    final startY = shipLen * 0.12;
    final heatGlow = 0.08 + 0.04 * sin(t * 1.8);

    for (int c = 0; c < cols; c++) {
      for (int r = 0; r < rows; r++) {
        final x = (-(cols - 1) / 2 + c) * (tileW + gap);
        final y = startY + r * (tileH + gap);
        final rect = Rect.fromLTWH(x - tileW / 2, y, tileW, tileH);

        canvas.drawRect(rect, Paint()..color = const Color(0xFF0D0D0D));
        canvas.drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.3
            ..color = const Color(0xFF222222),
        );

        if (r >= rows - 2) {
          canvas.drawRect(
            rect,
            Paint()
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2)
              ..color = accentWarm.withValues(alpha: heatGlow * (r - rows + 3) / 2),
          );
        }
      }
    }

    canvas.restore();
  }

  void _drawEngineBell(Canvas canvas, double shipLen, double shipWidth, Color accentWarm, double t) {
    final bellW = shipWidth * 0.40;
    final bellH = shipLen * 0.08;
    final bellY = shipLen * 0.45;
    final glow = 0.5 + 0.3 * sin(t * 2.5);

    // Outer bell cone
    final bellPath = Path();
    bellPath.moveTo(-bellW, bellY);
    bellPath.lineTo(bellW, bellY);
    bellPath.lineTo(bellW * 0.85, bellY - bellH);
    bellPath.lineTo(-bellW * 0.85, bellY - bellH);
    bellPath.close();

    canvas.drawPath(
      bellPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, bellY - bellH),
          Offset(0, bellY),
          [const Color(0xFF111111), const Color(0xFF333333), const Color(0xFF0A0A0A)],
          [0.0, 0.5, 1.0],
        ),
    );

    // Bell rim glow
    canvas.drawPath(
      bellPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = accentWarm.withValues(alpha: 0.15 * glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // Tile pattern on bell surface
    for (int r = 0; r < 3; r++) {
      final yy = bellY - bellH * (0.2 + r * 0.3);
      final ww = bellW * (1.0 - r * 0.1);
      canvas.drawLine(
        Offset(-ww * 0.5, yy),
        Offset(ww * 0.5, yy),
        Paint()..color = const Color(0xFF1A1A1A)..strokeWidth = 0.4,
      );
    }
    for (int s = -2; s <= 2; s++) {
      if (s == 0) continue;
      final xx = s * bellW * 0.18;
      canvas.drawLine(
        Offset(xx, bellY - bellH * 0.15),
        Offset(xx * 0.92, bellY - bellH * 0.85),
        Paint()..color = const Color(0xFF1A1A1A)..strokeWidth = 0.4,
      );
    }

    // Inner nozzle (dark throat)
    final innerPath = Path();
    innerPath.moveTo(-bellW * 0.45, bellY);
    innerPath.lineTo(bellW * 0.45, bellY);
    innerPath.lineTo(bellW * 0.35, bellY - bellH * 0.5);
    innerPath.lineTo(-bellW * 0.35, bellY - bellH * 0.5);
    innerPath.close();

    canvas.drawPath(
      innerPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, bellY - bellH * 0.5),
          Offset(0, bellY),
          [const Color(0xFF000000), const Color(0xFF1A1A1A)],
        ),
    );

    // Heat glow at throat
    canvas.drawRect(
      Rect.fromLTWH(-bellW * 0.42, bellY - bellH * 0.15, bellW * 0.84, bellH * 0.3),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, bellY - bellH * 0.15),
          Offset(0, bellY + bellH * 0.15),
          [Colors.transparent, accentWarm.withValues(alpha: 0.25 * glow), Colors.transparent],
          [0.0, 0.5, 1.0],
        )
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    // Bright core glow at nozzle opening
    canvas.drawCircle(
      Offset(0, bellY),
      bellW * 0.3,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(0, bellY),
          bellW * 0.35,
          [Colors.white.withValues(alpha: 0.08 * glow), Colors.transparent],
          [0.0, 1.0],
        )
        ..blendMode = BlendMode.plus,
    );
  }

  void _drawNavLights(Canvas canvas, double shipLen, double shipWidth, double t) {
    final lightT = t * 1.8;
    final portAlpha = 0.65 + 0.35 * ((sin(lightT * 1.3) + 1) / 2);
    canvas.drawCircle(Offset(-shipWidth * 0.38, -shipLen * 0.32), shipLen * 0.012, Paint()..color = Color.lerp(const Color(0xFFB71C1C), Colors.redAccent, 0.3)!.withValues(alpha: portAlpha));
    final starAlpha = 0.65 + 0.35 * ((cos(lightT * 1.1) + 1) / 2);
    canvas.drawCircle(Offset(shipWidth * 0.38, -shipLen * 0.32), shipLen * 0.012, Paint()..color = Color.lerp(const Color(0xFF1B5E20), Colors.greenAccent, 0.3)!.withValues(alpha: starAlpha));
    final whiteAlpha = 0.3 + 0.7 * ((sin(lightT * 0.7) * cos(lightT * 0.4) + 1) / 2);
    canvas.drawCircle(Offset(0, -shipLen * 0.48), shipLen * 0.009, Paint()..color = Colors.white.withValues(alpha: whiteAlpha.clamp(0.15, 0.95)));
    canvas.drawCircle(Offset(0, shipLen * 0.48), shipLen * 0.007, Paint()..color = Colors.white.withValues(alpha: 0.45));
  }

  Path _buildTorchHull(double len, double width) {
    final path = Path();
    path.moveTo(0, -len * 0.5);
    path.lineTo(width * 0.25, -len * 0.4);
    path.lineTo(width * 0.35, -len * 0.15);
    path.lineTo(width * 0.4, len * 0.1);
    path.lineTo(width * 0.35, len * 0.45);
    path.lineTo(-width * 0.35, len * 0.45);
    path.lineTo(-width * 0.4, len * 0.1);
    path.lineTo(-width * 0.35, -len * 0.15);
    path.lineTo(-width * 0.25, -len * 0.4);
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant TorchShipPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      color != oldDelegate.color ||
      timeSeconds != oldDelegate.timeSeconds ||
      bpm != oldDelegate.bpm;
}
