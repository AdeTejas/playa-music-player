import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import 'playback_motion.dart';
import 'torch_plume_engine.dart';

/// Side-profile Rocinante (Corvette-class) replica. Local frame: nose −Y,
/// engines +Y, dorsal −X (up after the π/2 waveform rotation), ventral +X.
/// Faithful silhouette: layered hull, pointed drooping bow, raised forward
/// command deck, swept dorsal fin + keel, and a single Epstein drive cone.
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
  /// Roci pass-2 tuning knobs (defaults = current replica look).
  /// [bowDroop]: 0 = straight bow edge, 1 = current drooping tip, >1 more.
  /// [commandDeckHeight]: 0 = flush, 1 = current raised deck, >1 taller.
  /// [dorsalFinSweep]: 0 = upright leading edge, 1 = current sweep, >1 more.
  final double bowDroop;
  final double commandDeckHeight;
  final double dorsalFinSweep;

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
    this.bowDroop = 1.0,
    this.commandDeckHeight = 1.0,
    this.dorsalFinSweep = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final shipLen = height;
    final shipWidth = shipLen * 0.24;

    // --- High-Tech Micro-Vibration (Physical CEO standard) ---
    // Vibration intensifies with both waveform power AND physics acceleration
    final vibeIntensity = (thrustLevel * 0.7) + (pitchRadians.abs() * 1.5);
    final vibration = (vibeIntensity > 0.6) ? (sin(animTimeSeconds * 160.0) * 0.6 * vibeIntensity) : 0.0;

    canvas.save();
    canvas.translate(0, vibration); // Apply micro-jitter to the entire ship

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

    // --- Performance: Cache Hull Path ---
    final hullPath = _buildTorchHull(shipLen, shipWidth);

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
        cluster: TorchPlumeEngine.rociDriveCluster(
          TorchPlumeEngine.engineMetrics(shipLen).bellHalfW,
        ),
      );
    }

    canvas.drawPath(
      hullPath.shift(const Offset(2, 4)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = budget.tier == TorchEffectTier.minimal
            ? null
            : const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Gunmetal hull — light falls from the dorsal (top) side.
    final hullPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(-shipWidth / 2, 0),
        Offset(shipWidth / 2, 0),
        [
          const Color(0xFF3A3F47),
          const Color(0xFF1A1E24),
          const Color(0xFF0C0E12),
          const Color(0xFF050607),
        ],
        [0.0, 0.4, 0.7, 1.0],
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

    _drawHullPlating(
      canvas,
      hullPath,
      shipLen,
      shipWidth,
    );

    _drawMarkings(canvas, hullPath, shipLen, shipWidth, accentWarm, accentCool);

    _drawCommandDeck(canvas, shipLen, shipWidth, accentCool);

    _drawRociFins(canvas, shipLen, shipWidth, accentWarm);
    _drawRociDrive(
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

    // --- Visual: Engine Heatbloom (CEO Polish) ---
    if (engineHeat > 0.6 && budget.tier != TorchEffectTier.minimal) {
      final bellW = TorchPlumeEngine.engineMetrics(shipLen).bellHalfW;
      final bloomR = bellW * 2.5 * engineHeat;
      canvas.drawCircle(
        Offset(0, shipLen * 0.45),
        bloomR,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(0, shipLen * 0.45),
            bloomR,
            [
              raptorSheath.withValues(alpha: 0.14 * engineHeat),
              Colors.transparent,
            ],
          )
          ..blendMode = BlendMode.plus,
      );
    }

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
  /// Dorsal = −X, ventral = +X.
  List<({
    Offset pos,
    Offset dir,
    double phase,
    double demandBias,
  })> _rcsPodLayout(double shipLen, double shipWidth, double pitch) {
    final pitchUp = pitch > 0.001;

    return [
      // Bow dorsal — roll / lateral hold.
      (
        pos: Offset(-shipWidth * 0.14, -shipLen * 0.42),
        dir: const Offset(-1, 0),
        phase: 0.0,
        demandBias: 0.75,
      ),
      // Bow ventral — roll / lateral hold.
      (
        pos: Offset(shipWidth * 0.16, -shipLen * 0.42),
        dir: const Offset(1, 0),
        phase: 1.4,
        demandBias: 0.75,
      ),
      // Bow axial — pitch trim (fires forward to pull the nose down/up).
      (
        pos: Offset(0, -shipLen * 0.46),
        dir: const Offset(0, -1),
        phase: 2.6,
        demandBias: pitchUp ? 1.15 : 0.45,
      ),
      // Mid dorsal — main-burn lateral hold.
      (
        pos: Offset(-shipWidth * 0.40, -shipLen * 0.06),
        dir: const Offset(-1, 0),
        phase: 2.8,
        demandBias: 0.9,
      ),
      // Mid ventral — main-burn lateral hold.
      (
        pos: Offset(shipWidth * 0.38, -shipLen * 0.04),
        dir: const Offset(1, 0),
        phase: 4.1,
        demandBias: 0.9,
      ),
      // Dorsal aft — roll + aft moment.
      (
        pos: Offset(-shipWidth * 0.36, shipLen * 0.24),
        dir: const Offset(-1, 0),
        phase: 3.5,
        demandBias: 0.95,
      ),
      // Ventral aft — roll + aft moment.
      (
        pos: Offset(shipWidth * 0.32, shipLen * 0.26),
        dir: const Offset(1, 0),
        phase: 5.2,
        demandBias: 0.95,
      ),
      // Stern axial — main-burn axial hold.
      (
        pos: Offset(0, shipLen * 0.42),
        dir: const Offset(0, 1),
        phase: 1.1,
        demandBias: 1.0,
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

    // --- Logic: Seek-Reactive RCS ---
    final seekIntensity = seekPulse.clamp(0.0, 1.0);
    final pitchTrim = pitch.abs() * 18.0;
    final stabDemand = (thrust * 0.65 + pitchTrim * 0.55 + seekIntensity * 0.8).clamp(0.0, 1.0);

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

    // Roci red-orange hull stripe along the mid flank.
    final stripePaint = Paint()
      ..color = accentWarm
      ..style = PaintingStyle.stroke
      ..strokeWidth = shipLen * 0.028;
    canvas.drawLine(
      Offset(-shipWidth * 0.42, -shipLen * 0.08),
      Offset(shipWidth * 0.40, -shipLen * 0.14),
      stripePaint,
    );
    canvas.drawLine(
      Offset(-shipWidth * 0.42, shipLen * 0.00),
      Offset(shipWidth * 0.40, -shipLen * 0.06),
      Paint()
        ..color = accentWarm.withValues(alpha: 0.55)
        ..strokeWidth = shipLen * 0.012,
    );

    // Small red bow chevron.
    final chevron = Path()
      ..moveTo(-shipWidth * 0.20, -shipLen * 0.32)
      ..lineTo(-shipWidth * 0.04, -shipLen * 0.42)
      ..lineTo(-shipWidth * 0.10, -shipLen * 0.45)
      ..close();
    canvas.drawPath(chevron, Paint()..color = accentWarm);

    // Deck highlight line (dorsal edge).
    canvas.drawLine(
      Offset(-shipWidth * 0.30, -shipLen * 0.28),
      Offset(-shipWidth * 0.42, shipLen * 0.10),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = shipLen * 0.012,
    );

    // Cool accent window glow row along the flank.
    for (int i = 0; i < 3; i++) {
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(-shipWidth * 0.10 + i * shipWidth * 0.16, shipLen * 0.04),
          width: shipWidth * 0.12,
          height: shipLen * 0.02,
        ),
        Paint()
          ..color = accentCool.withValues(alpha: 0.45)
          ..maskFilter = budget.tier == TorchEffectTier.minimal
              ? null
              : const MaskFilter.blur(BlurStyle.normal, 1),
      );
    }

    // Hull number block near the stern.
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(shipWidth * 0.02, shipLen * 0.26),
        width: shipWidth * 0.30,
        height: shipLen * 0.03,
      ),
      Paint()..color = const Color(0xFF111111),
    );
    final idPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.82)
      ..strokeWidth = shipLen * 0.012
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(-shipWidth * 0.12, shipLen * 0.30),
      Offset(shipWidth * 0.16, shipLen * 0.30),
      idPaint,
    );
    canvas.drawLine(
      Offset(-shipWidth * 0.12, shipLen * 0.345),
      Offset(shipWidth * 0.16, shipLen * 0.345),
      idPaint..strokeWidth = shipLen * 0.007,
    );

    canvas.restore();
  }

  void _drawHullPlating(
    Canvas canvas,
    Path hullPath,
    double shipLen,
    double shipWidth,
  ) {
    canvas.save();
    canvas.clipPath(hullPath);

    // Flat armor panels — angular seam grid, no reentry tiles.
    final seamPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;

    // Longitudinal panel breaks — the Roci's layered deck lines.
    canvas.drawLine(
      Offset(-shipWidth * 0.44, -shipLen * 0.20),
      Offset(shipWidth * 0.42, -shipLen * 0.18),
      seamPaint,
    );
    canvas.drawLine(
      Offset(-shipWidth * 0.44, shipLen * 0.04),
      Offset(shipWidth * 0.42, shipLen * 0.06),
      seamPaint,
    );
    canvas.drawLine(
      Offset(-shipWidth * 0.44, shipLen * 0.20),
      Offset(shipWidth * 0.42, shipLen * 0.22),
      seamPaint,
    );

    // Cross ribs.
    for (final yy in [-0.08, 0.16]) {
      canvas.drawLine(
        Offset(-shipWidth * 0.48, shipLen * yy),
        Offset(shipWidth * 0.46, shipLen * (yy - 0.03)),
        seamPaint,
      );
    }

    // Rivet row near the dorsal edge.
    for (int i = 0; i < 6; i++) {
      canvas.drawCircle(
        Offset(-shipWidth * 0.36 + i * shipWidth * 0.14, -shipLen * 0.24),
        shipLen * 0.003,
        Paint()..color = Colors.white.withValues(alpha: 0.10),
      );
    }

    // Ventral wear shading.
    canvas.drawPath(
      hullPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, shipWidth * 0.3),
          Offset(0, shipWidth * 0.6),
          [Colors.black.withValues(alpha: 0.18), Colors.transparent],
        ),
    );

    canvas.restore();
  }

  /// Raised forward command deck (the Roci's bridge), with a sloped
  /// windshield and cool window glow.
  void _drawCommandDeck(
    Canvas canvas,
    double shipLen,
    double shipWidth,
    Color accentCool,
  ) {
    final h = commandDeckHeight;
    // Raised deck: base at -0.36L, top protrudes 0.08L (scaled by h).
    final deck = Path()
      ..moveTo(-shipWidth * 0.02, -shipLen * 0.36)
      ..lineTo(-shipWidth * 0.12, -shipLen * 0.35)
      ..lineTo(-shipWidth * 0.20, -shipLen * (0.36 + 0.08 * h))
      ..lineTo(-shipWidth * 0.04, -shipLen * (0.35 + 0.08 * h))
      ..close();

    canvas.drawPath(
      deck,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(-shipWidth * 0.02, -shipLen * (0.35 + 0.08 * h)),
          Offset(-shipWidth * 0.18, -shipLen * 0.36),
          [const Color(0xFF4A515B), const Color(0xFF1A1E24)],
        ),
    );
    canvas.drawPath(
      deck,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = Colors.white.withValues(alpha: 0.20),
    );

    // Sloped windshield — cool accent band facing the bow.
    canvas.drawLine(
      Offset(-shipWidth * 0.13, -shipLen * 0.36),
      Offset(-shipWidth * 0.19, -shipLen * (0.36 + 0.075 * h)),
      Paint()
        ..color = accentCool.withValues(alpha: 0.65)
        ..strokeWidth = shipLen * 0.010
        ..maskFilter = budget.tier == TorchEffectTier.minimal
            ? null
            : const MaskFilter.blur(BlurStyle.normal, 1),
    );

    // Top deck highlight.
    canvas.drawLine(
      Offset(-shipWidth * 0.05, -shipLen * (0.35 + 0.08 * h)),
      Offset(-shipWidth * 0.185, -shipLen * (0.36 + 0.077 * h)),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.30)
        ..strokeWidth = shipLen * 0.007,
    );
  }

  /// Swept dorsal fin, keel fin, and the layered deck spine.
  void _drawRociFins(
    Canvas canvas,
    double shipLen,
    double shipWidth,
    Color accentWarm,
  ) {
    final finPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(-shipWidth * 0.54, shipLen * 0.20),
        Offset(-shipWidth * 0.30, shipLen * 0.32),
        [const Color(0xFF343941), const Color(0xFF14161A)],
      );
    final finEdge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Colors.white.withValues(alpha: 0.22);

    // Swept-back dorsal fin ahead of the drive.
    final tipX = -0.38 + 0.08 * dorsalFinSweep;
    final dorsalFin = Path()
      ..moveTo(-shipWidth * 0.38, shipLen * 0.04)
      ..lineTo(shipWidth * tipX, shipLen * 0.28)
      ..lineTo(-shipWidth * 0.52, shipLen * 0.30)
      ..close();
    canvas.drawPath(dorsalFin, finPaint);
    canvas.drawPath(dorsalFin, finEdge);

    // Keel fin under the belly near the stern.
    final keelFin = Path()
      ..moveTo(shipWidth * 0.36, shipLen * 0.10)
      ..lineTo(shipWidth * 0.28, shipLen * 0.34)
      ..lineTo(shipWidth * 0.52, shipLen * 0.28)
      ..close();
    canvas.drawPath(keelFin, finPaint);
    canvas.drawPath(keelFin, finEdge);

    // Layered deck spine ridge running to the drive cone.
    final spine = Path()
      ..moveTo(-shipWidth * 0.28, -shipLen * 0.24)
      ..lineTo(-shipWidth * 0.40, -shipLen * 0.14)
      ..lineTo(-shipWidth * 0.44, -shipLen * 0.02)
      ..lineTo(-shipWidth * 0.40, shipLen * 0.14)
      ..lineTo(-shipWidth * 0.34, shipLen * 0.10)
      ..lineTo(-shipWidth * 0.38, -shipLen * 0.04)
      ..close();
    canvas.drawPath(
      spine,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(-shipWidth * 0.46, 0),
          Offset(-shipWidth * 0.28, 0),
          [const Color(0xFF4A515B), const Color(0xFF20242A)],
        ),
    );
    canvas.drawPath(
      spine,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = accentWarm.withValues(alpha: 0.35),
    );
  }

  /// Single Epstein drive cone at the stern, aligned to
  /// [TorchPlumeEngine.rociDriveCluster].
  void _drawRociDrive(
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
    final bellHalfW = TorchPlumeEngine.engineMetrics(shipLen).bellHalfW;
    final cowlTop = shipLen * 0.40;
    final cowlBottom = shipLen * 0.51;
    final glow = (0.5 + 0.3 * sin(t * 2.5)) *
        journeyHeat *
        (0.70 + 0.30 * beatStrength) *
        (0.65 + 0.35 * thrust);

    // Drive cone housing hugging the single Epstein bell.
    final blockHalf = bellHalfW * 1.22;
    final cowlPath = Path()
      ..moveTo(-blockHalf, cowlTop)
      ..lineTo(blockHalf, cowlTop)
      ..lineTo(blockHalf * 0.9, cowlBottom)
      ..lineTo(-blockHalf * 0.9, cowlBottom)
      ..close();

    canvas.drawPath(
      cowlPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, cowlTop),
          Offset(0, cowlBottom),
          [const Color(0xFF262A30), const Color(0xFF0B0C0F)],
        ),
    );

    canvas.drawPath(
      cowlPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = accentWarm.withValues(alpha: 0.12 * glow)
        ..maskFilter = budget.tier == TorchEffectTier.minimal
            ? null
            : const MaskFilter.blur(BlurStyle.normal, 3),
    );

    for (final engine in TorchPlumeEngine.rociDriveCluster(bellHalfW)) {
      final ex = engine.offset;
      final eHalf = bellHalfW * engine.scale;

      // Bell housing — narrow throat forward, flared mouth aft.
      final bellPath = Path()
        ..moveTo(ex - eHalf * 0.84, cowlTop + shipLen * 0.03)
        ..lineTo(ex + eHalf * 0.84, cowlTop + shipLen * 0.03)
        ..lineTo(ex + eHalf, cowlBottom - shipLen * 0.01)
        ..lineTo(ex - eHalf, cowlBottom - shipLen * 0.01)
        ..close();
      canvas.drawPath(
        bellPath,
        Paint()..color = const Color(0xFF07080A),
      );
      canvas.drawPath(
        bellPath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6
          ..color = const Color(0xFF3A3F47),
      );

      // Drive-cone panel seams (reactor deck bands).
      final seamPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.40)
        ..strokeWidth = 0.7;
      for (final band in [0.06, 0.13]) {
        canvas.drawLine(
          Offset(ex - eHalf * 0.9, cowlTop + shipLen * band),
          Offset(ex + eHalf * 0.9, cowlTop + shipLen * band),
          seamPaint,
        );
      }

      // Throat glow — blue-white Epstein plasma.
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(ex, cowlTop + shipLen * 0.09),
          width: eHalf * 1.5,
          height: shipLen * 0.03,
        ),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(ex, cowlTop + shipLen * 0.07),
            Offset(ex, cowlBottom),
            [
              raptorCore.withValues(
                alpha: (0.55 * glow * budget.glowAlphaMul).clamp(0.0, 1.0),
              ),
              raptorSheath.withValues(
                alpha: (0.28 * glow * budget.glowAlphaMul).clamp(0.0, 1.0),
              ),
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
        Offset(ex, cowlTop + shipLen * 0.05),
        eHalf * (0.22 + 0.08 * thrust),
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(ex, cowlTop + shipLen * 0.05),
            eHalf * (0.3 + 0.06 * thrust),
            [
              raptorCore.withValues(
                alpha: 0.24 * glow * budget.glowAlphaMul,
              ),
              raptorSheath.withValues(
                alpha: 0.10 * glow * budget.glowAlphaMul,
              ),
              Colors.transparent,
            ],
            [0.0, 0.55, 1.0],
          )
          ..blendMode = BlendMode.plus,
      );
    }
  }

  void _drawNavLights(Canvas canvas, double shipLen, double shipWidth, double t) {
    final lightT = t * 1.8;
    final portAlpha = 0.65 + 0.35 * ((sin(lightT * 1.3) + 1) / 2);
    canvas.drawCircle(
      Offset(-shipWidth * 0.30, -shipLen * 0.26),
      shipLen * 0.012,
      Paint()
        ..color = Color.lerp(const Color(0xFFB71C1C), Colors.redAccent, 0.3)!
            .withValues(alpha: portAlpha),
    );
    final starAlpha = 0.65 + 0.35 * ((cos(lightT * 1.1) + 1) / 2);
    canvas.drawCircle(
      Offset(shipWidth * 0.38, -shipLen * 0.08),
      shipLen * 0.012,
      Paint()
        ..color = Color.lerp(const Color(0xFF1B5E20), Colors.greenAccent, 0.3)!
            .withValues(alpha: starAlpha),
    );
    final whiteAlpha = 0.3 + 0.7 * ((sin(lightT * 0.7) * cos(lightT * 0.4) + 1) / 2);
    canvas.drawCircle(
      Offset(0, -shipLen * 0.49),
      shipLen * 0.009,
      Paint()
        ..color = Colors.white.withValues(alpha: whiteAlpha.clamp(0.15, 0.95)),
    );
    canvas.drawCircle(
      Offset(0, shipLen * 0.44),
      shipLen * 0.007,
      Paint()..color = Colors.white.withValues(alpha: 0.45),
    );
  }

  Path _buildTorchHull(double len, double width) {
    // Rocinante Corvette silhouette: pointed drooping bow, layered parallel
    // flanks, flat belly, and a drive-cone stern. The raised command deck and
    // dorsal/keel fins are drawn on top so the hull stays a clean polygon.
    // Bow edge is parametrized by [bowDroop]: 0 lays the tip edge on the
    // straight nose→dorsal-anchor line, 1 is the current drooping tip, >1
    // exaggerates the droop (and mid-bow rise).
    double bowLen(double xFrac, double lenFrac) {
      final t = (xFrac - 0.02) / -0.30;
      final lineLen = -0.50 + t * 0.20;
      return len * (lineLen + (lenFrac - lineLen) * bowDroop);
    }

    final path = Path();
    path.moveTo(0.02 * width, -len * 0.5);
    path.lineTo(-0.07 * width, -bowLen(-0.07, 0.48));
    path.lineTo(-0.13 * width, -bowLen(-0.13, 0.44));
    path.lineTo(-0.18 * width, -bowLen(-0.18, 0.39));
    path.lineTo(-0.22 * width, -bowLen(-0.22, 0.33));
    path.lineTo(-0.28 * width, -len * 0.30);
    path.lineTo(-0.34 * width, -len * 0.24);
    path.lineTo(-0.40 * width, -len * 0.14);
    path.lineTo(-0.44 * width, -len * 0.02);
    path.lineTo(-0.44 * width, len * 0.12);
    path.lineTo(-0.38 * width, len * 0.28);
    path.lineTo(-0.24 * width, len * 0.40);
    path.lineTo(-0.12 * width, len * 0.44);
    path.lineTo(0.12 * width, len * 0.44);
    path.lineTo(0.26 * width, len * 0.36);
    path.lineTo(0.36 * width, len * 0.22);
    path.lineTo(0.40 * width, len * 0.06);
    path.lineTo(0.40 * width, -len * 0.08);
    path.lineTo(0.36 * width, -len * 0.20);
    path.lineTo(0.30 * width, -len * 0.32);
    path.lineTo(0.22 * width, -len * 0.42);
    path.lineTo(0.12 * width, -len * 0.48);
    path.lineTo(0.04 * width, -len * 0.50);
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
      pitchRadians != oldDelegate.pitchRadians ||
      bowDroop != oldDelegate.bowDroop ||
      commandDeckHeight != oldDelegate.commandDeckHeight ||
      dorsalFinSweep != oldDelegate.dorsalFinSweep;
}
