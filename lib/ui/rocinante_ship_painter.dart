import 'dart:math';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The Rocinante ship as drawn on the Now Playing waveform cursor.
///
/// Local frame: nose −Y, engines +Y. Callers translate to the ship position
/// and rotate +π/2 so the ship flies rightward along the waveform / starfield.
/// Shared by the waveform cursor and the torch screensaver so both show the
/// exact same vessel.
///
/// Cosmetic layering, back to front:
///   L0 ambient engine aura · L1 plume · L2 hull form + rim lights +
///   clipped paint jobs · L3 engine stack · L4 command deck / cockpit ·
///   L5 PDC · L6 tail fins · L7 navigation lights.
class RocinanteShipPainter extends CustomPainter {
  final double shipLen;
  final Color color;
  final double timeSeconds;
  final double beatStrength;
  final bool drawPlume;
  final bool drawDiamonds;

  const RocinanteShipPainter({
    required this.shipLen,
    required this.color,
    required this.timeSeconds,
    required this.beatStrength,
    this.drawPlume = true,
    this.drawDiamonds = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final shipWidth = shipLen * 0.3;
    final rnd = Random((timeSeconds * 10).floor());

    final accent = color;
    final accentWarm = Color.lerp(accent, Colors.white, 0.25) ?? accent;
    // Finer greebles only earn their pixels when the hull is big enough to
    // read them (waveform ship). The tiny screensaver ship stays clean.
    final fullDetail = shipLen >= 48;

    // L0 — Ambient engine aura bleeding around the stern silhouette. Grounds
    // the vessel on the starfield / waveform instead of floating flat.
    if (drawPlume) {
      canvas.drawCircle(
        Offset(0, shipLen * 0.45),
        shipWidth * 1.2,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(0, shipLen * 0.45),
            shipWidth * 1.35,
            [
              accent.withValues(alpha: 0.22 + 0.16 * beatStrength),
              accent.withValues(alpha: 0.07),
              Colors.transparent,
            ],
            [0.0, 0.55, 1.0],
          )
          ..blendMode = BlendMode.plus,
      );
    }

    canvas.drawPath(
      _buildRociHull(shipLen, shipWidth).shift(const Offset(4, 8)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    if (drawPlume) {
      _drawPlume(canvas, shipLen, shipWidth, rnd, accent, accentWarm);
    }

    final hullPath = _buildRociHull(shipLen, shipWidth);
    _drawHullForm(
      canvas,
      shipLen,
      shipWidth,
      accent,
      accentWarm,
      beatStrength,
      hullPath,
      fullDetail,
    );

    _drawEngineStack(
      canvas,
      shipLen,
      shipWidth,
      accent,
      accentWarm,
      beatStrength,
    );
    _drawDeckAndCockpit(
      canvas,
      shipLen,
      shipWidth,
      accent,
      accentWarm,
      beatStrength,
      fullDetail,
    );
    _drawPdc(canvas, shipLen, shipWidth, beatStrength, rnd);
    _drawFins(canvas, shipLen, shipWidth, accent);
    _drawLights(canvas, shipLen, shipWidth);
  }

  // ---------------------------------------------------------------------------
  // L1 — Drive plume
  // ---------------------------------------------------------------------------
  void _drawPlume(
    Canvas canvas,
    double shipLen,
    double shipWidth,
    Random rnd,
    Color accent,
    Color accentWarm,
  ) {
    final flicker = 1.0 + 0.12 * beatStrength +
        0.05 * sin(timeSeconds * 22.0) +
        0.03 * cos(timeSeconds * 41.0);
    final wobble =
        1.0 +
        0.06 * sin(timeSeconds * 9.0) +
        0.04 * sin(timeSeconds * 15.0 + 0.9);
    final plumeLen = shipLen * 1.55 * flicker;
    final baseY = shipLen * 0.45;

    Path buildDrivePlume({required double width, required double lenScale}) {
      final len = plumeLen * lenScale;
      final tipY = baseY + len;
      final c1Y = baseY + len * 0.25;
      final c2Y = baseY + len * 0.65;
      final p = Path();
      p.moveTo(-width, baseY);
      p.cubicTo(-width * 0.55, c1Y, -width * 0.25 * wobble, c2Y, 0, tipY);
      p.cubicTo(width * 0.25 * wobble, c2Y, width * 0.55, c1Y, width, baseY);
      p.close();
      return p;
    }

    final corePath = buildDrivePlume(width: shipWidth * 0.22, lenScale: 1.00);
    final haloPath = buildDrivePlume(width: shipWidth * 0.55, lenScale: 1.25);
    final coronaPath = buildDrivePlume(width: shipWidth * 0.95, lenScale: 1.55);
    final hotCorePath = buildDrivePlume(width: shipWidth * 0.11, lenScale: 0.82);

    // Engine-mouth bloom: a bright spot right at the bell.
    canvas.drawCircle(
      Offset(0, baseY),
      shipWidth * 0.30,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(0, baseY),
          shipWidth * 0.55,
          [
            Colors.white.withValues(alpha: 0.55),
            accent.withValues(alpha: 0.25),
            Colors.transparent,
          ],
          [0.0, 0.4, 1.0],
        )
        ..blendMode = BlendMode.plus,
    );

    // Wide, very faint corona so the drive reads as a hot exhaust column.
    canvas.drawPath(
      coronaPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, baseY),
          Offset(0, baseY + plumeLen * 1.6),
          [
            accent.withValues(alpha: 0.12),
            accent.withValues(alpha: 0.04),
            Colors.transparent,
          ],
          [0.0, 0.5, 1.0],
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14)
        ..blendMode = BlendMode.plus,
    );

    canvas.drawPath(
      haloPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, baseY),
          Offset(0, baseY + plumeLen * 1.35),
          [
            accent.withValues(alpha: 0.38),
            accent.withValues(alpha: 0.16),
            accent.withValues(alpha: 0.0),
          ],
          [0.0, 0.55, 1.0],
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
        ..blendMode = BlendMode.plus,
    );

    canvas.drawPath(
      corePath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, baseY),
          Offset(0, baseY + plumeLen * 0.95),
          [
            Colors.white.withValues(alpha: 0.95),
            accent.withValues(alpha: 0.78),
            accent.withValues(alpha: 0.0),
          ],
          [0.0, 0.22, 1.0],
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
        ..blendMode = BlendMode.plus,
    );

    // Tight white-hot needle hugging the exhaust centerline.
    canvas.drawPath(
      hotCorePath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, baseY),
          Offset(0, baseY + plumeLen * 0.8),
          [
            Colors.white.withValues(alpha: 0.95),
            accentWarm.withValues(alpha: 0.45),
            Colors.transparent,
          ],
          [0.0, 0.30, 1.0],
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
        ..blendMode = BlendMode.plus,
    );

    if (drawDiamonds) {
      const diamondCount = 5;
      final diamondPaint =
          Paint()
            ..color = Colors.white.withValues(alpha: 0.65)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);

      for (int i = 1; i <= diamondCount; i++) {
        final dy = baseY + (plumeLen * 0.18 * i);
        final wob = 0.85 + 0.20 * sin(timeSeconds * 7.0 + i);
        final w = shipWidth * 0.32 * (1.0 - (i / (diamondCount + 1))) * wob;
        canvas.drawOval(
          Rect.fromCenter(center: Offset(0, dy), width: w, height: w * 0.6),
          diamondPaint,
        );
      }
    }

    if (rnd.nextDouble() > 0.85) {
      _drawRCS(canvas, Offset(-shipWidth * 0.4, -shipLen * 0.3), -pi / 2);
    }
    if (rnd.nextDouble() > 0.85) {
      _drawRCS(canvas, Offset(shipWidth * 0.4, -shipLen * 0.3), pi / 2);
    }
  }

  // ---------------------------------------------------------------------------
  // L2 — Hull form, rim lights and clipped paint jobs
  // ---------------------------------------------------------------------------
  void _drawHullForm(
    Canvas canvas,
    double shipLen,
    double shipWidth,
    Color accent,
    Color accentWarm,
    double beatStrength,
    Path hullPath,
    bool fullDetail,
  ) {
    // Base metallic plate: dark flanks, brighter spine.
    canvas.drawPath(
      hullPath,
      Paint()
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
        ),
    );

    // Soft accent rim around the whole silhouette — pulses with the beat.
    canvas.drawPath(
      hullPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = shipLen * 0.015
        ..color = accent
            .withValues(alpha: (0.20 + 0.22 * beatStrength).clamp(0.0, 1.0))
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
    );

    canvas.save();
    canvas.clipPath(hullPath);

    // Vertical spine highlight gives the hull cylindrical form.
    canvas.drawRect(
      Rect.fromLTRB(-shipWidth * 0.06, -shipLen * 0.5, shipWidth * 0.09, shipLen * 0.45),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(-shipWidth * 0.06, 0),
          Offset(shipWidth * 0.09, 0),
          [
            Colors.transparent,
            Colors.white.withValues(alpha: 0.10),
            Colors.transparent,
          ],
          [0.0, 0.5, 1.0],
        ),
    );

    // Dorsal (top, −X) rim light — the lit edge.
    final dorsal = Path()
      ..moveTo(0, -shipLen * 0.5)
      ..lineTo(-shipWidth * 0.25, -shipLen * 0.4)
      ..lineTo(-shipWidth * 0.35, -shipLen * 0.15)
      ..lineTo(-shipWidth * 0.4, shipLen * 0.1);
    canvas.drawPath(
      dorsal,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = shipLen * 0.010
        ..color = accent.withValues(alpha: 0.35 + 0.18 * beatStrength)
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // Ventral (belly) reflection — engine light bouncing off the underside.
    final ventral = Path()
      ..moveTo(0, -shipLen * 0.5)
      ..lineTo(shipWidth * 0.25, -shipLen * 0.4)
      ..lineTo(shipWidth * 0.35, -shipLen * 0.15)
      ..lineTo(shipWidth * 0.4, shipLen * 0.1);
    canvas.drawPath(
      ventral,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = shipLen * 0.008
        ..color = accent.withValues(alpha: 0.14 + 0.10 * beatStrength)
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );

    // Broad soft specular + tight bright streak along the dorsal deck line.
    canvas.drawPath(
      dorsal,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = shipLen * 0.026
        ..color = Colors.white.withValues(alpha: 0.08)
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawPath(
      dorsal,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = shipLen * 0.010
        ..color = Colors.white.withValues(alpha: 0.30)
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
    );

    // Accent racing stripes running fore→aft along the ventral flank. Lines
    // parallel to the hull read as paint job instead of wrap-around target
    // rings; they also survive the small waveform ship because they are long.
    final racerPaint =
        Paint()
          ..color = accentWarm.withValues(alpha: 0.42)
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(0.7, shipLen * 0.010);
    canvas.drawLine(
      Offset(shipWidth * 0.24, -shipLen * 0.26),
      Offset(shipWidth * 0.10, shipLen * 0.30),
      racerPaint,
    );
    canvas.drawLine(
      Offset(shipWidth * 0.32, -shipLen * 0.22),
      Offset(shipWidth * 0.18, shipLen * 0.30),
      racerPaint,
    );

    // Small waist accent block on the ventral mid (the Roci "belt" echo).
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(shipWidth * 0.26, shipLen * 0.02),
        width: shipLen * 0.05,
        height: shipLen * 0.14,
      ),
      Paint()..color = accentWarm.withValues(alpha: 0.55),
    );

    // Engine light cast sweeping up the belly.
    final hullCast = 0.10 + 0.16 * beatStrength;
    canvas.drawRect(
      Rect.fromLTRB(-shipWidth * 0.5, shipLen * 0.05, shipWidth * 0.5, shipLen * 0.45),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, shipLen * 0.45),
          Offset(0, shipLen * 0.05),
          [
            accent.withValues(alpha: hullCast),
            accent.withValues(alpha: hullCast * 0.4),
            Colors.transparent,
          ],
          [0.0, 0.5, 1.0],
        )
        ..blendMode = BlendMode.plus,
    );

    // Panel seams: layered deck striations nose→stern + slanted cross ribs.
    final seamPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.38)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(0.6, shipLen * 0.005);
    canvas.drawLine(
      Offset(-shipWidth * 0.24, -shipLen * 0.34),
      Offset(-shipWidth * 0.20, shipLen * 0.30),
      seamPaint,
    );
    canvas.drawLine(
      Offset(shipWidth * 0.22, -shipLen * 0.30),
      Offset(shipWidth * 0.20, shipLen * 0.30),
      seamPaint,
    );
    for (final yy in [-0.10, 0.14]) {
      canvas.drawLine(
        Offset(-shipWidth * 0.40, shipLen * yy),
        Offset(shipWidth * 0.40, shipLen * (yy - 0.02)),
        seamPaint,
      );
    }

    // Centerline spine seam nose→stern.
    canvas.drawLine(
      Offset(0, -shipLen * 0.42),
      Offset(0, shipLen * 0.40),
      Paint()
        ..color = accent.withValues(alpha: 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.5, shipLen * 0.004),
    );

    // Torpedo-bay panel seams near mid-hull.
    for (final yy in [0.02, 0.10]) {
      canvas.drawLine(
        Offset(-shipWidth * 0.36, shipLen * yy),
        Offset(shipWidth * 0.36, shipLen * (yy + 0.012)),
        seamPaint,
      );
    }

    // Double MCRN bow chevron at the nose.
    final chevronOuter = Path()
      ..moveTo(-shipWidth * 0.15, -shipLen * 0.34)
      ..lineTo(0, -shipLen * 0.48)
      ..lineTo(shipWidth * 0.15, -shipLen * 0.34)
      ..close();
    canvas.drawPath(chevronOuter, Paint()..color = accentWarm.withValues(alpha: 0.30));
    final chevron = Path()
      ..moveTo(-shipWidth * 0.12, -shipLen * 0.36)
      ..lineTo(-shipWidth * 0.02, -shipLen * 0.46)
      ..lineTo(shipWidth * 0.12, -shipLen * 0.36)
      ..close();
    canvas.drawPath(chevron, Paint()..color = accentWarm.withValues(alpha: 0.85));

    if (fullDetail) {
      // Dorsal rivet row.
      for (int i = 0; i < 6; i++) {
        canvas.drawCircle(
          Offset(-shipWidth * 0.32, -shipLen * 0.26 + i * shipLen * 0.10),
          max(0.4, shipLen * 0.004),
          Paint()..color = Colors.white.withValues(alpha: 0.10),
        );
      }

      // Hull number / ID dashes near the stern.
      final idPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.5, shipLen * 0.006);
      canvas.drawLine(
        Offset(-shipWidth * 0.14, shipLen * 0.20),
        Offset(shipWidth * 0.16, shipLen * 0.20),
        idPaint,
      );
      canvas.drawLine(
        Offset(-shipWidth * 0.14, shipLen * 0.245),
        Offset(shipWidth * 0.16, shipLen * 0.245),
        idPaint..strokeWidth = max(0.5, shipLen * 0.003),
      );

      // Extra deck plating seams.
      final platingPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.5, shipLen * 0.0035);
      for (final yy in [-0.16, 0.0, 0.16]) {
        canvas.drawLine(
          Offset(-shipWidth * 0.38, shipLen * yy),
          Offset(shipWidth * 0.38, shipLen * (yy - 0.02)),
          platingPaint,
        );
      }
    }

    canvas.restore();
  }

  // ---------------------------------------------------------------------------
  // L3 — Drive cowl, nozzle and engine glow
  // ---------------------------------------------------------------------------
  void _drawEngineStack(
    Canvas canvas,
    double shipLen,
    double shipWidth,
    Color accent,
    Color accentWarm,
    double beatStrength,
  ) {
    // Drive cowl + reactor deck bands wrapping the engine cone.
    final cowlTop = shipLen * 0.34;
    final cowlBottom = shipLen * 0.42;
    final cowl = Path()
      ..moveTo(-shipWidth * 0.42, cowlTop)
      ..lineTo(shipWidth * 0.42, cowlTop)
      ..lineTo(shipWidth * 0.36, cowlBottom)
      ..lineTo(-shipWidth * 0.36, cowlBottom)
      ..close();
    canvas.drawPath(
      cowl,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, cowlTop),
          Offset(0, cowlBottom),
          [const Color(0xFF3A414B), const Color(0xFF15171C)],
        ),
    );
    canvas.drawPath(
      cowl,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.6, shipLen * 0.005)
        ..color = accentWarm.withValues(alpha: 0.40),
    );
    // Bright leading edge on the cowl so the drive block separates from the
    // hull instead of sinking into the dark stern.
    canvas.drawLine(
      Offset(-shipWidth * 0.42, cowlTop),
      Offset(shipWidth * 0.42, cowlTop),
      Paint()
        ..color = accent.withValues(alpha: 0.5 + 0.25 * beatStrength)
        ..strokeWidth = max(0.7, shipLen * 0.007)
        ..blendMode = BlendMode.plus,
    );
    // Reactor vents glowing through the cowl face.
    final ventGlow = 0.35 + 0.35 * beatStrength;
    final ventPaint =
        Paint()
          ..shader = ui.Gradient.radial(
            const Offset(0, 0),
            shipWidth * 0.06,
            [
              accent.withValues(alpha: 0.9 * ventGlow),
              accent.withValues(alpha: 0.0),
            ],
          )
          ..blendMode = BlendMode.plus;
    for (final vx in [-0.28, -0.14, 0.0, 0.14, 0.28]) {
      canvas.drawCircle(
        Offset(shipWidth * vx, shipLen * 0.376),
        shipWidth * 0.045,
        ventPaint,
      );
    }
    final bandPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.40)
      ..strokeWidth = max(0.5, shipLen * 0.005);
    for (final band in [0.36, 0.39]) {
      canvas.drawLine(
        Offset(-shipWidth * 0.40, shipLen * band),
        Offset(shipWidth * 0.40, shipLen * band),
        bandPaint,
      );
    }

    // Nozzle bell: brushed metal gradient + lit rim so it reads even without
    // an additive throat glow (screensaver draws that itself).
    final nozzlePath = Path();
    nozzlePath.moveTo(-shipWidth * 0.35, shipLen * 0.45);
    nozzlePath.lineTo(shipWidth * 0.35, shipLen * 0.45);
    nozzlePath.lineTo(shipWidth * 0.30, shipLen * 0.40);
    nozzlePath.lineTo(-shipWidth * 0.30, shipLen * 0.40);
    nozzlePath.close();
    canvas.drawPath(
      nozzlePath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, shipLen * 0.40),
          Offset(0, shipLen * 0.45),
          [const Color(0xFF262B32), const Color(0xFF0A0B0E)],
        ),
    );
    canvas.drawPath(
      nozzlePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.6, shipLen * 0.005)
        ..color = accentWarm.withValues(alpha: 0.35),
    );

    // Chevron petals around the bell throat.
    final petalFill = Paint()..color = const Color(0xFF0A0B0E);
    final petalEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(0.5, shipLen * 0.003)
      ..color = accentWarm.withValues(alpha: 0.20);
    for (int i = 0; i < 5; i++) {
      final cx = -shipWidth * 0.22 + i * shipWidth * 0.11;
      final petal = Path()
        ..moveTo(cx - shipWidth * 0.055, shipLen * 0.40)
        ..lineTo(cx + shipWidth * 0.055, shipLen * 0.40)
        ..lineTo(cx, shipLen * 0.425)
        ..close();
      canvas.drawPath(petal, petalFill);
      canvas.drawPath(petal, petalEdge);
    }

    // Additive engine glow is owned by the painter only when it draws its own
    // plume. The screensaver passes drawPlume:false and layers
    // TorchPlumeEngine.paintEngineThroat itself — gate the glow so the two
    // don't stack.
    if (drawPlume) {
      // Bright bell-mouth rim.
      canvas.drawLine(
        Offset(-shipWidth * 0.30, shipLen * 0.40),
        Offset(shipWidth * 0.30, shipLen * 0.40),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.55 + 0.3 * beatStrength)
          ..strokeWidth = max(0.6, shipLen * 0.006)
          ..blendMode = BlendMode.plus
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
      );

      // Engine bloom halo behind the throat.
      canvas.drawCircle(
        Offset(0, shipLen * 0.45),
        shipWidth * 0.55,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(0, shipLen * 0.45),
            shipWidth * 0.6,
            [
              Colors.white.withValues(alpha: 0.35 + 0.3 * beatStrength),
              accent.withValues(alpha: 0.18),
              Colors.transparent,
            ],
            [0.0, 0.35, 1.0],
          )
          ..blendMode = BlendMode.plus
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );

      // Hot plasma well inside the nozzle.
      final throatGlow = 0.6 + 0.4 * beatStrength;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(0, shipLen * 0.45),
          width: shipWidth * 0.7,
          height: shipWidth * 0.22,
        ),
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(0, shipLen * 0.45),
            shipWidth * 0.5,
            [
              Colors.white.withValues(alpha: 0.95 * throatGlow),
              accent.withValues(alpha: 0.55 * throatGlow),
              Colors.transparent,
            ],
            [0.0, 0.5, 1.0],
          )
          ..blendMode = BlendMode.plus
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(0, shipLen * 0.45),
          width: shipWidth * 0.34,
          height: shipWidth * 0.1,
        ),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.7 * throatGlow)
          ..blendMode = BlendMode.plus,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // L4 — Raised command deck + cockpit glazing
  // ---------------------------------------------------------------------------
  void _drawDeckAndCockpit(
    Canvas canvas,
    double shipLen,
    double shipWidth,
    Color accent,
    Color accentWarm,
    double beatStrength,
    bool fullDetail,
  ) {
    // Raised command deck ahead of mid-hull on the dorsal flank.
    final deck = Path()
      ..moveTo(-shipWidth * 0.02, -shipLen * 0.315)
      ..lineTo(-shipWidth * 0.30, -shipLen * 0.30)
      ..lineTo(-shipWidth * 0.44, -shipLen * 0.20)
      ..lineTo(-shipWidth * 0.02, -shipLen * 0.225)
      ..close();
    canvas.drawPath(
      deck,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(-shipWidth * 0.44, -shipLen * 0.20),
          Offset(-shipWidth * 0.02, -shipLen * 0.315),
          [const Color(0xFF4A515B), const Color(0xFF1A1E24)],
        ),
    );
    canvas.drawPath(
      deck,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.5, shipLen * 0.004)
        ..color = Colors.white.withValues(alpha: 0.22),
    );

    // Sloped windshield facing the bow.
    final wStart = Offset(-shipWidth * 0.30, -shipLen * 0.30);
    final wEnd = Offset(-shipWidth * 0.44, -shipLen * 0.20);

    // Soft glow band behind the glazing.
    canvas.drawLine(
      wStart,
      wEnd,
      Paint()
        ..color = accent.withValues(alpha: 0.30 + 0.22 * beatStrength)
        ..strokeWidth = shipWidth * 0.26
        ..strokeCap = StrokeCap.round
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    // Window strip.
    canvas.drawLine(
      wStart,
      wEnd,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55 + 0.3 * beatStrength)
        ..strokeWidth = shipWidth * 0.08
        ..strokeCap = StrokeCap.round
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
    );
    // Window mullions (frame dividers).
    final d = wEnd - wStart;
    final perp = d.distance == 0
        ? Offset.zero
        : Offset(-d.dy, d.dx) / d.distance;
    final mullion = Paint()
      ..color = const Color(0xFF15181D)
      ..strokeWidth = max(0.6, shipLen * 0.005)
      ..strokeCap = StrokeCap.round;
    for (final t in [0.32, 0.66]) {
      final p = Offset(wStart.dx + d.dx * t, wStart.dy + d.dy * t);
      final half = shipWidth * 0.055;
      canvas.drawLine(p - perp * half, p + perp * half, mullion);
    }

    // Top deck highlight.
    canvas.drawLine(
      Offset(-shipWidth * 0.03, -shipLen * 0.245),
      Offset(-shipWidth * 0.16, -shipLen * 0.235),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.30)
        ..strokeWidth = max(0.5, shipLen * 0.004),
    );

    if (fullDetail) {
      // Whip comms mast rising from the deck's leading edge.
      canvas.drawLine(
        Offset(-shipWidth * 0.44, -shipLen * 0.20),
        Offset(-shipWidth * 0.50, -shipLen * 0.33),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.28)
          ..strokeWidth = max(0.5, shipLen * 0.006),
      );
      canvas.drawCircle(
        Offset(-shipWidth * 0.50, -shipLen * 0.33),
        max(0.4, shipLen * 0.004),
        Paint()..color = Colors.white.withValues(alpha: 0.35),
      );

      // Aft radiator fin forward of the dorsal tail fin.
      final rad = Path()
        ..moveTo(-shipWidth * 0.40, shipLen * 0.02)
        ..lineTo(-shipWidth * 0.48, shipLen * 0.02)
        ..lineTo(-shipWidth * 0.44, shipLen * 0.10)
        ..lineTo(-shipWidth * 0.38, shipLen * 0.10)
        ..close();
      canvas.drawPath(
        rad,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(-shipWidth * 0.48, 0),
            Offset(-shipWidth * 0.36, 0),
            [const Color(0xFF2A2E35), const Color(0xFF0E1013)],
          ),
      );
      canvas.drawPath(
        rad,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(0.5, shipLen * 0.004)
          ..color = accent.withValues(alpha: 0.25),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // L5 — PDC point-defense cannons
  // ---------------------------------------------------------------------------
  void _drawPdc(
    Canvas canvas,
    double shipLen,
    double shipWidth,
    double beatStrength,
    Random rnd,
  ) {
    // Twin-barrel cluster on the dorsal mid, aiming forward.
    final pdcBase = Path()
      ..moveTo(-shipWidth * 0.40, -shipLen * 0.04)
      ..lineTo(-shipWidth * 0.30, -shipLen * 0.04)
      ..lineTo(-shipWidth * 0.33, -shipLen * 0.12)
      ..lineTo(-shipWidth * 0.44, -shipLen * 0.10)
      ..close();
    canvas.drawPath(pdcBase, Paint()..color = const Color(0xFF1A1E24));
    canvas.drawPath(
      pdcBase,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.5, shipLen * 0.004)
        ..color = Colors.white.withValues(alpha: 0.18),
    );
    final barrelPaint = Paint()
      ..color = const Color(0xFF2A2E35)
      ..strokeWidth = max(1.0, shipLen * 0.012)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(-shipWidth * 0.31, -shipLen * 0.05),
      Offset(-shipWidth * 0.26, -shipLen * 0.20),
      barrelPaint,
    );
    canvas.drawLine(
      Offset(-shipWidth * 0.37, -shipLen * 0.05),
      Offset(-shipWidth * 0.34, -shipLen * 0.19),
      barrelPaint,
    );

    // Warm muzzle tips.
    final tipPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..strokeWidth = max(0.6, shipLen * 0.008)
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(
      Offset(-shipWidth * 0.26, -shipLen * 0.20),
      max(0.5, shipLen * 0.006),
      tipPaint,
    );
    canvas.drawCircle(
      Offset(-shipWidth * 0.34, -shipLen * 0.19),
      max(0.5, shipLen * 0.006),
      tipPaint,
    );

    // Muzzle flash when the drive is hot.
    if (beatStrength > 0.55 && rnd.nextDouble() > 0.5) {
      for (final m in [
        Offset(-shipWidth * 0.255, -shipLen * 0.205),
        Offset(-shipWidth * 0.335, -shipLen * 0.195),
      ]) {
        canvas.drawCircle(
          m,
          shipWidth * 0.12,
          Paint()
            ..color = const Color(0xFFFFF6C0).withValues(alpha: 0.85)
            ..blendMode = BlendMode.plus
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // L6 — Dorsal + keel tail fins
  // ---------------------------------------------------------------------------
  void _drawFins(Canvas canvas, double shipLen, double shipWidth, Color accent) {
    final finPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(-shipWidth * 0.55, shipLen * 0.06),
        Offset(-shipWidth * 0.30, shipLen * 0.30),
        [const Color(0xFF2B2F35), const Color(0xFF111317)],
      );
    final finEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(0.5, shipLen * 0.004)
      ..color = Colors.white.withValues(alpha: 0.18);

    // Dorsal fin: modest rake aft, sized so it reads as a fin rather than a
    // sail towering over the hull.
    final dorsalFin = Path()
      ..moveTo(-shipWidth * 0.32, shipLen * 0.06)
      ..lineTo(-shipWidth * 0.52, shipLen * 0.24)
      ..lineTo(-shipWidth * 0.40, shipLen * 0.28)
      ..close();
    canvas.drawPath(dorsalFin, finPaint);
    canvas.drawPath(dorsalFin, finEdge);

    // Keel fin: roughly matched to the dorsal so the stern reads balanced.
    final keelFin = Path()
      ..moveTo(shipWidth * 0.26, shipLen * 0.08)
      ..lineTo(shipWidth * 0.54, shipLen * 0.26)
      ..lineTo(shipWidth * 0.14, shipLen * 0.32)
      ..close();
    canvas.drawPath(keelFin, finPaint);
    canvas.drawPath(keelFin, finEdge);

    // Accent-lit fin tips — kept small and dim so the fins don't glare.
    final tipGlow = Paint()
      ..color = accent.withValues(alpha: 0.32)
      ..blendMode = BlendMode.plus
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
    canvas.drawCircle(Offset(-shipWidth * 0.52, shipLen * 0.24), shipWidth * 0.05, tipGlow);
    canvas.drawCircle(Offset(shipWidth * 0.54, shipLen * 0.26), shipWidth * 0.05, tipGlow);

    // Ambient-occlusion shadow where the fins seat into the hull.
    final aoPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.30)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(Offset(-shipWidth * 0.34, shipLen * 0.24), shipWidth * 0.16, aoPaint);
    canvas.drawCircle(Offset(shipWidth * 0.30, shipLen * 0.26), shipWidth * 0.16, aoPaint);
  }

  // ---------------------------------------------------------------------------
  // L7 — Navigation lights + tail beacon
  // ---------------------------------------------------------------------------
  void _drawLights(Canvas canvas, double shipLen, double shipWidth) {
    // Gentle breathing pulse on the wing-tip running lights.
    final pulse = 0.7 + 0.3 * sin(timeSeconds * 2.6);

    void navLight(Offset center, Color c) {
      canvas.drawCircle(
        center,
        shipWidth * 0.12,
        Paint()
          ..color = c.withValues(alpha: 0.5 * pulse)
          ..blendMode = BlendMode.plus
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawCircle(
        center,
        shipWidth * 0.04,
        Paint()..color = c.withValues(alpha: pulse),
      );
    }

    navLight(Offset(-shipWidth * 0.42, shipLen * 0.3), Colors.redAccent);
    navLight(Offset(shipWidth * 0.42, shipLen * 0.3), Colors.greenAccent);

    // Blinking tail beacon on the dorsal fin's trailing edge.
    final beacon = (timeSeconds * 2.0) % 1.0;
    if (beacon < 0.22) {
      final bA = 1.0 - beacon / 0.22;
      final bPos = Offset(-shipWidth * 0.50, shipLen * 0.25);
      canvas.drawCircle(
        bPos,
        shipWidth * 0.10,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.7 * bA)
          ..blendMode = BlendMode.plus
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawCircle(
        bPos,
        shipWidth * 0.028,
        Paint()..color = Colors.white.withValues(alpha: bA),
      );
    }
  }

  void _drawRCS(Canvas canvas, Offset pos, double angle) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(angle);

    final rcsPath = Path();
    rcsPath.moveTo(0, 0);
    rcsPath.lineTo(-2, -8);
    rcsPath.lineTo(2, -8);
    rcsPath.close();

    canvas.drawPath(
      rcsPath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.restore();
  }

  Path _buildRociHull(double len, double width) {
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
  bool shouldRepaint(covariant RocinanteShipPainter oldDelegate) =>
      shipLen != oldDelegate.shipLen ||
      color != oldDelegate.color ||
      timeSeconds != oldDelegate.timeSeconds ||
      beatStrength != oldDelegate.beatStrength ||
      drawPlume != oldDelegate.drawPlume ||
      drawDiamonds != oldDelegate.drawDiamonds;
}
