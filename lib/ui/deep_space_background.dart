import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

enum DeepSpaceMode { background, overlay }

class DeepSpaceBackground extends StatefulWidget {
  final bool subtle;
  final DeepSpaceMode mode;

  const DeepSpaceBackground({
    super.key,
    this.subtle = false,
    this.mode = DeepSpaceMode.background,
  });

  @override
  State<DeepSpaceBackground> createState() => _DeepSpaceBackgroundState();
}

class _DeepSpaceBackgroundState extends State<DeepSpaceBackground>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  final ValueNotifier<double> _repaint = ValueNotifier<double>(0.0);
  final List<_Star> _stars = [];
  final List<_ShootingStar> _shootingStars = [];
  final Random _rnd = Random();
  Size? _lastSize;

  // Nebula clouds
  final List<Offset> _nebulaCenters = [];
  final List<Offset> _nebulaVels = [];
  final List<bool> _nebulaEnabled = [];
  final List<Color> _nebulaColors = [];

  Duration _lastElapsed = Duration.zero;
  double _timeSeconds = 0.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();

    if (widget.mode == DeepSpaceMode.background) {
      // Init nebula clouds
      for (int i = 0; i < 4; i++) {
        _nebulaCenters.add(Offset(_rnd.nextDouble(), _rnd.nextDouble()));
        final ang = _rnd.nextDouble() * pi * 2;
        final sp = 0.0015 + _rnd.nextDouble() * 0.0028;
        _nebulaVels.add(Offset(cos(ang) * sp, sin(ang) * sp));
        _nebulaEnabled.add(_rnd.nextDouble() < 0.35); // ~65% rarer
        _nebulaColors.add(
          HSVColor.fromAHSV(
            0.30,
            195.0 + _rnd.nextDouble() * 90,
            0.68,
            0.55,
          ).toColor(),
        );
      }

      if (_nebulaEnabled.every((e) => !e) && _nebulaEnabled.isNotEmpty) {
        _nebulaEnabled[_rnd.nextInt(_nebulaEnabled.length)] = true;
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  // Removed didUpdateWidget to prevent re-initialization stutter
  // The painter will handle the 'subtle' flag by drawing fewer stars.

  void _initStars(Size size) {
    _stars.clear();
    const count = 300; // Always init max stars
    for (int i = 0; i < count; i++) {
      // Star Color Temperature (more varied but still realistic)
      // Bias: mostly near-white, with a spectrum of subtle tints.
      final r = _rnd.nextDouble();
      late final Color color;
      if (r < 0.62) {
        final hue = 190.0 + _rnd.nextDouble() * 110.0;
        color =
            HSVColor.fromAHSV(
              1.0,
              hue,
              0.08 + _rnd.nextDouble() * 0.10,
              1.0,
            ).toColor();
      } else if (r < 0.78) {
        final hue = 40.0 + _rnd.nextDouble() * 35.0;
        color =
            HSVColor.fromAHSV(
              1.0,
              hue,
              0.14 + _rnd.nextDouble() * 0.16,
              1.0,
            ).toColor();
      } else if (r < 0.90) {
        final hue = 195.0 + _rnd.nextDouble() * 35.0;
        color =
            HSVColor.fromAHSV(
              1.0,
              hue,
              0.16 + _rnd.nextDouble() * 0.18,
              1.0,
            ).toColor();
      } else if (r < 0.97) {
        final hue = 10.0 + _rnd.nextDouble() * 22.0;
        color =
            HSVColor.fromAHSV(
              1.0,
              hue,
              0.18 + _rnd.nextDouble() * 0.20,
              1.0,
            ).toColor();
      } else {
        final hue =
            _rnd.nextBool()
                ? (150.0 + _rnd.nextDouble() * 25.0)
                : (285.0 + _rnd.nextDouble() * 20.0);
        color =
            HSVColor.fromAHSV(
              1.0,
              hue,
              0.22 + _rnd.nextDouble() * 0.22,
              1.0,
            ).toColor();
      }

      // Parallax depth (0.0 = far, 1.0 = near)
      final depth = _rnd.nextDouble();

      _stars.add(
        _Star(
          x: _rnd.nextDouble(),
          y: _rnd.nextDouble(),
          size:
              (0.5 + _rnd.nextDouble() * 2.0) *
              (widget.subtle ? 0.8 : 1.0) *
              (0.5 + depth * 0.5),
          brightness: 0.3 + _rnd.nextDouble() * 0.7,
          twinkleSpeed: 0.5 + _rnd.nextDouble() * 3.0,
          twinklePhase: _rnd.nextDouble() * 2 * pi,
          color: color,
          driftSpeed:
              (0.005 + _rnd.nextDouble() * 0.015) *
              (0.5 + depth), // Near stars move faster
          depth: depth,
        ),
      );
    }
    _lastSize = size;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (_lastSize != size) {
          if (widget.mode == DeepSpaceMode.background) {
            _initStars(size);
          }
          _lastSize = size;
        }

        return Container(
          color:
              widget.mode == DeepSpaceMode.background
                  ? const Color(0xFF06070A)
                  : Colors.transparent,
          child: CustomPaint(
            painter: _StarFieldPainter(
              stars: _stars,
              shootingStars: _shootingStars,
              subtle: widget.subtle,
              nebulaCenters: _nebulaCenters,
              nebulaEnabled: _nebulaEnabled,
              nebulaColors: _nebulaColors,
              mode: widget.mode,
              time: _repaint,
            ),
          ),
        );
      },
    );
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    final dt = (elapsed - _lastElapsed).inMilliseconds / 1000.0;
    _lastElapsed = elapsed;
    if (dt.isFinite && dt > 0) {
      _timeSeconds += dt;
      if (_timeSeconds > 3600) _timeSeconds -= 3600;
    }

    if (widget.mode == DeepSpaceMode.background) {
      // Update Stars (Twinkle + Drift)
      for (final star in _stars) {
        star.update(dt);
      }

      // Drift nebula across the scene so it doesn't stay anchored.
      for (int i = 0; i < _nebulaCenters.length; i++) {
        if (i >= _nebulaVels.length || i >= _nebulaEnabled.length) break;
        if (!_nebulaEnabled[i]) continue;

        final v = _nebulaVels[i];
        final steer = Offset(
          sin(_timeSeconds * 0.05 + i * 2.1) * 0.00025,
          cos(_timeSeconds * 0.043 + i * 1.7) * 0.00022,
        );
        var nv = v + steer;
        final speed = nv.distance;
        if (speed > 0.0045) {
          nv = nv * (0.0045 / speed);
        }
        _nebulaVels[i] = nv;

        var c = _nebulaCenters[i] + nv * dt;
        bool wrapped = false;
        if (c.dx < -0.2) {
          c = Offset(c.dx + 1.4, c.dy);
          wrapped = true;
        } else if (c.dx > 1.2) {
          c = Offset(c.dx - 1.4, c.dy);
          wrapped = true;
        }
        if (c.dy < -0.2) {
          c = Offset(c.dx, c.dy + 1.4);
          wrapped = true;
        } else if (c.dy > 1.2) {
          c = Offset(c.dx, c.dy - 1.4);
          wrapped = true;
        }
        _nebulaCenters[i] = c;

        if (wrapped && _rnd.nextDouble() < 0.25) {
          _nebulaColors[i] =
              HSVColor.fromAHSV(
                0.30,
                195.0 + _rnd.nextDouble() * 90,
                0.62 + _rnd.nextDouble() * 0.25,
                0.50 + _rnd.nextDouble() * 0.18,
              ).toColor();
        }
      }
    }

    if (widget.mode == DeepSpaceMode.overlay) {
      // Manage Shooting Stars / Comets
      if (!widget.subtle && dt.isFinite && dt > 0) {
        // Two-style mix:
        // - Frequent but subtle streaks
        // - Rare but bigger cinematic events
        const subtleRatePerSecond = 0.22; // ~1 every 4.5s
        const cinematicRatePerSecond =
            0.0165; // 45% rarer than 0.03 (~1 every 60s)

        if (_rnd.nextDouble() < subtleRatePerSecond * dt) {
          _spawnShootingStar(style: _CometStyle.subtle);
        }
        if (_rnd.nextDouble() < cinematicRatePerSecond * dt) {
          _spawnShootingStar(style: _CometStyle.cinematic);
        }
      }

      // Update Shooting Stars
      _shootingStars.removeWhere((s) => s.isFinished);
      final w = _lastSize?.width ?? 1000.0;
      final h = _lastSize?.height ?? 1000.0;
      for (final s in _shootingStars) {
        s.update(dt, w, h);
      }
    }

    // Avoid rebuilding the widget tree every frame; only repaint the canvas.
    _repaint.value = _timeSeconds;
  }

  void _spawnShootingStar({required _CometStyle style}) {
    final w = _lastSize?.width ?? 1000;
    final h = _lastSize?.height ?? 1000;

    // Dynamic Spawn Logic
    double startX, startY;
    double angle;

    final side = _rnd.nextInt(4); // 0: Top, 1: Right, 2: Bottom, 3: Left

    switch (side) {
      case 0: // Top
        startX = _rnd.nextDouble() * w;
        startY = -50;
        angle = (45 + _rnd.nextDouble() * 90) * pi / 180.0; // Downwards
        break;
      case 1: // Right
        startX = w + 50;
        startY = _rnd.nextDouble() * h;
        angle = (135 + _rnd.nextDouble() * 90) * pi / 180.0; // Leftwards
        break;
      case 2: // Bottom
        startX = _rnd.nextDouble() * w;
        startY = h + 50;
        angle = (225 + _rnd.nextDouble() * 90) * pi / 180.0; // Upwards
        break;
      case 3: // Left
      default:
        startX = -50;
        startY = _rnd.nextDouble() * h;
        angle = (-45 + _rnd.nextDouble() * 90) * pi / 180.0; // Rightwards
        break;
    }

    // Base speed (px/s)
    // Subtle comets skew slower so they stay visible longer.
    // Cinematic comets keep a wider speed range but are rarer.
    late final double baseSpeedPxPerSec;
    if (style == _CometStyle.subtle) {
      const minSpeed = 260.0;
      const maxSpeed = 820.0;
      final t = pow(_rnd.nextDouble(), 2.25).toDouble();
      baseSpeedPxPerSec = minSpeed + (maxSpeed - minSpeed) * t;
    } else {
      baseSpeedPxPerSec = 420.0 + _rnd.nextDouble() * 720.0;
    }

    // Random Color (More realistic meteor colors)
    final Color color;
    if (style == _CometStyle.cinematic) {
      // Match the reference look: green head + cool/blue trail.
      const cinematicColors = [
        Color(0xFF7CFFB0), // green-cyan
        Color(0xFFB3E5FC), // cool blue
        Color(0xFFE1F5FE), // white-blue
      ];
      color = cinematicColors[_rnd.nextInt(cinematicColors.length)];
    } else {
      final colors = [
        const Color(0xFFB3E5FC), // Light Blue (Ice/Magnesium)
        const Color(0xFFE1F5FE), // White-Blue
        const Color(0xFFFFF9C4), // Pale Yellow (Dust/Sodium)
        const Color(0xFFFFCCBC), // Pale Orange
        const Color(0xFFB2DFDB), // Teal (Iron)
        Colors.white,
      ];
      color = colors[_rnd.nextInt(colors.length)];
    }

    // Random Size Scale
    double sizeScale = 1.0;
    if (style == _CometStyle.subtle) {
      sizeScale = 0.35 + _rnd.nextDouble() * 0.55;
    } else {
      sizeScale = 2.2 + _rnd.nextDouble() * 2.2;
    }

    // Speed scaling by size:
    // - Subtle: smaller = slower (so tiny streaks don't zip by)
    // - Cinematic: larger = slower
    late final double speedPxPerSec;
    if (style == _CometStyle.subtle) {
      speedPxPerSec = baseSpeedPxPerSec * pow(sizeScale, 0.8);
    } else {
      speedPxPerSec =
          baseSpeedPxPerSec / pow(sizeScale, style.speedSizeExponent);
    }
    final lifetimeSeconds =
        style == _CometStyle.subtle
            ? (0.62 + 0.32 * sizeScale).clamp(0.55, 1.25)
            : (1.35 + 0.35 * sqrt(sizeScale)).clamp(1.3, 3.2);
    final seed = _rnd.nextInt(1 << 31);

    _shootingStars.add(
      _ShootingStar(
        x: startX / w,
        y: startY / h,
        angle: angle,
        speedPxPerSec: speedPxPerSec,
        color: color,
        sizeScale: sizeScale,
        lifetimeSeconds: lifetimeSeconds,
        style: style,
        debrisSeed: seed,
      ),
    );
  }
}

class _CometStyle {
  final double tailLengthMul;
  final double tailWidthMul;
  final double coreWidthMul;
  final double headMul;
  final double alphaMul;
  final int debrisCount;
  final double speedSizeExponent;

  const _CometStyle._({
    required this.tailLengthMul,
    required this.tailWidthMul,
    required this.coreWidthMul,
    required this.headMul,
    required this.alphaMul,
    required this.debrisCount,
    required this.speedSizeExponent,
  });

  static const subtle = _CometStyle._(
    tailLengthMul: 0.22,
    tailWidthMul: 0.55,
    coreWidthMul: 0.65,
    headMul: 0.6,
    alphaMul: 0.55,
    debrisCount: 3,
    speedSizeExponent: 0.75,
  );

  static const cinematic = _CometStyle._(
    tailLengthMul: 0.95,
    tailWidthMul: 0.95,
    coreWidthMul: 0.95,
    headMul: 1.45,
    alphaMul: 1.0,
    debrisCount: 6,
    speedSizeExponent: 0.95,
  );
}

class _Star {
  double x, y; // 0.0 to 1.0
  double size;
  double brightness;
  double twinkleSpeed;
  double twinklePhase;
  Color color;
  double driftSpeed;
  double depth;

  _Star({
    required this.x,
    required this.y,
    required this.size,
    required this.brightness,
    required this.twinkleSpeed,
    required this.twinklePhase,
    required this.color,
    required this.driftSpeed,
    required this.depth,
  });

  double opacityAt(double timeSeconds) {
    final t = timeSeconds * twinkleSpeed + twinklePhase;
    final wave = sin(t) + sin(t * 2.7) * 0.5;
    // Far stars twinkle less.
    final twinkleAmp = 0.18 * (0.35 + depth * 0.65);
    return (brightness + wave * twinkleAmp).clamp(0.08, 1.0);
  }

  void update(double dt) {
    // Parallax drift (slowly move left)
    x -= driftSpeed * dt;
    if (x < 0) x += 1.0;
  }
}

class _DebrisSpec {
  final double distFactor;
  final double lateralFactor;
  final double radius;
  final double alpha;

  const _DebrisSpec({
    required this.distFactor,
    required this.lateralFactor,
    required this.radius,
    required this.alpha,
  });
}

class _ShootingStar {
  double x, y;
  double angle;
  double speedPxPerSec;
  double _elapsedSeconds = 0.0;
  double progress = 0.0;
  bool isFinished = false;
  Color color;
  double sizeScale;
  double lifetimeSeconds;
  final _CometStyle style;
  final List<_DebrisSpec> debris;

  // Shape variance (primarily for cinematic comets)
  final double tailCurveAmp;
  final double tailWidthJitter;
  final double coreWidthJitter;
  final double headStretch;
  final double headSkew;

  _ShootingStar({
    required this.x,
    required this.y,
    required this.angle,
    required this.speedPxPerSec,
    required this.color,
    this.sizeScale = 1.0,
    required this.lifetimeSeconds,
    required this.style,
    required int debrisSeed,
  }) : debris = _buildDebris(debrisSeed, style.debrisCount),
       tailCurveAmp = _buildTailCurveAmp(debrisSeed, style),
       tailWidthJitter = _buildWidthJitter(debrisSeed ^ 0x51f3a, style),
       coreWidthJitter = _buildWidthJitter(debrisSeed ^ 0x9b77d, style),
       headStretch = _buildHeadStretch(debrisSeed ^ 0x3311, style),
       headSkew = _buildHeadSkew(debrisSeed ^ 0x77aa, style);

  static double _buildTailCurveAmp(int seed, _CometStyle style) {
    if (style != _CometStyle.cinematic) return 0.0;
    final r = Random(seed);
    // Straighter trail like the reference (still slight natural variation).
    return 0.03 + r.nextDouble() * 0.09; // fraction of tail length
  }

  static double _buildWidthJitter(int seed, _CometStyle style) {
    if (style != _CometStyle.cinematic) return 1.0;
    final r = Random(seed);
    return 0.78 + r.nextDouble() * 0.55;
  }

  static double _buildHeadStretch(int seed, _CometStyle style) {
    if (style != _CometStyle.cinematic) return 1.0;
    final r = Random(seed);
    return 0.85 + r.nextDouble() * 0.70;
  }

  static double _buildHeadSkew(int seed, _CometStyle style) {
    if (style != _CometStyle.cinematic) return 0.0;
    final r = Random(seed);
    return (r.nextDouble() - 0.5) *
        0.5; // ellipse offset along flight direction
  }

  static List<_DebrisSpec> _buildDebris(int seed, int count) {
    final r = Random(seed);
    return List.generate(count, (_) {
      return _DebrisSpec(
        distFactor: r.nextDouble() * 0.28,
        lateralFactor: (r.nextDouble() - 0.5) * 7.0,
        radius: 0.5 + r.nextDouble() * 1.4,
        alpha: 0.15 + r.nextDouble() * 0.85,
      );
    });
  }

  void update(double dt, double w, double h) {
    if (isFinished) return;
    if (!dt.isFinite || dt <= 0) return;

    _elapsedSeconds += dt;
    // Keep progress available for styling, but don't end the comet by time.
    // Comets should retain their form until they leave the screen.
    progress = (_elapsedSeconds / lifetimeSeconds).clamp(0.0, 1.0);

    // Move along angle (normalized coords)
    x += cos(angle) * (speedPxPerSec * dt) / w;
    y += sin(angle) * (speedPxPerSec * dt) / h;

    // Cull if far offscreen.
    if (x < -0.25 || x > 1.25 || y < -0.25 || y > 1.25) {
      isFinished = true;
    }
  }
}

class _StarFieldPainter extends CustomPainter {
  final List<_Star> stars;
  final List<_ShootingStar> shootingStars;
  final bool subtle;
  final List<Offset> nebulaCenters;
  final List<bool> nebulaEnabled;
  final List<Color> nebulaColors;
  final DeepSpaceMode mode;
  final ValueNotifier<double> time;

  _StarFieldPainter({
    required this.stars,
    required this.shootingStars,
    required this.subtle,
    required this.nebulaCenters,
    required this.nebulaEnabled,
    required this.nebulaColors,
    required this.mode,
    required this.time,
  }) : super(repaint: time);

  @override
  void paint(Canvas canvas, Size size) {
    final timeSeconds = time.value;
    final w = size.width;
    final h = size.height;
    final paint = Paint();

    if (mode == DeepSpaceMode.background) {
      // 1. Draw Nebula Clouds (Background)
      // Deep Space Base
      canvas.drawColor(const Color(0xFF040508), BlendMode.src);

      // Keep nebula visible even in subtle mode.
      // Make nebula ~65% harder to see overall.
      final nebulaAlphaMul = (subtle ? 0.65 : 1.0) * 0.35;
      for (int i = 0; i < nebulaCenters.length; i++) {
        if (i < nebulaEnabled.length && !nebulaEnabled[i]) continue;
        final c = nebulaCenters[i];
        // Larger drift so it's clearly non-static (still subtle enough for music UI).
        final drift = Offset(
          sin(timeSeconds * 0.06 + i * 1.7) * 0.06,
          cos(timeSeconds * 0.05 + i * 1.3) * 0.045,
        );
        final baseCenter = Offset((c.dx + drift.dx) * w, (c.dy + drift.dy) * h);

        // "Legit" nebula: multiple overlapping blobs whose centers and radii
        // wobble slowly, creating evolving structure instead of a static circle.
        final baseRadius = min(w, h) * 0.72;
        paint.blendMode = BlendMode.screen;
        for (int j = 0; j < 4; j++) {
          final phase = i * 3.11 + j * 1.87;
          final wobble = 0.10 + 0.05 * sin(timeSeconds * 0.08 + phase);
          final blobOffset = Offset(
            (sin(timeSeconds * 0.11 + phase) * 0.11 +
                    sin(timeSeconds * 0.03 + phase * 2.3) * 0.05) *
                w,
            (cos(timeSeconds * 0.10 + phase) * 0.09 +
                    cos(timeSeconds * 0.028 + phase * 2.1) * 0.05) *
                h,
          );
          final center = baseCenter + blobOffset;
          final radius = baseRadius * (0.55 + j * 0.12) * (1.0 + wobble);

          paint.shader = ui.Gradient.radial(
            center,
            radius,
            [
              nebulaColors[i].withValues(
                alpha: (0.20 - j * 0.03) * nebulaAlphaMul,
              ),
              nebulaColors[i].withValues(
                alpha: (0.09 - j * 0.015) * nebulaAlphaMul,
              ),
              Colors.transparent,
            ],
            const [0.0, 0.55, 1.0],
          );
          canvas.drawCircle(center, radius, paint);
        }

        // Readable inner "ion" core that also breathes slightly.
        final coreCenter =
            baseCenter +
            Offset(
              sin(timeSeconds * 0.12 + i) * 12,
              cos(timeSeconds * 0.10 + i) * 10,
            );
        final coreRadius =
            baseRadius * (0.32 + 0.03 * sin(timeSeconds * 0.16 + i));
        paint.shader = ui.Gradient.radial(
          coreCenter,
          coreRadius,
          [
            Colors.white.withValues(alpha: 0.06 * nebulaAlphaMul),
            nebulaColors[i].withValues(alpha: 0.15 * nebulaAlphaMul),
            Colors.transparent,
          ],
          const [0.0, 0.62, 1.0],
        );
        paint.blendMode = BlendMode.plus;
        canvas.drawCircle(coreCenter, coreRadius, paint);
      }
      paint.blendMode = BlendMode.srcOver;
      paint.shader = null;

      // 2. Draw Stars
      final drawCount = subtle ? 50 : stars.length;
      for (int i = 0; i < drawCount && i < stars.length; i++) {
        final star = stars[i];
        final op = star.opacityAt(timeSeconds);
        final alpha = op * (subtle ? 0.25 : 0.85);
        final pos = Offset(star.x * w, star.y * h);

        // Soft glow for a small subset of bright, near stars.
        if (!subtle && star.size > 1.6 && op > 0.82) {
          paint.color = star.color.withValues(alpha: alpha * 0.12);
          canvas.drawCircle(pos, star.size * 2.6, paint);
        }

        paint.color = star.color.withValues(alpha: alpha);
        canvas.drawCircle(pos, star.size, paint);
      }
    }

    if (mode == DeepSpaceMode.overlay) {
      // 3. Draw Shooting Stars / Comets
      if (subtle) return;

      for (final s in shootingStars) {
        final start = Offset(s.x * w, s.y * h);
        final perp = Offset(cos(s.angle + pi / 2), sin(s.angle + pi / 2));
        final cinematic = s.style == _CometStyle.cinematic;
        final speedFactor = (s.speedPxPerSec / 800.0).clamp(0.55, 1.45);
        final baseTail =
            min(w, h) *
            0.28 *
            (0.75 + 0.18 * s.sizeScale) *
            speedFactor *
            s.style.tailLengthMul;
        // Keep a stable comet shape while it traverses the screen.
        // Cinematic comets: longer dust tail.
        final tailLen = cinematic ? (baseTail * 1.62) : baseTail;
        final end =
            start - Offset(cos(s.angle) * tailLen, sin(s.angle) * tailLen);

        final alpha = s.style.alphaMul.clamp(0.0, 1.0);

        double hash01(double v) {
          final x = sin(v * 12.9898) * 43758.5453;
          return x - x.floorToDouble();
        }

        // 1. The Tail (Gaseous Trail)
        final tailPaint =
            Paint()
              ..shader = ui.Gradient.linear(
                start,
                end,
                [
                  s.color.withValues(alpha: alpha * 0.3),
                  s.color.withValues(alpha: alpha * 0.05),
                  Colors.transparent,
                ],
                [0.0, 0.5, 1.0],
              )
              ..strokeWidth =
                  3.0 * s.sizeScale * s.style.tailWidthMul * s.tailWidthJitter
              ..strokeCap = StrokeCap.round
              ..style = PaintingStyle.stroke;

        Offset? ctrl;
        if (cinematic && s.tailCurveAmp > 0) {
          final mid = Offset(
            (start.dx + end.dx) * 0.5,
            (start.dy + end.dy) * 0.5,
          );
          final curvePx =
              (s.tailCurveAmp * tailLen) *
              sin(timeSeconds * 0.55 + s.headSkew * 12);
          ctrl = mid + perp * curvePx;
        }

        Offset pointOnTail(double t) {
          if (ctrl == null) {
            return Offset.lerp(start, end, t) ?? start;
          }
          final it = 1.0 - t;
          return start * (it * it) + ctrl * (2.0 * it * t) + end * (t * t);
        }

        if (cinematic) {
          // Fan-shaped dust tail (broader + more opaque, with irregular edges)
          final int seed =
              ((s.angle * 100000).round() ^
                  (s.speedPxPerSec.round() << 1) ^
                  ((s.sizeScale * 100).round() << 3) ^
                  (s.headSkew * 1000).round());

          final dustPaint =
              Paint()
                ..style = PaintingStyle.fill
                ..blendMode = BlendMode.plus
                ..maskFilter = MaskFilter.blur(
                  BlurStyle.normal,
                  8 * s.sizeScale,
                );

          final baseW =
              (1.7 + 1.15 * s.sizeScale) *
              s.style.tailWidthMul *
              s.tailWidthJitter;
          const segs = 18;
          final left = <Offset>[];
          final right = <Offset>[];

          for (int i = 0; i <= segs; i++) {
            final t = i / segs;
            final c = pointOnTail(t);

            // Wider farther from the nucleus (fan), slightly asymmetrical.
            final noise =
                0.92 + 0.18 * hash01(seed * 0.001 + t * 9.3 + i * 0.17);
            // Ice-cream-cone fan: tight at the head, flares quickly.
            final tt = pow(t, 1.25).toDouble();
            final spread = (0.24 + 2.25 * tt) * (1.05 - 0.28 * t);
            final width = baseW * spread * noise;
            final skew = s.headSkew * (0.35 + 0.25 * t);

            left.add(c + perp * (width * (1.05 + skew)));
            right.add(c - perp * (width * (0.95 - skew)));
          }

          final dustPath = Path()..moveTo(left.first.dx, left.first.dy);
          for (int i = 1; i < left.length; i++) {
            dustPath.lineTo(left[i].dx, left[i].dy);
          }
          for (int i = right.length - 1; i >= 0; i--) {
            dustPath.lineTo(right[i].dx, right[i].dy);
          }
          dustPath.close();

          final comaTint =
              HSLColor.fromColor(
                s.color,
              ).withHue(140).withSaturation(0.55).withLightness(0.78).toColor();
          final dustColor = Color.lerp(comaTint, Colors.white, 0.48)!;
          dustPaint.shader = ui.Gradient.linear(
            start,
            end,
            [
              dustColor.withValues(alpha: alpha * 0.62),
              s.color.withValues(alpha: alpha * 0.24),
              Colors.transparent,
            ],
            const [0.0, 0.55, 1.0],
          );
          canvas.drawPath(dustPath, dustPaint);

          // Dust streaks inside the cone (fine trails)
          final streakPaint =
              Paint()
                ..isAntiAlias = true
                ..style = PaintingStyle.stroke
                ..strokeCap = StrokeCap.round
                ..strokeJoin = StrokeJoin.round
                ..blendMode = BlendMode.plus
                ..strokeWidth =
                    1.15 *
                    s.sizeScale *
                    s.style.coreWidthMul *
                    s.coreWidthJitter
                ..maskFilter = MaskFilter.blur(
                  BlurStyle.normal,
                  3.2 * s.sizeScale,
                );
          final streakEnd =
              start -
              Offset(
                cos(s.angle) * (tailLen * 1.55),
                sin(s.angle) * (tailLen * 1.55),
              );
          for (int k = 0; k < 5; k++) {
            final drift =
                (hash01(seed * 0.11 + k * 7.3) - 0.5) *
                baseW *
                (0.65 + 0.35 * k);
            final skewDrift = drift + (s.headSkew * baseW * 0.55);
            final p0 = start + perp * skewDrift;
            final p1 = streakEnd + perp * (skewDrift * (1.15 + 0.12 * k));
            streakPaint.shader = ui.Gradient.linear(
              p0,
              p1,
              [
                Colors.white.withValues(alpha: alpha * 0.22),
                dustColor.withValues(alpha: alpha * 0.14),
                Colors.transparent,
              ],
              const [0.0, 0.55, 1.0],
            );
            canvas.drawLine(p0, p1, streakPaint);
          }

          // Ion tail (thin, straighter, cooler)
          const ionTint = Color(0xFF66CFFF);
          final ionPaint =
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeCap = StrokeCap.round
                ..blendMode = BlendMode.plus
                ..strokeWidth =
                    1.1 * s.sizeScale * s.style.coreWidthMul * s.coreWidthJitter
                ..maskFilter = MaskFilter.blur(
                  BlurStyle.normal,
                  2.0 * s.sizeScale,
                )
                ..shader = ui.Gradient.linear(
                  start,
                  end,
                  [
                    Colors.white.withValues(alpha: alpha * 0.90),
                    ionTint.withValues(alpha: alpha * 0.32),
                    Colors.transparent,
                  ],
                  const [0.0, 0.18, 1.0],
                );
          final ionPath = Path()..moveTo(start.dx, start.dy);
          for (int i = 1; i <= segs; i++) {
            final t = i / segs;
            final c = pointOnTail(t);
            ionPath.lineTo(c.dx, c.dy);
          }
          canvas.drawPath(ionPath, ionPaint);
        } else {
          // Subtle streak
          if (ctrl != null) {
            final path =
                Path()
                  ..moveTo(start.dx, start.dy)
                  ..quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy);
            canvas.drawPath(path, tailPaint);
          } else {
            canvas.drawLine(start, end, tailPaint);
          }
        }

        // 2. The Core Trail (Hotter, thinner)
        if (!cinematic) {
          tailPaint.shader = ui.Gradient.linear(
            start,
            end,
            [
              Colors.white.withValues(alpha: alpha * 0.9),
              s.color.withValues(alpha: alpha * 0.4),
              Colors.transparent,
            ],
            [0.0, 0.2, 1.0],
          );
          tailPaint.strokeWidth =
              1.0 * s.sizeScale * s.style.coreWidthMul * s.coreWidthJitter;
          if (ctrl != null) {
            final path =
                Path()
                  ..moveTo(start.dx, start.dy)
                  ..quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy);
            canvas.drawPath(path, tailPaint);
          } else {
            canvas.drawLine(start, end, tailPaint);
          }
        }

        // 3. The Head (Coma)
        final headBase = 8.0 * s.sizeScale * s.style.headMul;
        if (cinematic) {
          final comaTint =
              HSLColor.fromColor(
                s.color,
              ).withHue(140).withSaturation(0.55).withLightness(0.78).toColor();
          final comaColor = Color.lerp(comaTint, Colors.white, 0.35)!;

          canvas.save();
          canvas.translate(start.dx, start.dy);
          canvas.rotate(s.angle);
          final skewPx = headBase * 0.5 * s.headSkew;

          // Big diffuse coma cloud (white-green)
          const flareMul =
              0.078; // reduced further: 0.13 * 0.60 (additional -40%)
          final comaOuter = Rect.fromCenter(
            center: Offset(skewPx * 0.55, 0),
            width: headBase * 6.1 * s.headStretch,
            height: headBase * 3.7,
          );
          paint.shader = ui.Gradient.radial(
            Offset(skewPx * 0.55, 0),
            headBase * 3.45,
            [
              comaColor.withValues(alpha: alpha * 0.36 * flareMul),
              comaTint.withValues(alpha: alpha * 0.26 * flareMul),
              Colors.transparent,
            ],
            const [0.0, 0.55, 1.0],
          );
          paint.maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            24 * s.sizeScale * flareMul,
          );
          canvas.drawOval(comaOuter, paint);
          paint.shader = null;

          final outer = Rect.fromCenter(
            center: Offset(skewPx, 0),
            width: headBase * 2.2 * s.headStretch,
            height: headBase * 1.4,
          );
          paint.color = comaTint.withValues(alpha: alpha * 0.22 * flareMul);
          paint.maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            12 * s.sizeScale * flareMul,
          );
          canvas.drawOval(outer, paint);

          final inner = Rect.fromCenter(
            center: Offset(skewPx * 0.6, 0),
            width: headBase * 1.15 * s.headStretch,
            height: headBase * 0.9,
          );
          paint.color = comaColor.withValues(alpha: alpha * 0.55 * flareMul);
          paint.maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            5 * s.sizeScale * flareMul,
          );
          canvas.drawOval(inner, paint);
          paint.maskFilter = null;

          // Dark irregular nucleus
          final nucR = 2.20 * s.sizeScale;
          final nuc = Path();
          const points = 9;
          for (int i = 0; i < points; i++) {
            final a = (i / points) * 2 * pi;
            final rr =
                nucR * (0.72 + 0.48 * hash01((i + 1) * 1.7 + s.headSkew * 9.1));
            final p = Offset(skewPx * 0.48 + cos(a) * rr, sin(a) * rr);
            if (i == 0) {
              nuc.moveTo(p.dx, p.dy);
            } else {
              nuc.lineTo(p.dx, p.dy);
            }
          }
          nuc.close();
          paint
            ..shader = null
            ..maskFilter = null
            ..blendMode = BlendMode.srcOver
            ..color = Colors.black.withValues(alpha: alpha * 0.92);
          canvas.drawPath(nuc, paint);

          // Tiny bright core sparkle inside coma
          paint
            ..blendMode = BlendMode.plus
            ..color = Colors.white.withValues(alpha: alpha * 0.85);
          canvas.drawCircle(
            Offset(skewPx * 0.52, -0.2),
            1.15 * s.sizeScale,
            paint,
          );

          canvas.restore();
        } else {
          // Outer Glow
          paint.color = s.color.withValues(alpha: alpha * 0.25);
          paint.maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            10 * s.sizeScale * s.style.headMul,
          );
          canvas.drawCircle(start, headBase, paint);

          // Inner Glow
          paint.color = s.color.withValues(alpha: alpha * 0.6);
          paint.maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            4 * s.sizeScale * s.style.headMul,
          );
          canvas.drawCircle(start, headBase * 0.5, paint);
          paint.maskFilter = null;

          // Solid Core
          paint.color = Colors.white.withValues(alpha: alpha);
          canvas.drawCircle(
            start,
            1.5 * s.sizeScale * (0.9 + 0.15 * s.style.headMul),
            paint,
          );
        }

        // 4. Sparkles / Debris (Simple simulation)
        for (final d in s.debris) {
          final dist = d.distFactor * tailLen;
          final offset = d.lateralFactor * s.sizeScale;

          final debrisPos =
              start -
              Offset(cos(s.angle) * dist, sin(s.angle) * dist) +
              Offset(
                cos(s.angle + pi / 2) * offset,
                sin(s.angle + pi / 2) * offset,
              );

          paint.color = s.color.withValues(alpha: alpha * 0.35 * d.alpha);
          canvas.drawCircle(debrisPos, d.radius, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StarFieldPainter oldDelegate) {
    return oldDelegate.subtle != subtle ||
        oldDelegate.mode != mode ||
        oldDelegate.stars != stars ||
        oldDelegate.shootingStars != shootingStars ||
        oldDelegate.nebulaCenters != nebulaCenters ||
        oldDelegate.nebulaColors != nebulaColors ||
        oldDelegate.nebulaEnabled != nebulaEnabled;
  }
}
