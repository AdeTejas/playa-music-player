import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'playback_motion.dart';
import 'torch_plume_engine.dart';

class TorchShipPainter extends CustomPainter {
  final double height;
  final double progress;
  final double animTimeSeconds;
  final double playbackTimeSeconds;
  final Color color;
  final double? bpm;
  final bool drawPlume;
  final TorchEffectBudget budget;
  final double seekPulse;
  /// 0–1 thrust from waveform / beat — drives engine heat and hull vibration.
  final double thrustLevel;
  /// Nose-up pitch under acceleration (radians).
  final double pitchRadians;

  const TorchShipPainter({
    required this.height,
    required this.progress,
    required this.animTimeSeconds,
    required this.playbackTimeSeconds,
    required this.color,
    required this.budget,
    this.bpm,
    this.drawPlume = true,
    this.seekPulse = 0.0,
    this.thrustLevel = 0.5,
    this.pitchRadians = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final shipLen = height;
    final shipWidth = shipLen * 0.25;
    final thrust = thrustLevel.clamp(0.0, 1.0);

    final accent = color;
    final accentCool = Color.lerp(accent, const Color(0xFF80D8FF), 0.35) ?? accent;
    final accentWarm = Color.lerp(const Color(0xFFD84315), accent, 0.45) ?? accent;
    final raptorCore = TorchPlumeEngine.raptorCore(accent);
    final raptorSheath = TorchPlumeEngine.raptorSheath(accent);

    final beatStrength =
        TorchPlumeEngine.beatStrength(playbackTimeSeconds, bpm);
    final seekBoost = 1.0 + 0.28 * seekPulse.clamp(0.0, 1.0);
    final journeyHeat =
        (0.82 + 0.18 * progress.clamp(0.0, 1.0)) * seekBoost;
    final engineHeat = journeyHeat * (0.55 + 0.45 * thrust);

    canvas.save();
    if (pitchRadians.abs() > 1e-4) {
      canvas.rotate(pitchRadians);
    }

    TorchPlumeEngine.paintVerticalSideIons(
      canvas: canvas,
      shipLen: shipLen,
      shipWidth: shipWidth,
      accent: accent,
      animTimeSeconds: animTimeSeconds,
      beatStrength: beatStrength,
      budget: budget,
    );

    if (drawPlume) {
      TorchPlumeEngine.paintVerticalCorePlume(
        canvas: canvas,
        shipLen: shipLen,
        shipWidth: shipWidth,
        accent: accent,
        accentCool: accentCool,
        animTimeSeconds: animTimeSeconds,
        beatStrength: beatStrength,
        budget: budget,
      );
    }

    final hullPath = _buildTorchHull(shipLen, shipWidth);

    canvas.drawPath(
      hullPath.shift(const Offset(3, 6)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = budget.tier == TorchEffectTier.minimal
            ? null
            : const MaskFilter.blur(BlurStyle.normal, 6),
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
        ..color = accent.withValues(
          alpha: ((0.14 + 0.22 * beatStrength) * journeyHeat).clamp(0.0, 1.0),
        )
        ..blendMode = BlendMode.plus
        ..maskFilter = budget.tier == TorchEffectTier.minimal
            ? null
            : const MaskFilter.blur(BlurStyle.normal, 3.0),
    );

    _drawHeatshieldTiles(
      canvas,
      hullPath,
      shipLen,
      shipWidth,
      accentWarm,
      animTimeSeconds,
      journeyHeat,
    );

    _drawMarkings(canvas, hullPath, shipLen, shipWidth, accentWarm, accentCool);

    _drawEngineBell(
      canvas,
      shipLen,
      shipWidth,
      accentWarm,
      raptorCore,
      raptorSheath,
      animTimeSeconds,
      engineHeat,
      beatStrength * seekBoost,
      thrust,
    );

    _drawNavLights(canvas, shipLen, shipWidth, animTimeSeconds);

    // RCS on top so plumes read clearly against hull + nav lights.
    _drawRcsThrusters(
      canvas,
      shipLen,
      shipWidth,
      accentCool,
      animTimeSeconds,
      thrust,
      pitchRadians,
    );

    canvas.restore();
  }

  /// RCS pods locked to [_buildTorchHull] vertices (nose −Y, engines +Y).
  List<({
    Offset pos,
    Offset dir,
    double phase,
    double demandBias,
  })> _rcsPodLayout(double shipLen, double shipWidth, double pitch) {
    final pitchUp = pitch > 0.001;
    final pitchDown = pitch < -0.001;

    return [
      // Forward chine — roll (outward ±X).
      (
        pos: Offset(-shipWidth * 0.25, -shipLen * 0.40),
        dir: const Offset(-1, 0),
        phase: 0.0,
        demandBias: 0.75,
      ),
      (
        pos: Offset(shipWidth * 0.25, -shipLen * 0.40),
        dir: const Offset(1, 0),
        phase: 1.4,
        demandBias: 0.75,
      ),
      // Forward flare — roll / yaw trim.
      (
        pos: Offset(-shipWidth * 0.35, -shipLen * 0.15),
        dir: const Offset(-1, 0),
        phase: 2.8,
        demandBias: 0.85,
      ),
      (
        pos: Offset(shipWidth * 0.35, -shipLen * 0.15),
        dir: const Offset(1, 0),
        phase: 4.1,
        demandBias: 0.85,
      ),
      // Max-beam mid-body — lateral hold during main burn.
      (
        pos: Offset(-shipWidth * 0.40, shipLen * 0.10),
        dir: const Offset(-1, 0),
        phase: 0.7,
        demandBias: 1.0,
      ),
      (
        pos: Offset(shipWidth * 0.40, shipLen * 0.10),
        dir: const Offset(1, 0),
        phase: 2.0,
        demandBias: 1.0,
      ),
      // Grid-fin root (aft flare apex) — roll + aft moment.
      (
        pos: Offset(-shipWidth * 0.35, shipLen * 0.45),
        dir: const Offset(-0.88, 0.22),
        phase: 3.5,
        demandBias: 0.95,
      ),
      (
        pos: Offset(shipWidth * 0.35, shipLen * 0.45),
        dir: const Offset(0.88, 0.22),
        phase: 5.2,
        demandBias: 0.95,
      ),
      // Dorsal aft — pitch-down correction when nose is up under thrust.
      (
        pos: Offset(0, shipLen * 0.36),
        dir: const Offset(0, 1),
        phase: 1.1,
        demandBias: pitchUp ? 1.25 : 0.45,
      ),
      // Forward dorsal — counters nose-up (push nose down).
      (
        pos: Offset(0, -shipLen * 0.38),
        dir: const Offset(0, -1),
        phase: 2.6,
        demandBias: pitchUp ? 1.15 : 0.35,
      ),
      // Ventral forward — pitch-up assist when nose is down.
      (
        pos: Offset(0, -shipLen * 0.22),
        dir: const Offset(0, 1),
        phase: 4.8,
        demandBias: pitchDown ? 1.1 : 0.3,
      ),
    ];
  }

  void _drawRcsThrusters(
    Canvas canvas,
    double shipLen,
    double shipWidth,
    Color accentCool,
    double t,
    double thrust,
    double pitch,
  ) {
    if (budget.tier == TorchEffectTier.minimal) return;

    final pitchTrim = pitch.abs() * 18.0;
    final stabDemand = (thrust * 0.65 + pitchTrim * 0.55).clamp(0.0, 1.0);

    final ion = TorchPlumeEngine.ionCool(accentCool);
    final core = TorchPlumeEngine.raptorCore(accentCool);
    final portR = shipLen * 0.011;
    final plumeLen = shipLen * 0.092;
    final pods = _rcsPodLayout(shipLen, shipWidth, pitch);

    for (final pod in pods) {
      final intensity = PlaybackMotion.rcsPuffIntensity(
        timeSeconds: t,
        podPhase: pod.phase,
        stabDemand: stabDemand,
        demandBias: pod.demandBias,
        pitchRadians: pitch,
        podDirection: pod.dir,
      );
      final firing = intensity >= 0.06;

      // Nozzle port — always visible at hull hardpoints.
      canvas.drawCircle(
        pod.pos,
        portR * 1.45,
        Paint()..color = const Color(0xFF121212),
      );
      canvas.drawCircle(
        pod.pos,
        portR * 1.45,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6
          ..color = Colors.white.withValues(alpha: 0.14),
      );
      canvas.drawCircle(
        pod.pos,
        portR,
        Paint()
          ..color = ion.withValues(
            alpha: firing ? 0.35 + 0.45 * intensity : 0.12,
          )
          ..blendMode = BlendMode.plus,
      );

      if (!firing) continue;

      final dir = pod.dir;
      final len = dir.distance;
      final norm = Offset(dir.dx / len, dir.dy / len);
      final exhaustEnd =
          pod.pos + norm * plumeLen * (0.82 + 0.18 * intensity);

      final blur = budget.coreBlur > 0
          ? MaskFilter.blur(BlurStyle.normal, budget.coreBlur * 0.85)
          : null;

      // Outer puff halo.
      canvas.drawCircle(
        exhaustEnd,
        portR * (2.2 + 1.4 * intensity),
        Paint()
          ..color = ion.withValues(alpha: (0.38 * intensity).clamp(0.0, 1.0))
          ..blendMode = BlendMode.plus
          ..maskFilter = blur,
      );

      final plumePaint = Paint()
        ..strokeWidth = max(1.4, portR * 2.0)
        ..strokeCap = StrokeCap.round
        ..blendMode = BlendMode.plus
        ..maskFilter = blur;

      plumePaint.shader = ui.Gradient.linear(
        pod.pos,
        exhaustEnd,
        [
          Colors.white.withValues(alpha: (0.82 * intensity).clamp(0.0, 1.0)),
          core.withValues(alpha: (0.78 * intensity).clamp(0.0, 1.0)),
          ion.withValues(alpha: (0.58 * intensity).clamp(0.0, 1.0)),
          ion.withValues(alpha: 0.0),
        ],
        const [0.0, 0.22, 0.58, 1.0],
      );
      canvas.drawLine(pod.pos, exhaustEnd, plumePaint);

      canvas.drawCircle(
        exhaustEnd,
        portR * (1.2 + 0.9 * intensity),
        Paint()
          ..color = Colors.white.withValues(alpha: (0.55 * intensity).clamp(0.0, 1.0))
          ..blendMode = BlendMode.plus
          ..maskFilter = blur,
      );
    }
  }

  void _drawMarkings(
    Canvas canvas,
    Path hullPath,
    double shipLen,
    double shipWidth,
    Color accentWarm,
    Color accentCool,
  ) {
    canvas.save();
    canvas.clipPath(hullPath);

    final stripePaint = Paint()
      ..color = accentWarm
      ..style = PaintingStyle.stroke
      ..strokeWidth = shipLen * 0.05;

    canvas.drawLine(
      Offset(-shipWidth, -shipLen * 0.3),
      Offset(shipWidth, -shipLen * 0.3),
      stripePaint,
    );
    canvas.drawLine(
      Offset(-shipWidth, -shipLen * 0.35),
      Offset(shipWidth, -shipLen * 0.35),
      stripePaint..strokeWidth = shipLen * 0.02,
    );

    canvas.drawRect(
      Rect.fromCenter(
        center: const Offset(0, 0),
        width: shipWidth,
        height: shipLen * 0.15,
      ),
      Paint()..color = accentWarm,
    );

    final panelPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    canvas.drawLine(
      Offset(-shipWidth * 0.3, -shipLen * 0.1),
      Offset(shipWidth * 0.3, -shipLen * 0.1),
      panelPaint,
    );
    canvas.drawLine(
      Offset(-shipWidth * 0.3, shipLen * 0.1),
      Offset(shipWidth * 0.3, shipLen * 0.1),
      panelPaint,
    );
    canvas.drawLine(
      Offset(0, -shipLen * 0.4),
      Offset(0, shipLen * 0.4),
      panelPaint,
    );

    final wearPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawLine(
      Offset(-shipWidth * 0.28, -shipLen * 0.18),
      Offset(shipWidth * 0.05, -shipLen * 0.19),
      wearPaint,
    );
    canvas.drawLine(
      Offset(-shipWidth * 0.15, shipLen * 0.07),
      Offset(shipWidth * 0.32, shipLen * 0.08),
      wearPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-shipWidth * 0.12, shipLen * 0.18),
        width: shipWidth * 0.22,
        height: shipLen * 0.06,
      ),
      wearPaint..color = Colors.black.withValues(alpha: 0.12),
    );

    canvas.drawLine(
      Offset(-shipWidth * 0.2, 0),
      Offset(shipWidth * 0.2, 0),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..strokeWidth = 1.0,
    );

    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(0, -shipLen * 0.25),
        width: shipWidth * 0.4,
        height: shipLen * 0.05,
      ),
      Paint()
        ..color = accentCool.withValues(alpha: 0.92)
        ..maskFilter = budget.tier == TorchEffectTier.minimal
            ? null
            : const MaskFilter.blur(BlurStyle.normal, 1),
    );

    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(0, -shipLen * 0.45),
        width: shipWidth * 0.1,
        height: shipLen * 0.1,
      ),
      Paint()..color = const Color(0xFF111111),
    );

    final idPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.82)
      ..strokeWidth = shipLen * 0.012
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(-shipWidth * 0.16, -shipLen * 0.07),
      Offset(shipWidth * 0.16, -shipLen * 0.07),
      idPaint,
    );
    canvas.drawLine(
      Offset(-shipWidth * 0.16, -shipLen * 0.035),
      Offset(shipWidth * 0.16, -shipLen * 0.035),
      idPaint..strokeWidth = shipLen * 0.007,
    );

    final regPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.65)
      ..strokeWidth = 0.6;
    canvas.drawLine(
      Offset(-shipWidth * 0.20, shipLen * 0.215),
      Offset(-shipWidth * 0.09, shipLen * 0.215),
      regPaint,
    );
    canvas.drawLine(
      Offset(shipWidth * 0.09, shipLen * 0.215),
      Offset(shipWidth * 0.20, shipLen * 0.215),
      regPaint,
    );

    canvas.restore();
  }

  void _drawHeatshieldTiles(
    Canvas canvas,
    Path hullPath,
    double shipLen,
    double shipWidth,
    Color accentWarm,
    double t,
    double journeyHeat,
  ) {
    canvas.save();
    canvas.clipPath(hullPath);

    final tileW = shipWidth * 0.16;
    final tileH = shipLen * 0.035;
    const gap = 0.8;
    const cols = 3;
    const rows = 5;
    final startY = shipLen * 0.12;
    final heatGlow =
        (0.08 + 0.04 * sin(t * 1.8)) * journeyHeat * budget.glowAlphaMul;

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
              ..maskFilter = budget.tier == TorchEffectTier.minimal
                  ? null
                  : const MaskFilter.blur(BlurStyle.normal, 2)
              ..color = accentWarm.withValues(
                alpha: heatGlow * (r - rows + 3) / 2,
              ),
          );
        }
      }
    }

    canvas.restore();
  }

  void _drawEngineBell(
    Canvas canvas,
    double shipLen,
    double shipWidth,
    Color accentWarm,
    Color raptorCore,
    Color raptorSheath,
    double t,
    double journeyHeat,
    double beatStrength,
    double thrust,
  ) {
    final bellW = TorchPlumeEngine.engineMetrics(shipLen).bellHalfW;
    final bellH = shipLen * 0.08;
    final bellY = shipLen * 0.45;
    final glow = (0.5 + 0.3 * sin(t * 2.5)) *
        journeyHeat *
        (0.70 + 0.30 * beatStrength) *
        (0.65 + 0.35 * thrust);

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

    canvas.drawPath(
      bellPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = accentWarm.withValues(alpha: 0.15 * glow)
        ..maskFilter = budget.tier == TorchEffectTier.minimal
            ? null
            : const MaskFilter.blur(BlurStyle.normal, 3),
    );

    for (int r = 0; r < 3; r++) {
      final yy = bellY - bellH * (0.2 + r * 0.3);
      final ww = bellW * (1.0 - r * 0.1);
      canvas.drawLine(
        Offset(-ww * 0.5, yy),
        Offset(ww * 0.5, yy),
        Paint()
          ..color = const Color(0xFF1A1A1A)
          ..strokeWidth = 0.4,
      );
    }
    for (int s = -2; s <= 2; s++) {
      if (s == 0) continue;
      final xx = s * bellW * 0.18;
      canvas.drawLine(
        Offset(xx, bellY - bellH * 0.15),
        Offset(xx * 0.92, bellY - bellH * 0.85),
        Paint()
          ..color = const Color(0xFF1A1A1A)
          ..strokeWidth = 0.4,
      );
    }

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

    canvas.drawRect(
      Rect.fromLTWH(-bellW * 0.42, bellY - bellH * 0.15, bellW * 0.84, bellH * 0.3),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, bellY - bellH * 0.15),
          Offset(0, bellY + bellH * 0.15),
          [
            Colors.transparent,
            Color.lerp(raptorSheath, accentWarm, 0.35)!
                .withValues(alpha: 0.32 * glow * budget.glowAlphaMul),
            Colors.transparent,
          ],
          [0.0, 0.5, 1.0],
        )
        ..blendMode = BlendMode.plus
        ..maskFilter = budget.nozzleBlur > 0
            ? MaskFilter.blur(BlurStyle.normal, budget.nozzleBlur)
            : null,
    );

    canvas.drawCircle(
      Offset(0, bellY),
      bellW * (0.28 + 0.08 * thrust),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(0, bellY),
          bellW * (0.38 + 0.06 * thrust),
          [
            raptorCore.withValues(alpha: 0.22 * glow * budget.glowAlphaMul),
            raptorSheath.withValues(alpha: 0.10 * glow * budget.glowAlphaMul),
            Colors.transparent,
          ],
          [0.0, 0.55, 1.0],
        )
        ..blendMode = BlendMode.plus,
    );
  }

  void _drawNavLights(Canvas canvas, double shipLen, double shipWidth, double t) {
    final lightT = t * 1.8;
    final portAlpha = 0.65 + 0.35 * ((sin(lightT * 1.3) + 1) / 2);
    canvas.drawCircle(
      Offset(-shipWidth * 0.38, -shipLen * 0.32),
      shipLen * 0.012,
      Paint()
        ..color = Color.lerp(const Color(0xFFB71C1C), Colors.redAccent, 0.3)!
            .withValues(alpha: portAlpha),
    );
    final starAlpha = 0.65 + 0.35 * ((cos(lightT * 1.1) + 1) / 2);
    canvas.drawCircle(
      Offset(shipWidth * 0.38, -shipLen * 0.32),
      shipLen * 0.012,
      Paint()
        ..color = Color.lerp(const Color(0xFF1B5E20), Colors.greenAccent, 0.3)!
            .withValues(alpha: starAlpha),
    );
    final whiteAlpha = 0.3 + 0.7 * ((sin(lightT * 0.7) * cos(lightT * 0.4) + 1) / 2);
    canvas.drawCircle(
      Offset(0, -shipLen * 0.48),
      shipLen * 0.009,
      Paint()
        ..color = Colors.white.withValues(alpha: whiteAlpha.clamp(0.15, 0.95)),
    );
    canvas.drawCircle(
      Offset(0, shipLen * 0.48),
      shipLen * 0.007,
      Paint()..color = Colors.white.withValues(alpha: 0.45),
    );
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
      animTimeSeconds != oldDelegate.animTimeSeconds ||
      playbackTimeSeconds != oldDelegate.playbackTimeSeconds ||
      bpm != oldDelegate.bpm ||
      budget != oldDelegate.budget ||
      drawPlume != oldDelegate.drawPlume ||
      seekPulse != oldDelegate.seekPulse ||
      thrustLevel != oldDelegate.thrustLevel ||
      pitchRadians != oldDelegate.pitchRadians;
}