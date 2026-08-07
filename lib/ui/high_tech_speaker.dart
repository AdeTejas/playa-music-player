import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../design/design_system.dart';
import '../design/utils/design_utils.dart';
import '../services/settings_service.dart';
import 'playback_motion.dart';

// ---------------------------------------------------------------------------
// Sacred geometry helpers (cached, testable)
// ---------------------------------------------------------------------------

/// Hex-lattice Flower of Life layout utilities.
class SacredFlowerGeometry {
  SacredFlowerGeometry._();

  static const int flowerOfLifeCircleCount = 19;

  /// Classic 19-circle Flower of Life (equal radius = [radius], centers spaced by [radius]).
  static List<Offset> flowerCenters(double radius, {int rings = 2}) {
    if (rings != 2) {
      // Seed of Life (7 circles) for nested driver detail.
      final centers = <Offset>[Offset.zero];
      for (int i = 0; i < 6; i++) {
        final a = pi / 3 * i;
        centers.add(Offset(cos(a) * radius, sin(a) * radius));
      }
      return centers;
    }

    final sqrt3 = sqrt(3);
    final centers = <Offset>[Offset.zero];

    for (int i = 0; i < 6; i++) {
      final a = pi / 3 * i;
      centers.add(Offset(cos(a) * radius, sin(a) * radius));
    }
    for (int i = 0; i < 6; i++) {
      final a = pi / 3 * i + pi / 6;
      centers.add(Offset(cos(a) * radius * sqrt3, sin(a) * radius * sqrt3));
    }
    for (int i = 0; i < 6; i++) {
      final a = pi / 3 * i;
      centers.add(Offset(cos(a) * radius * 2, sin(a) * radius * 2));
    }
    return centers;
  }

  /// Neighbor pairs whose centers are exactly [spacing] apart.
  static List<(Offset, Offset)> adjacentPairs(
    List<Offset> centers,
    double spacing,
  ) {
    final pairs = <(Offset, Offset)>[];
    final tol = spacing * 0.06;
    for (int i = 0; i < centers.length; i++) {
      for (int j = i + 1; j < centers.length; j++) {
        final d = (centers[i] - centers[j]).distance;
        if ((d - spacing).abs() <= tol) {
          pairs.add((centers[i], centers[j]));
        }
      }
    }
    return pairs;
  }

  static Path vesicaLens(Offset c1, Offset c2, double radius) {
    final d = (c2 - c1).distance;
    if (d < 1e-5 || d > radius * 2.05) return Path();

    final mid = Offset((c1.dx + c2.dx) / 2, (c1.dy + c2.dy) / 2);
    final h = sqrt(max(0.0, radius * radius - (d * 0.5) * (d * 0.5)));
    final nx = -(c2.dy - c1.dy) / d;
    final ny = (c2.dx - c1.dx) / d;

    final p1 = Offset(mid.dx + nx * h, mid.dy + ny * h);
    final p2 = Offset(mid.dx - nx * h, mid.dy - ny * h);

    double sweep(Offset c, Offset from, Offset to) {
      var a0 = atan2(from.dy - c.dy, from.dx - c.dx);
      var a1 = atan2(to.dy - c.dy, to.dx - c.dx);
      var sweep = a1 - a0;
      while (sweep <= -pi) {
        sweep += 2 * pi;
      }
      while (sweep > pi) {
        sweep -= 2 * pi;
      }
      return sweep;
    }

    final path = Path()..moveTo(p1.dx, p1.dy);
    path.arcToPoint(
      p2,
      radius: Radius.circular(radius),
      rotation: 0,
      largeArc: false,
      clockwise: sweep(c1, p1, p2) < 0,
    );
    path.arcToPoint(
      p1,
      radius: Radius.circular(radius),
      rotation: 0,
      largeArc: false,
      clockwise: sweep(c2, p2, p1) < 0,
    );
    path.close();
    return path;
  }

  /// Ring index for 19-circle layout: 0=center, 1=inner hex, 2=mid, 3=outer.
  static int ringAt(Offset local, double spacing) {
    final d = local.distance;
    if (d < spacing * 0.2) return 0;
    if (d < spacing * 1.15) return 1;
    if (d < spacing * sqrt(3) * 1.15) return 2;
    return 3;
  }

  /// Coherent mandala pulse — shared breath with an outward-traveling wave.
  static double pulseLevel({
    required int ring,
    required double t,
    required double lowBand,
    required double highBand,
    required bool isPlaying,
  }) {
    if (!isPlaying) return PlaybackMotion.idleShimmer(t);

    final drive = (lowBand * 0.74 + highBand * 0.26).clamp(0.0, 1.0);
    final breathEased = PlaybackMotion.breathEased(t);
    final waveEased = PlaybackMotion.ringWaveEased(ring, t);

    return (0.28 + 0.34 * breathEased + 0.58 * waveEased) * drive;
  }

  /// Subtle whole-symbol scale tied to the shared breath.
  static double globalBreath({
    required double t,
    required double lowBand,
    required double energy,
    required bool isPlaying,
  }) {
    final idle = 1.0 + 0.006 * sin(t * PlaybackMotion.idleShimmerHz);
    if (!isPlaying) return idle;

    final e = energy.clamp(0.0, 1.0);
    return 1.0 + 0.022 * lowBand * e * PlaybackMotion.breathEased(t);
  }

  /// Per-ring radius swell — keeps circle geometry locked while feeling alive.
  static double ringRadiusScale({
    required int ring,
    required double t,
    required double lowBand,
    required bool isPlaying,
  }) {
    if (!isPlaying) return 1.0;
    return 1.0 +
        0.014 * lowBand * sin(PlaybackMotion.ringWave(ring, t) * pi);
  }
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

class HighTechSpeaker extends StatefulWidget {
  final bool isPlaying;
  final double? bpm;
  final Duration? position;
  final double volume;
  final Color accentColor;

  const HighTechSpeaker({
    super.key,
    required this.isPlaying,
    this.bpm,
    this.position,
    this.volume = 1.0,
    this.accentColor = PlayaColors.accent,
  });

  @override
  State<HighTechSpeaker> createState() => _HighTechSpeakerState();
}

class _HighTechSpeakerState extends State<HighTechSpeaker>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _animSeconds = 0;
  Duration _lastElapsed = Duration.zero;
  double _lowBand = 0;
  double _highBand = 0;

  double _beatHz() {
    final v = (widget.bpm ?? 120.0).clamp(55.0, 190.0);
    return v / 60.0;
  }

  double _smoothBand(
    double current,
    double target,
    double dtSeconds, {
    required double tauAttack,
    required double tauRelease,
  }) {
    final tau = target >= current ? tauAttack : tauRelease;
    final a = 1.0 - exp(-dtSeconds / max(1e-6, tau));
    return current + (target - current) * a;
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    if (widget.isPlaying) _ticker.start();
  }

  @override
  void didUpdateWidget(HighTechSpeaker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_ticker.isActive) {
      _ticker.start();
    } else if (!widget.isPlaying && _ticker.isActive) {
      _ticker.stop();
      _lowBand = 0;
      _highBand = 0;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    if (!dt.isFinite || dt <= 0) return;

    _animSeconds += dt;
    if (_animSeconds > 36000) _animSeconds -= 36000;

    if (widget.isPlaying) {
      final posSeconds = (widget.position?.inMicroseconds ?? 0) / 1e6;
      final t = posSeconds + _animSeconds;
      final beatHz = _beatHz();
      final lowTarget =
          pow(0.5 + 0.5 * sin(2 * pi * beatHz * t), 1.35).toDouble();
      final highTarget = (0.5 +
              0.5 *
                  sin(2 * pi * (beatHz * 6.0) * t + sin(t * 1.73) * 1.20))
          .clamp(0.0, 1.0);

      _lowBand = _smoothBand(
        _lowBand,
        lowTarget,
        dt,
        tauAttack: 0.14,
        tauRelease: 0.32,
      );
      _highBand = _smoothBand(
        _highBand,
        highTarget,
        dt,
        tauAttack: 0.08,
        tauRelease: 0.24,
      );
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final posSeconds = (widget.position?.inMicroseconds ?? 0) / 1e6;
    final t = widget.isPlaying ? posSeconds + _animSeconds : posSeconds;
    final energy =
        (widget.isPlaying ? 1.0 : 0.0) * widget.volume.clamp(0.0, 1.0);
    final expensive = SettingsService.instance.expensiveEffectsEnabled;

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = min(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 120.0,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 120.0,
        );

        return RepaintBoundary(
          child: CustomPaint(
            size: Size(side, side),
            painter: _SacredResonanceSpeakerPainter(
              t: t,
              isPlaying: widget.isPlaying,
              energy: energy,
              lowBand: _lowBand,
              highBand: _highBand,
              accentColor: widget.accentColor,
              highQuality: expensive,
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Painter — premium chassis + etched Flower of Life resonator
// ---------------------------------------------------------------------------

class _SacredResonanceSpeakerPainter extends CustomPainter {
  final double t;
  final bool isPlaying;
  final double energy;
  final double lowBand;
  final double highBand;
  final Color accentColor;
  final bool highQuality;

  _SacredResonanceSpeakerPainter({
    required this.t,
    required this.isPlaying,
    required this.energy,
    required this.lowBand,
    required this.highBand,
    required this.accentColor,
    required this.highQuality,
  });

  double get _intensityMul {
    final isNeon = SettingsService.instance.themeMode == SettingsService.themeNeon;
    return isNeon ? 1.75 : 1.15;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final side = min(size.width, size.height);
    final center = Offset(size.width / 2, size.height / 2);
    final r = side * 0.48;
    final e = (0.06 + 0.94 * energy).clamp(0.0, 1.0);
    final breathe = SacredFlowerGeometry.globalBreath(
      t: t,
      lowBand: lowBand,
      energy: e,
      isPlaying: isPlaying,
    );
    final flowerRadius = r * 0.78 * breathe;

    _drawChassis(canvas, center, r, e);
    _drawFaceRecess(canvas, center, r * 0.90, e);
    _drawHarmonicRings(canvas, center, flowerRadius, e);
    _drawFlowerOfLife(canvas, center, flowerRadius, e);
    _drawVesicaLenses(canvas, center, flowerRadius, e);
    _drawDriverAssembly(canvas, center, r * 0.30, e, breathe);
  }

  void _drawChassis(Canvas canvas, Offset center, double r, double e) {
    final outer = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: r * 2.05, height: r * 2.05),
      Radius.circular(r * 0.22),
    );

    canvas.drawRRect(
      outer.shift(const Offset(2, 3)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.50)
        ..maskFilter = highQuality
            ? const MaskFilter.blur(BlurStyle.normal, 5)
            : null,
    );

    canvas.drawRRect(
      outer,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(center.dx - r, center.dy - r),
          Offset(center.dx + r, center.dy + r),
          [
            PlayaColors.matteSlate,
            PlayaColors.matteGraphite,
            PlayaColors.obsidian,
            PlayaColors.deepVoid,
          ],
          const [0.0, 0.35, 0.72, 1.0],
        ),
    );

    DesignUtils.drawNoise(canvas, outer.outerRect.size, opacity: 0.05);

    canvas.drawRRect(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, r * 0.04)
        ..color = PlayaColors.borderSubtle,
    );

    canvas.drawRRect(
      outer.deflate(r * 0.06),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.6, r * 0.018)
        ..color = Colors.black.withValues(alpha: 0.55),
    );

    _drawCornerHardware(canvas, outer, r);
  }

  void _drawCornerHardware(Canvas canvas, RRect outer, double r) {
    final rect = outer.outerRect;
    final inset = r * 0.18;
    final boltR = r * 0.035;
    final corners = [
      Offset(rect.left + inset, rect.top + inset),
      Offset(rect.right - inset, rect.top + inset),
      Offset(rect.left + inset, rect.bottom - inset),
      Offset(rect.right - inset, rect.bottom - inset),
    ];
    for (final c in corners) {
      canvas.drawCircle(c, boltR, Paint()..color = PlayaColors.matteSlate);
      canvas.drawCircle(
        c,
        boltR * 0.45,
        Paint()..color = Colors.white.withValues(alpha: 0.07),
      );
    }
  }

  void _drawFaceRecess(Canvas canvas, Offset center, double r, double e) {
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            PlayaColors.matteCool.withValues(alpha: 0.35),
            PlayaColors.deepVoid,
            Colors.black.withValues(alpha: 0.92),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: r)),
    );
  }

  void _drawHarmonicRings(
    Canvas canvas,
    Offset center,
    double radius,
    double e,
  ) {
    final spacing = radius / 3.02;
    final ringRadii = [spacing, spacing * sqrt(3), spacing * 2.0];

    for (int ring = 1; ring <= 3; ring++) {
      final level = SacredFlowerGeometry.pulseLevel(
        ring: ring,
        t: t,
        lowBand: lowBand,
        highBand: highBand,
        isPlaying: isPlaying,
      );
      final alpha =
          (0.04 + 0.28 * level * e * _intensityMul).clamp(0.0, 0.45);
      final strokeW = max(0.6, radius * 0.012) * (0.85 + 0.25 * level);

      canvas.drawCircle(
        center,
        ringRadii[ring - 1],
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW
          ..color = accentColor.withValues(alpha: alpha)
          ..blendMode = isPlaying ? BlendMode.plus : BlendMode.srcOver,
      );
    }
  }

  void _drawFlowerOfLife(Canvas canvas, Offset center, double radius, double e) {
    final petalR = radius / 3.02;
    final spacing = petalR;
    final centers = SacredFlowerGeometry.flowerCenters(spacing);
    final baseStroke = max(0.5, radius * 0.014);

    for (final local in centers) {
      final ring = SacredFlowerGeometry.ringAt(local, spacing);
      final level = SacredFlowerGeometry.pulseLevel(
        ring: ring,
        t: t,
        lowBand: lowBand,
        highBand: highBand,
        isPlaying: isPlaying,
      );
      final radiusScale = SacredFlowerGeometry.ringRadiusScale(
        ring: ring,
        t: t,
        lowBand: lowBand,
        isPlaying: isPlaying,
      );
      final drawR = petalR * radiusScale;
      final alpha =
          (0.12 + 0.72 * level * e * _intensityMul).clamp(0.0, 1.0);
      final strokeW = baseStroke * (0.82 + 0.28 * level);

      if (highQuality && isPlaying && level > 0.22) {
        canvas.drawCircle(
          center + local,
          drawR,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = strokeW * 1.5
            ..color = accentColor.withValues(alpha: alpha * 0.26)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.014)
            ..blendMode = BlendMode.plus,
        );
      }

      canvas.drawCircle(
        center + local,
        drawR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW
          ..color = Color.lerp(
            PlayaColors.matteSlate.withValues(alpha: 0.38),
            accentColor,
            alpha,
          )!,
      );
    }
  }

  void _drawVesicaLenses(Canvas canvas, Offset center, double radius, double e) {
    if (!isPlaying && e < 0.05) return;

    final petalR = radius / 3.02;
    final spacing = petalR;
    final centers = SacredFlowerGeometry.flowerCenters(spacing);
    final pairs = SacredFlowerGeometry.adjacentPairs(centers, spacing);

    for (int i = 0; i < pairs.length; i++) {
      final (a, b) = pairs[i];
      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      final ring = SacredFlowerGeometry.ringAt(mid, spacing);
      final level = SacredFlowerGeometry.pulseLevel(
        ring: ring,
        t: t,
        lowBand: lowBand,
        highBand: highBand,
        isPlaying: isPlaying,
      );
      final alpha =
          (0.05 + 0.42 * level * e * _intensityMul).clamp(0.0, 0.68);

      final lens = SacredFlowerGeometry.vesicaLens(
        center + a,
        center + b,
        petalR * 1.002,
      );

      canvas.drawPath(
        lens,
        Paint()
          ..color = accentColor.withValues(alpha: alpha * 0.55)
          ..style = PaintingStyle.fill
          ..blendMode = BlendMode.plus
          ..maskFilter = highQuality
              ? MaskFilter.blur(BlurStyle.normal, radius * 0.012)
              : null,
      );
      canvas.drawPath(
        lens,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(0.4, radius * 0.008)
          ..color = accentColor.withValues(alpha: alpha * 0.85),
      );
    }
  }

  void _drawDriverAssembly(
    Canvas canvas,
    Offset center,
    double coreR,
    double e,
    double breathe,
  ) {
    final corePulse = SacredFlowerGeometry.pulseLevel(
      ring: 0,
      t: t,
      lowBand: lowBand,
      highBand: highBand,
      isPlaying: isPlaying,
    );
    final domeR =
        coreR * breathe * (isPlaying ? 1.0 + 0.06 * corePulse * e : 1.0);

    canvas.drawCircle(
      center,
      domeR * 1.35,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accentColor.withValues(alpha: 0.16 * lowBand * e * _intensityMul),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: center, radius: domeR * 1.5))
        ..blendMode = BlendMode.plus,
    );

    // Seed of Life at driver scale.
    const seedRings = 1;
    final seedSpacing = domeR * 0.52;
    final seedCenters =
        SacredFlowerGeometry.flowerCenters(seedSpacing, rings: seedRings);
    for (final local in seedCenters) {
      canvas.drawCircle(
        center + local,
        seedSpacing,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(0.5, coreR * 0.06)
          ..color = accentColor.withValues(
            alpha: (0.12 + 0.40 * highBand * e * _intensityMul).clamp(0.0, 0.70),
          ),
      );
    }

    canvas.drawCircle(
      center,
      domeR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color.lerp(Colors.white, accentColor, 0.25)!.withValues(alpha: 0.35),
            PlayaColors.matteGraphite,
            PlayaColors.deepVoid,
          ],
          stops: const [0.0, 0.48, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: domeR)),
    );

    canvas.drawCircle(
      center,
      domeR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.6, coreR * 0.05)
        ..color = PlayaColors.border,
    );

    final dustR = domeR * (0.22 + 0.10 * lowBand * e);
    canvas.drawCircle(
      center,
      dustR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accentColor.withValues(alpha: 0.95 * e),
            accentColor.withValues(alpha: 0.35 * e),
            Colors.transparent,
          ],
          stops: const [0.0, 0.42, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: dustR * 1.3))
        ..blendMode = BlendMode.plus,
    );

    canvas.drawCircle(
      center,
      dustR * 0.42,
      Paint()..color = PlayaColors.deepVoid,
    );
  }

  @override
  bool shouldRepaint(covariant _SacredResonanceSpeakerPainter oldDelegate) {
    return t != oldDelegate.t ||
        isPlaying != oldDelegate.isPlaying ||
        energy != oldDelegate.energy ||
        lowBand != oldDelegate.lowBand ||
        highBand != oldDelegate.highBand ||
        accentColor != oldDelegate.accentColor ||
        highQuality != oldDelegate.highQuality;
  }
}