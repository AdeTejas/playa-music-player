// ignore_for_file: prefer_const_constructors

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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
  double? _lastDpr;

  // Nebula clouds
  final List<Offset> _nebulaCenters = [];
  final List<Offset> _nebulaVels = [];
  final List<bool> _nebulaEnabled = [];
  final List<Color> _nebulaColors = [];
  final List<_NebulaSpeck> _nebulaSpecks = [];

  Duration _lastElapsed = Duration.zero;
  double _timeSeconds = 0.0;

  Color _randomNebulaColor({required bool isWindows}) {
    final r = _rnd.nextDouble();
    // Windows UHD mode: broader gamut + more variety.
    if (isWindows) {
      if (r < 0.55) {
        // Teal/blue ionized gas
        final hue = 175.0 + _rnd.nextDouble() * 85.0;
        return HSVColor.fromAHSV(
          0.34,
          hue,
          0.72 + _rnd.nextDouble() * 0.18,
          0.55 + _rnd.nextDouble() * 0.20,
        ).toColor();
      }
      if (r < 0.80) {
        // Magenta/purple dust
        final hue = 265.0 + _rnd.nextDouble() * 60.0;
        return HSVColor.fromAHSV(
          0.30,
          hue,
          0.72 + _rnd.nextDouble() * 0.20,
          0.50 + _rnd.nextDouble() * 0.22,
        ).toColor();
      }
      // Rare warm tint
      final hue = 25.0 + _rnd.nextDouble() * 35.0;
      return HSVColor.fromAHSV(
        0.22,
        hue,
        0.55 + _rnd.nextDouble() * 0.20,
        0.50 + _rnd.nextDouble() * 0.18,
      ).toColor();
    }

    // Default palette (kept closer to previous look)
    return HSVColor.fromAHSV(
      0.30,
      195.0 + _rnd.nextDouble() * 90,
      0.68,
      0.55,
    ).toColor();
  }

  void _initNebulaSpecks({required bool isWindows}) {
    _nebulaSpecks.clear();
    if (!isWindows) return;

    final r = Random(0xBADC0DE);
    // Lightweight static texture layer that reads like gaseous detail.
    for (int i = 0; i < 2200; i++) {
      final t = r.nextDouble();
      final hue = (180.0 + r.nextDouble() * 160.0) % 360.0;
      _nebulaSpecks.add(
        _NebulaSpeck(
          x: r.nextDouble(),
          y: r.nextDouble(),
          radius: 0.35 + pow(r.nextDouble(), 2.4).toDouble() * 1.15,
          alpha: 0.010 + t * 0.020,
          color: HSVColor.fromAHSV(1.0, hue, 0.22 + t * 0.25, 1.0).toColor(),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();

    if (widget.mode == DeepSpaceMode.background) {
      final isWindows =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

      // Init nebula clouds
      for (int i = 0; i < 4; i++) {
        _nebulaCenters.add(Offset(_rnd.nextDouble(), _rnd.nextDouble()));
        final ang = _rnd.nextDouble() * pi * 2;
        final sp = 0.0015 + _rnd.nextDouble() * 0.0028;
        _nebulaVels.add(Offset(cos(ang) * sp, sin(ang) * sp));
        _nebulaEnabled.add(_rnd.nextDouble() < 0.35); // ~65% rarer
        _nebulaColors.add(_randomNebulaColor(isWindows: isWindows));
      }

      _initNebulaSpecks(isWindows: isWindows);

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

  void _initStars(Size size, double devicePixelRatio) {
    _stars.clear();

    final isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    const baseArea = 1920.0 * 1080.0;
    final area = max(1.0, size.width * size.height);
    final areaFactor = sqrt(area / baseArea).clamp(0.85, 2.25);
    final uhdMul = isWindows ? 1.35 : 1.0;

    final count = (300 * (isWindows ? areaFactor : 1.0) * uhdMul)
        .round()
        .clamp(300, 1400);

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

        // Favor smaller stars for UHD: more micro-detail, less "blob" feel.
        final sizeRand =
          isWindows ? pow(_rnd.nextDouble(), 1.65).toDouble() : _rnd.nextDouble();

        // Keep a sensible minimum so micro-stars survive at DPR 1.
        final minStar = isWindows ? 0.35 : 0.5;
        final maxStar = isWindows ? 2.35 : 2.5;

        // Slightly tighten sizes on higher DPR so the field stays crisp.
        final dprTighten =
          isWindows
            ? (1.0 / max(1.0, devicePixelRatio)).clamp(0.75, 1.0)
            : 1.0;

      _stars.add(
        _Star(
          x: _rnd.nextDouble(),
          y: _rnd.nextDouble(),
          seed: _rnd.nextInt(1 << 31),
          size:
              (minStar + sizeRand * (maxStar - minStar)) *
              (widget.subtle ? 0.8 : 1.0) *
              (0.5 + depth * 0.5) *
              dprTighten,
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
    _lastDpr = devicePixelRatio;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final dpr = MediaQuery.devicePixelRatioOf(context);
        if (_lastSize != size || _lastDpr != dpr) {
          if (widget.mode == DeepSpaceMode.background) {
            _initStars(size, dpr);
          }
          _lastSize = size;
          _lastDpr = dpr;
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
              nebulaSpecks: _nebulaSpecks,
              mode: widget.mode,
              time: _repaint,
              devicePixelRatio: dpr,
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
          final isWindows =
              !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
          _nebulaColors[i] = _randomNebulaColor(isWindows: isWindows);
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
    // Sun direction (upper area of the screen) — ion tail points away from this.
    final sunAngle = -pi / 2 + (_rnd.nextDouble() - 0.5) * 0.8;

    _shootingStars.add(
      _ShootingStar(
        x: startX / w,
        y: startY / h,
        angle: angle,
        sunAngle: sunAngle,
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
    tailWidthMul: 0.57,
    coreWidthMul: 0.57,
    headMul: 1.45,
    alphaMul: 1.0,
    debrisCount: 6,
    speedSizeExponent: 0.95,
  );
}

class _Star {
  double x, y; // 0.0 to 1.0
  final int seed;
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
    required this.seed,
    required this.size,
    required this.brightness,
    required this.twinkleSpeed,
    required this.twinklePhase,
    required this.color,
    required this.driftSpeed,
    required this.depth,
  });

  static double _hash11(double x) {
    final v = sin(x * 12.9898) * 43758.5453;
    return v - v.floorToDouble();
  }

  double opacityAt(double timeSeconds, {required bool isWindows}) {
    final t = timeSeconds * twinkleSpeed + twinklePhase;

    // Base periodic twinkle (kept subtle so it doesn't look like blinking).
    final baseWave = sin(t) + sin(t * 2.7) * 0.5;

    // Aperiodic scintillation (cheap pseudo-noise) so UHD stars feel less uniform.
    final n1 = _hash11(timeSeconds * 0.65 + seed * 0.0000013);
    final n2 = _hash11(timeSeconds * 1.25 + seed * 0.0000007);
    final noise = (n1 - 0.5) * 1.15 + (n2 - 0.5) * 0.55;

    final wave = baseWave + (isWindows ? noise : noise * 0.55);

    // Far stars twinkle less.
    final twinkleAmpBase = 0.18 * (0.35 + depth * 0.65);
    final twinkleAmp = isWindows ? twinkleAmpBase * 1.25 : twinkleAmpBase;
    return (brightness + wave * twinkleAmp).clamp(0.05, 1.0);
  }

  void update(double dt) {
    // Parallax drift (slowly move left)
    x -= driftSpeed * dt;
    if (x < 0) x += 1.0;
  }
}

class _NebulaSpeck {
  final double x;
  final double y;
  final double radius;
  final double alpha;
  final Color color;

  const _NebulaSpeck({
    required this.x,
    required this.y,
    required this.radius,
    required this.alpha,
    required this.color,
  });
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
  double sunAngle;
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
    required this.sunAngle,
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
  final List<_NebulaSpeck> nebulaSpecks;
  final DeepSpaceMode mode;
  final ValueNotifier<double> time;
  final double devicePixelRatio;

  _StarFieldPainter({
    required this.stars,
    required this.shootingStars,
    required this.subtle,
    required this.nebulaCenters,
    required this.nebulaEnabled,
    required this.nebulaColors,
    required this.nebulaSpecks,
    required this.mode,
    required this.time,
    required this.devicePixelRatio,
  }) : super(repaint: time);

  bool get _isWindowsPaint => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  double _hash01(double v) {
    final x = sin(v * 12.9898) * 43758.5453;
    return x - x.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final timeSeconds = time.value;
    final w = size.width;
    final h = size.height;
    final paint = Paint();

    final isWindows = _isWindowsPaint;
    final dpr = max(1.0, devicePixelRatio);
    // Keep blur closer to a physical amount on UHD so it stays crisp.
    final blurMul = isWindows ? (0.80 / dpr).clamp(0.55, 0.90) : 1.0;

    if (mode == DeepSpaceMode.background) {
      // 1. Draw Nebula Clouds (Background)
      // Deep Space Base
      canvas.drawColor(const Color(0xFF040508), BlendMode.src);

      // Keep nebula visible even in subtle mode.
      // Make nebula ~65% harder to see overall.
      final nebulaAlphaMul = (subtle ? 0.65 : 1.0) * (isWindows ? 0.44 : 0.35);
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
        final blobCount = isWindows ? 6 : 4;
        for (int j = 0; j < blobCount; j++) {
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

        // Extra filament / clump detail (Windows UHD only).
        if (isWindows && !subtle) {
          final filamentColor = Color.lerp(nebulaColors[i], Colors.white, 0.18)!;
          for (int k = 0; k < 10; k++) {
            final seed = i * 97.1 + k * 13.7;
            final fx = (_hash01(seed + 0.7) - 0.5) * w * 0.35;
            final fy = (_hash01(seed + 2.9) - 0.5) * h * 0.28;
            final rr = baseRadius * (0.10 + 0.22 * _hash01(seed + 4.3));
            final center2 = baseCenter + Offset(fx, fy);
            paint.shader = ui.Gradient.radial(
              center2,
              rr,
              [
                filamentColor.withValues(
                  alpha: (0.050 + 0.030 * _hash01(seed + 1.4)) * nebulaAlphaMul,
                ),
                nebulaColors[i].withValues(
                  alpha: (0.020 + 0.020 * _hash01(seed + 6.7)) * nebulaAlphaMul,
                ),
                Colors.transparent,
              ],
              const [0.0, 0.55, 1.0],
            );
            canvas.drawCircle(center2, rr, paint);
          }
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

        // Subtle dark dust lanes (adds depth/contrast) – Windows only.
        if (isWindows && !subtle) {
          paint
            ..shader = ui.Gradient.radial(
              baseCenter,
              baseRadius * 0.72,
              [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.10 * nebulaAlphaMul),
              ],
              const [0.0, 1.0],
            )
            ..blendMode = BlendMode.multiply;
          canvas.drawCircle(baseCenter, baseRadius * 0.72, paint);
        }
      }
      paint.blendMode = BlendMode.srcOver;
      paint.shader = null;

      // Nebula texture specks (Windows UHD only).
      if (isWindows && !subtle && nebulaSpecks.isNotEmpty) {
        paint
          ..blendMode = BlendMode.plus
          ..shader = null
          ..maskFilter = null;
        final drift = Offset(
          sin(timeSeconds * 0.018) * 0.03,
          cos(timeSeconds * 0.016) * 0.025,
        );
        for (final s in nebulaSpecks) {
          final x = (s.x + drift.dx) % 1.0;
          final y = (s.y + drift.dy) % 1.0;
          paint.color = s.color.withValues(alpha: s.alpha);
          canvas.drawCircle(Offset(x * w, y * h), s.radius, paint);
        }
        paint.blendMode = BlendMode.srcOver;
      }

      // 2. Draw Stars
      final drawCount = subtle ? 50 : stars.length;
      for (int i = 0; i < drawCount && i < stars.length; i++) {
        final star = stars[i];
        final op = star.opacityAt(timeSeconds, isWindows: isWindows);
        final alpha = op * (subtle ? 0.25 : (isWindows ? 0.92 : 0.85));
        final pos = Offset(star.x * w, star.y * h);

        var starColor = star.color;
        var starRadius = star.size;
        if (isWindows && !subtle) {
          final sparkle = ((op - 0.60) / 0.40).clamp(0.0, 1.0);
          starColor = Color.lerp(star.color, Colors.white, sparkle * 0.20)!;
          starRadius = star.size * (1.0 + 0.12 * sparkle);
        }

        // Soft glow for a small subset of bright, near stars.
        if (!subtle && starRadius > 1.6 && op > (isWindows ? 0.80 : 0.82)) {
          paint.color = starColor.withValues(alpha: alpha * 0.12);
          canvas.drawCircle(
            pos,
            starRadius * (isWindows ? 2.05 : 2.6),
            paint,
          );
        }

        // Add star spikes for brighter stars (more realistic appearance)
        if (!subtle && starRadius > 1.2 && op > (isWindows ? 0.75 : 0.78)) {
          const spikeCount = 4; // Cross-shaped spikes
          final spikeLength = starRadius * (isWindows ? 1.8 : 2.2);
          final spikeWidth = starRadius * 0.3;

          paint.color = starColor.withValues(alpha: alpha * 0.6);
          for (int i = 0; i < spikeCount; i++) {
            final angle = (i * pi) / 2; // 90 degrees apart
            final startOffset = Offset(
              cos(angle) * starRadius * 0.8,
              sin(angle) * starRadius * 0.8,
            );
            final endOffset = Offset(
              cos(angle) * spikeLength,
              sin(angle) * spikeLength,
            );

            final path = Path()
              ..moveTo(pos.dx + startOffset.dx, pos.dy + startOffset.dy)
              ..lineTo(pos.dx + endOffset.dx, pos.dy + endOffset.dy)
              ..lineTo(pos.dx + endOffset.dx + sin(angle) * spikeWidth,
                      pos.dy + endOffset.dy - cos(angle) * spikeWidth)
              ..lineTo(pos.dx + startOffset.dx + sin(angle) * spikeWidth * 0.5,
                      pos.dy + startOffset.dy - cos(angle) * spikeWidth * 0.5)
              ..close();

            canvas.drawPath(path, paint);
          }
        }

        // Main star body
        paint.color = starColor.withValues(alpha: alpha);
        canvas.drawCircle(pos, starRadius, paint);
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

        final tailLenMul = cinematic ? 1.82 : 1.0;
        final tailLen = baseTail * tailLenMul;
        final end =
            start - Offset(cos(s.angle) * tailLen, sin(s.angle) * tailLen);

        final alpha = s.style.alphaMul.clamp(0.0, 1.0);

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
              (sin(timeSeconds * 0.55 + s.headSkew * 12) +
               sin(timeSeconds * 1.9 + s.headSkew * 7) * 0.18);
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
                  8.0 * s.sizeScale * blurMul,
                );

          final baseW =
              (1.7 + 1.15 * s.sizeScale) *
              s.style.tailWidthMul *
              s.tailWidthJitter;

          final segs = isWindows ? 28 : 18;
          final left = <Offset>[];
          final right = <Offset>[];

          for (int i = 0; i <= segs; i++) {
            final t = i / segs;
            var c = pointOnTail(t);
            final turb = (_hash01(seed * 0.007 + t * 17.3 + timeSeconds * 3.1) - 0.5) * baseW * 0.045 * (1.0 - t * 0.7);
            c = c + perp * turb;
            final tailTaper = 0.25 + 0.75 * pow(1.0 - t, 0.85).toDouble();
            final noise = 0.91 + 0.19 * _hash01(seed * 0.001 + t * 9.3 + i * 0.17);

            final spread = (0.24 + 2.25 * pow(t, 1.25)) * (1.05 - 0.28 * t);

            final width = baseW * spread * noise * tailTaper;
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

          // Warm cream color for the dust tail (reflected sunlight off dust)
          final dustColor = Color.lerp(const Color(0xFFFFF8E1), Colors.white, 0.35)!;
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

          final spinePaint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..blendMode = BlendMode.plus
            ..strokeWidth = 1.1 * s.sizeScale
            ..shader = ui.Gradient.linear(
              start,
              end,
              [
                Colors.white.withValues(alpha: alpha * 0.42),
                Colors.transparent,
              ],
            );
          canvas.drawPath(dustPath, spinePaint);

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
                  (3.2 * s.sizeScale) * blurMul,
                );
          final streakEnd =
              start -
              Offset(
                cos(s.angle) * (tailLen * 1.55),
                sin(s.angle) * (tailLen * 1.55),
              );
          for (int k = 0; k < (isWindows ? 7 : 5); k++) {
            final drift =
                (_hash01(seed * 0.11 + k * 7.3) - 0.5) *
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

          // Ion tail — points away from the sun (not the velocity direction)
          // This creates the characteristic split-tail look of real comets.
          final ionTailAngle = s.sunAngle + pi;
          final ionTailLen = tailLen * 1.3;
          final ionEnd = start + Offset(cos(ionTailAngle) * ionTailLen, sin(ionTailAngle) * ionTailLen);

          const ionTint = Color(0xFF66CFFF);
          final ionPaint =
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeCap = StrokeCap.round
                ..blendMode = BlendMode.plus
                ..maskFilter = MaskFilter.blur(
                  BlurStyle.normal,
                  (2.0 * s.sizeScale) * blurMul,
                )
                ..shader = ui.Gradient.linear(
                  start,
                  ionEnd,
                  [
                    Colors.white.withValues(alpha: alpha * 0.85),
                    ionTint.withValues(alpha: alpha * 0.25),
                    Colors.transparent,
                  ],
                  const [0.0, 0.15, 1.0],
                );
          final ionSegs = isWindows ? 24 : 16;
          final ionPerp = Offset(cos(ionTailAngle + pi / 2), sin(ionTailAngle + pi / 2));
          for (int i = 0; i < ionSegs; i++) {
            final t0 = i / ionSegs;
            final t1 = (i + 1) / ionSegs;
            final c0 = Offset.lerp(start, ionEnd, t0)! + ionPerp * (sin(t0 * 17.0 + timeSeconds * 3.1) * s.sizeScale * 0.3);
            final c1 = Offset.lerp(start, ionEnd, t1)! + ionPerp * (sin(t1 * 17.0 + timeSeconds * 3.1) * s.sizeScale * 0.18);
            final tm = (t0 + t1) * 0.5;
            final taper = 0.15 + 0.85 * pow(1.0 - tm, 0.70).toDouble();
            ionPaint.strokeWidth = (1.2 * s.sizeScale * s.style.coreWidthMul * s.coreWidthJitter) * taper;
            canvas.drawLine(c0, c1, ionPaint);
          }
        } else {
          // Subtle streak, tapered toward the tail.
          final segs = isWindows ? 16 : 10;
          final baseW =
              3.0 * s.sizeScale * s.style.tailWidthMul * s.tailWidthJitter;
          for (int i = 0; i < segs; i++) {
            final t0 = i / segs;
            final t1 = (i + 1) / segs;
            final p0 = pointOnTail(t0);
            final p1 = pointOnTail(t1);
            final tm = (t0 + t1) * 0.5;
            final taper = 0.25 + 0.75 * pow(1.0 - tm, 0.85).toDouble();
            tailPaint.strokeWidth = baseW * taper;
            canvas.drawLine(p0, p1, tailPaint);
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
          final segs = isWindows ? 16 : 10;
          final baseW =
              1.0 * s.sizeScale * s.style.coreWidthMul * s.coreWidthJitter;
          for (int i = 0; i < segs; i++) {
            final t0 = i / segs;
            final t1 = (i + 1) / segs;
            final p0 = pointOnTail(t0);
            final p1 = pointOnTail(t1);
            final tm = (t0 + t1) * 0.5;
            final taper = 0.25 + 0.75 * pow(1.0 - tm, 0.85).toDouble();
            tailPaint.strokeWidth = baseW * taper;
            canvas.drawLine(p0, p1, tailPaint);
          }
        }

        // 3. The Head (Coma)
        final headDamp = (cinematic && s.sizeScale > 3.2) ? 0.76 : 1.0;
        final headBase = 8.0 * s.sizeScale * s.style.headMul * headDamp;
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

          // Big diffuse coma cloud (white-green) with irregular shape
          const flareMul = 0.10;
          const comaGlowWidthMul = 0.66;

          // Create irregular coma shape using multiple overlapping ovals
          final comaSeed = ((s.angle * 100000).round() ^
                           (s.speedPxPerSec.round() << 1) ^
                           ((s.sizeScale * 100).round() << 3) ^
                           (s.headSkew * 1000).round());
            final comaShapes = 2 + (pow(s.sizeScale, 0.72) * 1.7).round().clamp(0, 4);
          for (int i = 0; i < comaShapes; i++) {
            final shapeSeed = comaSeed + i * 17;
            final offsetX = skewPx * 0.55 + (0.3 * _hash01(shapeSeed * 0.01) - 0.15) * headBase;
            final offsetY = (0.2 * _hash01(shapeSeed * 0.02) - 0.1) * headBase;
            final shapeWidth = headBase * (4.5 + 1.6 * _hash01(shapeSeed * 0.03)) * s.headStretch * comaGlowWidthMul;
            final shapeHeight = headBase * (2.8 + 0.9 * _hash01(shapeSeed * 0.04)) * comaGlowWidthMul;

            final comaRect = Rect.fromCenter(
              center: Offset(offsetX, offsetY),
              width: shapeWidth,
              height: shapeHeight,
            );

            final shapeAlpha = alpha * (0.25 + 0.15 * _hash01(shapeSeed * 0.05)) * flareMul;
            paint.shader = ui.Gradient.radial(
              Offset(offsetX, offsetY),
              shapeWidth * 0.4,
              [
                comaColor.withValues(alpha: shapeAlpha),
                comaTint.withValues(alpha: shapeAlpha * 0.7),
                Colors.transparent,
              ],
              const [0.0, 0.6, 1.0],
            );
            paint.maskFilter = MaskFilter.blur(
              BlurStyle.normal,
              (18 + 8 * _hash01(shapeSeed * 0.06)) * s.sizeScale * flareMul * comaGlowWidthMul * blurMul,
            );
            canvas.drawOval(comaRect, paint);
          }
          paint.shader = null;

          final outer = Rect.fromCenter(
            center: Offset(skewPx, 0),
            width: headBase * 2.2 * s.headStretch * comaGlowWidthMul,
            height: headBase * 1.4 * comaGlowWidthMul,
          );
          paint.color = comaTint.withValues(alpha: alpha * 0.22 * flareMul);
          paint.maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            (12 * s.sizeScale * flareMul * comaGlowWidthMul) * blurMul,
          );
          canvas.drawOval(outer, paint);

          final inner = Rect.fromCenter(
            center: Offset(skewPx * 0.6, 0),
            width: headBase * 1.15 * s.headStretch * comaGlowWidthMul,
            height: headBase * 0.9 * comaGlowWidthMul,
          );
          paint.color = comaColor.withValues(alpha: alpha * 0.55 * flareMul);
          paint.maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            (5 * s.sizeScale * flareMul * comaGlowWidthMul) * blurMul,
          );
          canvas.drawOval(inner, paint);
          paint.maskFilter = null;

          // Dark irregular nucleus elongated along velocity axis (potato shape)
          final nucR = 2.20 * s.sizeScale;
          final nucElongation = 1.6;
          final cosVel = cos(s.angle);
          final sinVel = sin(s.angle);
          final nuc = Path();
          const points = 14;
          final nucleusSeed = ((s.angle * 100000).round() ^
                              (s.speedPxPerSec.round() << 1) ^
                              ((s.sizeScale * 100).round() << 3) ^
                              (s.headSkew * 1000).round());

          for (int i = 0; i < points; i++) {
            final a = (i / points) * 2 * pi;
            final rr = nucR * (0.62 + 0.52 * _hash01(nucleusSeed * 0.0009 + i * 1.97 + timeSeconds * 0.4));
            final dx = cos(a) * rr;
            final dy = sin(a) * rr;
            final along = dx * cosVel + dy * sinVel;
            final across = -dx * sinVel + dy * cosVel;
            final ex = cosVel * along * nucElongation - sinVel * across;
            final ey = sinVel * along * nucElongation + cosVel * across;
            final p = Offset(skewPx * 0.48 + ex, ey);
            if (i == 0) {
              nuc.moveTo(p.dx, p.dy);
            } else {
              nuc.lineTo(p.dx, p.dy);
            }
          }
          nuc.close();

          // Add surface texture/details to nucleus (elongated to match)
          final detailPath = Path();
          for (int i = 0; i < 8; i++) {
            final a = (i / 8) * 2 * pi + _hash01(nucleusSeed * 0.01 + i) * 0.5;
            final r = nucR * (0.75 + 0.25 * _hash01(nucleusSeed * 0.02 + i));
            final detailSize = nucR * 0.15 * _hash01(nucleusSeed * 0.03 + i);
            final dx = cos(a) * r;
            final dy = sin(a) * r;
            final along = dx * cosVel + dy * sinVel;
            final across = -dx * sinVel + dy * cosVel;
            final ex = cosVel * along * nucElongation - sinVel * across;
            final ey = sinVel * along * nucElongation + cosVel * across;
            final p = Offset(skewPx * 0.48 + ex, ey);

            detailPath.addOval(Rect.fromCenter(
              center: p,
              width: detailSize,
              height: detailSize * 0.6,
            ));
          }

          paint
            ..shader = null
            ..maskFilter = null
            ..blendMode = BlendMode.srcOver
            ..color = Colors.black.withValues(alpha: alpha * 0.95);
          canvas.drawPath(nuc, paint);

          // Add surface details
          paint.color = Color(0xFF2A2A2A).withValues(alpha: alpha * 0.7);
          canvas.drawPath(detailPath, paint);

          // Add plasma jets emanating from the nucleus
          final jetSeed = nucleusSeed + 2000;
          final jetCount = (sqrt(s.sizeScale) * 1.05).round().clamp(1, 2);
          for (int i = 0; i < jetCount; i++) {
            final jetAngle = (i / jetCount) * 2 * pi + _hash01(jetSeed * 0.01 + i * 23) * 0.8;
            final jetLength = headBase * (0.8 + 0.6 * _hash01(jetSeed * 0.02 + i * 24)) * headDamp;
            final jetWidth = headBase * (0.15 + 0.1 * _hash01(jetSeed * 0.03 + i * 25)) * headDamp;

            final jetStart = Offset(skewPx * 0.48, 0);
            final jetEnd = Offset(
              jetStart.dx + cos(jetAngle) * jetLength,
              jetStart.dy + sin(jetAngle) * jetLength,
            );

            // Jet glow
            paint.blendMode = BlendMode.plus;
            paint.color = Color(0xFF66DDFF).withValues(alpha: alpha * 0.4);
            paint.maskFilter = MaskFilter.blur(BlurStyle.normal, jetWidth * 3 * blurMul);

            final jetPath = Path()
              ..moveTo(jetStart.dx, jetStart.dy)
              ..lineTo(jetEnd.dx, jetEnd.dy)
              ..lineTo(jetEnd.dx + sin(jetAngle) * jetWidth, jetEnd.dy - cos(jetAngle) * jetWidth)
              ..lineTo(jetStart.dx + sin(jetAngle) * jetWidth * 0.3, jetStart.dy - cos(jetAngle) * jetWidth * 0.3)
              ..close();

            canvas.drawPath(jetPath, paint);

            // Jet core
            paint.color = Colors.white.withValues(alpha: alpha * 0.6);
            paint.maskFilter = MaskFilter.blur(BlurStyle.normal, jetWidth * blurMul);
            canvas.drawLine(jetStart, jetEnd, paint);
          }
          paint.blendMode = BlendMode.srcOver;
          paint.maskFilter = null;

          // Tiny bright core sparkle inside coma
          paint
            ..blendMode = BlendMode.plus
            ..color = Colors.white.withValues(alpha: alpha * 0.85);
          canvas.drawCircle(
            Offset(skewPx * 0.52, -0.2),
            1.15 * s.sizeScale,
            paint,
          );

          // Add trailing fragments that break off
          final fragmentSeed = nucleusSeed + 1000;
          final fragmentCount = (sqrt(s.sizeScale) * 1.4).round().clamp(0, 3);
          for (int i = 0; i < fragmentCount; i++) {
            final fragmentDist = 0.1 + 0.4 * _hash01(fragmentSeed * 0.1 + i * 3.7);
            final fragmentAngle = s.angle + (0.3 * _hash01(fragmentSeed * 0.2 + i * 4.1) - 0.15);
            final fragmentPos = Offset(
              start.dx - cos(fragmentAngle) * (tailLen * fragmentDist),
              start.dy - sin(fragmentAngle) * (tailLen * fragmentDist),
            );

            final fragmentSize = 0.8 + 1.2 * _hash01(fragmentSeed * 0.3 + i * 5.3);
            final fragmentAlpha = alpha * (0.3 + 0.4 * _hash01(fragmentSeed * 0.4 + i * 6.1));

            // Fragment glow
            paint.color = s.color.withValues(alpha: fragmentAlpha * 0.4);
            paint.maskFilter = MaskFilter.blur(BlurStyle.normal, fragmentSize * 2 * blurMul);
            canvas.drawCircle(fragmentPos, fragmentSize * 3, paint);

            // Fragment core
            paint.color = Colors.white.withValues(alpha: fragmentAlpha * 0.8);
            paint.maskFilter = null;
            canvas.drawCircle(fragmentPos, fragmentSize, paint);
          }

          canvas.restore();
        } else {
          // Outer Glow
          paint.color = s.color.withValues(alpha: alpha * 0.25);
          paint.maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            (10 * s.sizeScale * s.style.headMul) * blurMul,
          );
          canvas.drawCircle(start, headBase, paint);

          // Inner Glow
          paint.color = s.color.withValues(alpha: alpha * 0.6);
          paint.maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            (4 * s.sizeScale * s.style.headMul) * blurMul,
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
          final largeDamp = (cinematic && s.sizeScale > 3.2) ? 0.65 : 1.0;
          final eject = (0.6 + 1.8 * s.progress) * (0.4 + 0.6 * _hash01(d.distFactor * 31.7 + timeSeconds * 1.8)) * s.sizeScale * largeDamp;

          final debrisPos =
              start -
              Offset(cos(s.angle) * dist, sin(s.angle) * dist) +
              Offset(
                cos(s.angle + pi / 2) * (offset + eject),
                sin(s.angle + pi / 2) * (offset + eject * 0.6),
              );

          paint.color = s.color.withValues(alpha: alpha * 0.35 * d.alpha * (1.0 - s.progress * 0.4));
          canvas.drawCircle(debrisPos, d.radius * largeDamp, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StarFieldPainter oldDelegate) {
    return oldDelegate.subtle != subtle ||
        oldDelegate.mode != mode ||
        oldDelegate.devicePixelRatio != devicePixelRatio ||
        oldDelegate.stars != stars ||
        oldDelegate.shootingStars != shootingStars ||
        oldDelegate.nebulaCenters != nebulaCenters ||
        oldDelegate.nebulaColors != nebulaColors ||
        oldDelegate.nebulaSpecks != nebulaSpecks ||
        oldDelegate.nebulaEnabled != nebulaEnabled;
  }
}
