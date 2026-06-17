// ignore_for_file: prefer_const_constructors

import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'deep_space_noise.dart';

enum DeepSpaceMode { background, overlay }

enum StarLayer { far, mid, near }

/// Adaptive repaint cadence — lowers GPU work without visible stutter.
class DeepSpaceFrameBudget {
  DeepSpaceFrameBudget._();

  static const double backgroundImmersiveFps = 30;
  static const double backgroundSubtleFps = 22;
  static const double overlayActiveFps = 45;
  static const double overlayIdleFps = 18;

  static double minFrameIntervalSeconds({
    required DeepSpaceMode mode,
    required bool subtle,
    required bool hasComets,
    required bool appActive,
  }) {
    if (!appActive) return double.infinity;
    if (mode == DeepSpaceMode.overlay) {
      final fps = hasComets ? overlayActiveFps : overlayIdleFps;
      return 1.0 / fps;
    }
    final fps = subtle ? backgroundSubtleFps : backgroundImmersiveFps;
    return 1.0 / fps;
  }
}

/// Adaptive quality budget for stars/nebula/comets across platforms.
class _QualityBudget {
  final int starCount;
  final int nebulaClouds;
  final int nebulaSpecks;
  final int nebulaBlobCount;
  final int noiseGridCols;
  final int noiseGridRows;
  final bool filaments;
  final bool dustLanes;
  final bool noiseField;
  final double nebulaAlpha;
  final double starAlpha;
  final int subtleStarFloor;

  const _QualityBudget({
    required this.starCount,
    required this.nebulaClouds,
    required this.nebulaSpecks,
    required this.nebulaBlobCount,
    required this.noiseGridCols,
    required this.noiseGridRows,
    required this.filaments,
    required this.dustLanes,
    required this.noiseField,
    required this.nebulaAlpha,
    required this.starAlpha,
    required this.subtleStarFloor,
  });

  factory _QualityBudget.resolve({
    required double dpr,
    required bool subtle,
    required bool isDesktop,
    double starDensity = 1.0,
  }) {
    final areaBoost = isDesktop ? 1.25 : 1.0;
    final dprBoost = (dpr / 2.0).clamp(0.85, 1.35);
    final density = starDensity.clamp(0.40, 1.35);
    final baseStars = (subtle ? 1150.0 : 2100.0) * density;

    return _QualityBudget(
      starCount: (baseStars * areaBoost * dprBoost).round().clamp(
        (700 * density).round(),
        (3000 * density).round(),
      ),
      nebulaClouds: isDesktop ? 2 : 2,
      nebulaSpecks: subtle ? 0 : ((isDesktop ? 220 : 140) * dprBoost).round(),
      nebulaBlobCount: isDesktop ? 2 : 2,
      noiseGridCols: isDesktop ? 8 : 6,
      noiseGridRows: isDesktop ? 6 : 5,
      filaments: !subtle,
      dustLanes: !subtle,
      noiseField: !subtle,
      nebulaAlpha: subtle ? 0.11 : (isDesktop ? 0.18 : 0.16),
      starAlpha: subtle ? 0.94 : (isDesktop ? 1.0 : 0.98),
      subtleStarFloor: subtle ? 420 : 0,
    );
  }
}

class DeepSpaceBackground extends StatefulWidget {
  final bool subtle;
  final DeepSpaceMode mode;

  /// Star field density multiplier. Library ~0.80; Now Playing ~0.49; screensaver ~0.54.
  final double starDensity;

  /// Perceptual HDR lift (bright cores / deep vignette) without extra particles.
  final bool hdrBoost;

  const DeepSpaceBackground({
    super.key,
    this.subtle = false,
    this.mode = DeepSpaceMode.background,
    this.starDensity = 1.0,
    this.hdrBoost = true,
  });

  @override
  State<DeepSpaceBackground> createState() => _DeepSpaceBackgroundState();
}

class _DeepSpaceBackgroundState extends State<DeepSpaceBackground>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const int _maxConcurrentComets = 2;
  static const double _cometSpawnRate = 0.10;
  static const double _nebulaCacheLifetimeSeconds = 2.5;

  late Ticker _ticker;
  final ValueNotifier<double> _repaint = ValueNotifier<double>(0.0);
  double _repaintAccumulator = 0.0;
  bool _appActive = true;
  final List<_Star> _stars = [];
  final List<_Star> _farStars = [];
  final List<_ShootingStar> _shootingStars = [];
  final Random _rnd = Random();

  Size? _lastSize;
  double? _lastDpr;
  bool? _lastSubtle;
  double? _lastStarDensity;
  _QualityBudget? _budget;
  ui.Picture? _cachedFarLayer;
  Size? _cachedFarLayerSize;
  ui.Picture? _cachedNebulaLayer;
  Size? _cachedNebulaLayerSize;
  double _lastNebulaCacheAt = -999.0;

  final List<Offset> _nebulaCenters = [];
  final List<Offset> _nebulaVels = [];
  final List<double> _nebulaRotSpeed = [];
  final List<bool> _nebulaEnabled = [];
  final List<Color> _nebulaColors = [];
  final List<_NebulaSpeck> _nebulaSpecks = [];

  Duration _lastElapsed = Duration.zero;
  double _timeSeconds = 0.0;
  int _frame = 0;

  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux);

  Color _randomNebulaColor() {
    final r = _rnd.nextDouble();
    if (r < 0.55) {
      final hue = 175.0 + _rnd.nextDouble() * 85.0;
      return HSVColor.fromAHSV(
        0.20,
        hue,
        0.58 + _rnd.nextDouble() * 0.16,
        0.38 + _rnd.nextDouble() * 0.14,
      ).toColor();
    }
    if (r < 0.80) {
      final hue = 265.0 + _rnd.nextDouble() * 60.0;
      return HSVColor.fromAHSV(
        0.18,
        hue,
        0.58 + _rnd.nextDouble() * 0.18,
        0.34 + _rnd.nextDouble() * 0.16,
      ).toColor();
    }
    final hue = 25.0 + _rnd.nextDouble() * 35.0;
    return HSVColor.fromAHSV(
      0.14,
      hue,
      0.45 + _rnd.nextDouble() * 0.16,
      0.32 + _rnd.nextDouble() * 0.14,
    ).toColor();
  }

  void _initNebulaSpecks(int count) {
    _nebulaSpecks.clear();
    final r = Random(0xBADC0DE);
    for (int i = 0; i < count; i++) {
      final t = r.nextDouble();
      final hue = (180.0 + r.nextDouble() * 160.0) % 360.0;
      _nebulaSpecks.add(
        _NebulaSpeck(
          x: r.nextDouble(),
          y: r.nextDouble(),
          radius: 0.30 + pow(r.nextDouble(), 2.4).toDouble() * 1.10,
          alpha: 0.0015 + t * 0.0035,
          color: HSVColor.fromAHSV(1.0, hue, 0.22 + t * 0.25, 1.0).toColor(),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick)..start();

    if (widget.mode == DeepSpaceMode.background) {
      final budget = _QualityBudget.resolve(
        dpr: 2.0,
        subtle: widget.subtle,
        isDesktop: _isDesktop,
        starDensity: widget.starDensity,
      );
      for (int i = 0; i < budget.nebulaClouds; i++) {
        _nebulaCenters.add(Offset(_rnd.nextDouble(), _rnd.nextDouble()));
        final ang = _rnd.nextDouble() * pi * 2;
        final sp = 0.0015 + _rnd.nextDouble() * 0.0028;
        _nebulaVels.add(Offset(cos(ang) * sp, sin(ang) * sp));
        _nebulaRotSpeed.add((_rnd.nextDouble() - 0.5) * 0.08);
        _nebulaEnabled.add(_rnd.nextDouble() < 0.18);
        _nebulaColors.add(_randomNebulaColor());
      }
      _initNebulaSpecks(budget.nebulaSpecks);
      if (_nebulaEnabled.every((e) => !e) && _nebulaEnabled.isNotEmpty) {
        _nebulaEnabled[_rnd.nextInt(_nebulaEnabled.length)] = true;
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _repaint.dispose();
    _cachedFarLayer = null;
    _cachedNebulaLayer = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (_appActive && !_ticker.isActive) {
      _ticker.start();
    } else if (!_appActive) {
      _ticker.stop();
    }
  }

  Color _randomStarColor() {
    final r = _rnd.nextDouble();
    if (r < 0.62) {
      return HSVColor.fromAHSV(
        1.0,
        190.0 + _rnd.nextDouble() * 110.0,
        0.08 + _rnd.nextDouble() * 0.10,
        1.0,
      ).toColor();
    }
    if (r < 0.78) {
      return HSVColor.fromAHSV(
        1.0,
        40.0 + _rnd.nextDouble() * 35.0,
        0.14 + _rnd.nextDouble() * 0.16,
        1.0,
      ).toColor();
    }
    if (r < 0.90) {
      return HSVColor.fromAHSV(
        1.0,
        195.0 + _rnd.nextDouble() * 35.0,
        0.16 + _rnd.nextDouble() * 0.18,
        1.0,
      ).toColor();
    }
    if (r < 0.97) {
      return HSVColor.fromAHSV(
        1.0,
        10.0 + _rnd.nextDouble() * 22.0,
        0.18 + _rnd.nextDouble() * 0.20,
        1.0,
      ).toColor();
    }
    final hue = _rnd.nextBool()
        ? (150.0 + _rnd.nextDouble() * 25.0)
        : (285.0 + _rnd.nextDouble() * 20.0);
    return HSVColor.fromAHSV(
      1.0,
      hue,
      0.22 + _rnd.nextDouble() * 0.22,
      1.0,
    ).toColor();
  }

  StarLayer _pickStarLayer() {
    final r = _rnd.nextDouble();
    if (r < 0.32) return StarLayer.far;
    if (r < 0.88) return StarLayer.mid;
    return StarLayer.near;
  }

  void _initStars(Size size, double devicePixelRatio) {
    _stars.clear();
    _farStars.clear();
    _cachedFarLayer = null;
    _cachedNebulaLayer = null;
    _lastNebulaCacheAt = -999.0;

    final budget = _QualityBudget.resolve(
      dpr: devicePixelRatio,
      subtle: widget.subtle,
      isDesktop: _isDesktop,
      starDensity: widget.starDensity,
    );
    _budget = budget;

    const baseArea = 1920.0 * 1080.0;
    final area = max(1.0, size.width * size.height);
    final areaFactor = sqrt(area / baseArea).clamp(0.85, 2.25);
    final count = (budget.starCount * areaFactor).round().clamp(
      budget.starCount ~/ 2,
      budget.starCount + 400,
    );

    final dprTighten = (1.0 / max(1.0, devicePixelRatio)).clamp(0.72, 1.0);

    for (int i = 0; i < count; i++) {
      final layer = _pickStarLayer();
      final depth = switch (layer) {
        StarLayer.far => 0.08 + _rnd.nextDouble() * 0.28,
        StarLayer.mid => 0.35 + _rnd.nextDouble() * 0.35,
        StarLayer.near => 0.72 + _rnd.nextDouble() * 0.28,
      };

      final mag = pow(_rnd.nextDouble(), 2.0).toDouble();
      final minStar = switch (layer) {
        StarLayer.far => 0.38,
        StarLayer.mid => 0.62,
        StarLayer.near => 1.10,
      };
      final maxStar = switch (layer) {
        StarLayer.far => 1.05,
        StarLayer.mid => 1.75,
        StarLayer.near => 2.65,
      };

      final brightness = switch (layer) {
        StarLayer.far => 0.38 + _rnd.nextDouble() * 0.38,
        StarLayer.mid => 0.56 + _rnd.nextDouble() * 0.38,
        StarLayer.near => 0.78 + _rnd.nextDouble() * 0.22,
      };

      final star = _Star(
        x: _rnd.nextDouble(),
        y: _rnd.nextDouble(),
        seed: _rnd.nextInt(1 << 31),
        layer: layer,
        size: (minStar + mag * (maxStar - minStar)) *
            (widget.subtle ? 0.96 : 1.0) *
            dprTighten,
        brightness: brightness,
        twinkleSpeed: layer == StarLayer.far
            ? 0.15 + _rnd.nextDouble() * 0.35
            : 0.5 + _rnd.nextDouble() * 3.0,
        twinklePhase: _rnd.nextDouble() * 2 * pi,
        color: _randomStarColor(),
        driftSpeed: switch (layer) {
          StarLayer.far => 0.002 + _rnd.nextDouble() * 0.004,
          StarLayer.mid => 0.006 + _rnd.nextDouble() * 0.010,
          StarLayer.near => 0.014 + _rnd.nextDouble() * 0.020,
        },
        depth: depth,
      );

      if (layer == StarLayer.far) {
        _farStars.add(star);
      } else {
        _stars.add(star);
      }
    }

    _rebuildFarLayerCache(size);
    _lastSize = size;
    _lastDpr = devicePixelRatio;
    _lastSubtle = widget.subtle;
    _lastStarDensity = widget.starDensity;
  }

  bool _needsStarReinit(Size size, double dpr) {
    return _lastSize != size ||
        _lastDpr != dpr ||
        _lastSubtle != widget.subtle ||
        _lastStarDensity != widget.starDensity;
  }

  void _rebuildFarLayerCache(Size size) {
    if (_farStars.isEmpty) {
      _cachedFarLayer = null;
      return;
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint();
    final w = size.width;
    final h = size.height;

    for (final star in _farStars) {
      paint.color = star.color.withValues(alpha: star.brightness * 1.02);
      canvas.drawCircle(
        Offset(star.x * w, star.y * h),
        max(0.45, star.size),
        paint,
      );
    }

    _cachedFarLayer = recorder.endRecording();
    _cachedFarLayerSize = size;
  }

  void _rebuildNebulaCache(Size size, double timeSeconds) {
    if (widget.subtle ||
        widget.mode != DeepSpaceMode.background ||
        _budget == null) {
      _cachedNebulaLayer = null;
      _cachedNebulaLayerSize = null;
      return;
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    _StarFieldPainter.recordStaticLayers(
      canvas: canvas,
      size: size,
      timeSeconds: timeSeconds,
      subtle: widget.subtle,
      hdrBoost: widget.hdrBoost && !widget.subtle,
      budget: _budget,
      nebulaCenters: _nebulaCenters,
      nebulaRotSpeed: _nebulaRotSpeed,
      nebulaEnabled: _nebulaEnabled,
      nebulaColors: _nebulaColors,
      nebulaSpecks: _nebulaSpecks,
      frame: _frame,
    );

    _cachedNebulaLayer = recorder.endRecording();
    _cachedNebulaLayerSize = size;
    _lastNebulaCacheAt = timeSeconds;
  }

  void _maybeRefreshNebulaCache(Size size, double timeSeconds) {
    final stale = timeSeconds - _lastNebulaCacheAt >= _nebulaCacheLifetimeSeconds;
    final sizeChanged = _cachedNebulaLayerSize != size;
    if (_cachedNebulaLayer == null || stale || sizeChanged) {
      _rebuildNebulaCache(size, timeSeconds);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final dpr = MediaQuery.devicePixelRatioOf(context);
        if (_needsStarReinit(size, dpr)) {
          if (widget.mode == DeepSpaceMode.background) {
            _initStars(size, dpr);
          } else {
            _lastSize = size;
            _lastDpr = dpr;
            _lastSubtle = widget.subtle;
            _lastStarDensity = widget.starDensity;
          }
        }

        if (disableAnimations && !_ticker.isTicking) {
          // Static frame when system requests reduced motion.
        } else if (!disableAnimations && !_ticker.isActive) {
          _ticker.start();
        } else if (disableAnimations && _ticker.isActive) {
          _ticker.stop();
        }

        return Container(
          color: widget.mode == DeepSpaceMode.background
              ? const Color(0xFF000000)
              : Colors.transparent,
          child: CustomPaint(
            painter: _StarFieldPainter(
              stars: _stars,
              shootingStars: _shootingStars,
              subtle: widget.subtle,
              hdrBoost: widget.hdrBoost && !widget.subtle,
              budget: _budget,
              nebulaCenters: _nebulaCenters,
              nebulaRotSpeed: _nebulaRotSpeed,
              nebulaEnabled: _nebulaEnabled,
              nebulaColors: _nebulaColors,
              nebulaSpecks: _nebulaSpecks,
              cachedFarLayer: _cachedFarLayer,
              cachedFarLayerSize: _cachedFarLayerSize,
              cachedNebulaLayer: _cachedNebulaLayer,
              cachedNebulaLayerSize: _cachedNebulaLayerSize,
              mode: widget.mode,
              time: _repaint,
              devicePixelRatio: dpr,
              frame: _frame,
            ),
            size: Size.infinite,
          ),
        );
      },
    );
  }

  void _onTick(Duration elapsed) {
    if (!mounted || !_appActive) return;
    final dt = (elapsed - _lastElapsed).inMilliseconds / 1000.0;
    _lastElapsed = elapsed;
    if (!dt.isFinite || dt <= 0) return;

    _timeSeconds += dt;
    if (_timeSeconds > 3600) _timeSeconds -= 3600;

    if (widget.mode == DeepSpaceMode.background) {
      for (final star in _stars) {
        star.update(dt);
      }
      for (final star in _farStars) {
        star.update(dt * 0.35);
      }

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
        if (c.dx < -0.2) {
          c = Offset(c.dx + 1.4, c.dy);
        } else if (c.dx > 1.2) {
          c = Offset(c.dx - 1.4, c.dy);
        }
        if (c.dy < -0.2) {
          c = Offset(c.dx, c.dy + 1.4);
        } else if (c.dy > 1.2) {
          c = Offset(c.dx, c.dy - 1.4);
        }
        _nebulaCenters[i] = c;

        if (i < _nebulaRotSpeed.length) {
          _nebulaRotSpeed[i] += sin(_timeSeconds * 0.02 + i) * 0.00005;
        }
      }
    }

    if (widget.mode == DeepSpaceMode.overlay) {
      if (!widget.subtle &&
          dt.isFinite &&
          dt > 0 &&
          _shootingStars.length < _maxConcurrentComets) {
        if (_rnd.nextDouble() < _cometSpawnRate * dt) {
          _spawnShootingStar();
        }
      }

      _shootingStars.removeWhere((s) => s.isFinished);
      final w = _lastSize?.width ?? 1000.0;
      final h = _lastSize?.height ?? 1000.0;
      for (final s in _shootingStars) {
        s.update(dt, w, h);
      }
    }

    final minInterval = DeepSpaceFrameBudget.minFrameIntervalSeconds(
      mode: widget.mode,
      subtle: widget.subtle,
      hasComets: _shootingStars.isNotEmpty,
      appActive: _appActive,
    );
    _repaintAccumulator += dt;
    if (_repaintAccumulator < minInterval) return;
    _repaintAccumulator = 0.0;
    _frame++;

    if (widget.mode == DeepSpaceMode.background &&
        _lastSize != null &&
        !widget.subtle) {
      _maybeRefreshNebulaCache(_lastSize!, _timeSeconds);
    }

    _repaint.value = _timeSeconds;
  }

  void _spawnShootingStar() {
    final w = _lastSize?.width ?? 1000;
    final h = _lastSize?.height ?? 1000;

    double startX, startY, angle;
    final side = _rnd.nextInt(4);
    switch (side) {
      case 0:
        startX = _rnd.nextDouble() * w;
        startY = -50;
        angle = (45 + _rnd.nextDouble() * 90) * pi / 180.0;
        break;
      case 1:
        startX = w + 50;
        startY = _rnd.nextDouble() * h;
        angle = (135 + _rnd.nextDouble() * 90) * pi / 180.0;
        break;
      case 2:
        startX = _rnd.nextDouble() * w;
        startY = h + 50;
        angle = (225 + _rnd.nextDouble() * 90) * pi / 180.0;
        break;
      default:
        startX = -50;
        startY = _rnd.nextDouble() * h;
        angle = (-45 + _rnd.nextDouble() * 90) * pi / 180.0;
        break;
    }

    const minSpeed = 260.0;
    const maxSpeed = 920.0;
    final t = pow(_rnd.nextDouble(), 2.25).toDouble();
    final baseSpeedPxPerSec = minSpeed + (maxSpeed - minSpeed) * t;

    final colors = [
      const Color(0xFFB3E5FC),
      const Color(0xFFE1F5FE),
      const Color(0xFFFFF9C4),
      const Color(0xFFFFCCBC),
      const Color(0xFFB2DFDB),
      const Color(0xFFC8E6C9),
      Colors.white,
    ];
    final color = colors[_rnd.nextInt(colors.length)];
    final sizeScale = 0.35 + _rnd.nextDouble() * 0.65;
    final speedPxPerSec = baseSpeedPxPerSec * pow(sizeScale, 0.8);
    final lifetimeSeconds = (0.62 + 0.32 * sizeScale).clamp(0.55, 1.25);
    final seed = _rnd.nextInt(1 << 31);
    final sunAngle = -pi / 2 + (_rnd.nextDouble() - 0.5) * 0.8;
    final style = _rnd.nextDouble() < 0.08
        ? _CometStyle.bright
        : _CometStyle.subtle;

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
        tailCurveAmp: (_rnd.nextDouble() - 0.5) * 0.18,
        tailWidthJitter: 0.85 + _rnd.nextDouble() * 0.35,
        coreWidthJitter: 0.85 + _rnd.nextDouble() * 0.30,
        headStretch: 0.9 + _rnd.nextDouble() * 0.35,
        headSkew: (_rnd.nextDouble() - 0.5) * 0.25,
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
  final double ionTailMul;

  const _CometStyle._({
    required this.tailLengthMul,
    required this.tailWidthMul,
    required this.coreWidthMul,
    required this.headMul,
    required this.alphaMul,
    required this.debrisCount,
    required this.ionTailMul,
  });

  static const subtle = _CometStyle._(
    tailLengthMul: 0.26,
    tailWidthMul: 0.58,
    coreWidthMul: 0.68,
    headMul: 0.65,
    alphaMul: 0.58,
    debrisCount: 4,
    ionTailMul: 0.75,
  );

  static const bright = _CometStyle._(
    tailLengthMul: 0.42,
    tailWidthMul: 0.82,
    coreWidthMul: 0.92,
    headMul: 1.05,
    alphaMul: 0.88,
    debrisCount: 8,
    ionTailMul: 1.15,
  );
}

class _Star {
  double x, y;
  final int seed;
  final StarLayer layer;
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
    required this.layer,
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

  double opacityAt(double timeSeconds) {
    if (layer == StarLayer.far) {
      return brightness.clamp(0.18, 0.78);
    }

    final twinkles = layer == StarLayer.near || brightness > 0.82;
    if (!twinkles) {
      return brightness.clamp(0.12, 0.88);
    }

    final t = timeSeconds * twinkleSpeed + twinklePhase;
    final baseWave = sin(t) + sin(t * 2.7) * 0.5;
    final n1 = _hash11(timeSeconds * 0.65 + seed * 0.0000013);
    final n2 = _hash11(timeSeconds * 1.25 + seed * 0.0000007);
    final noise = (n1 - 0.5) * 1.15 + (n2 - 0.5) * 0.55;
    final wave = baseWave + noise;
    final twinkleAmp = 0.18 * (0.35 + depth * 0.65) * (layer == StarLayer.near ? 1.35 : 1.0);
    return (brightness + wave * twinkleAmp).clamp(0.05, 1.0);
  }

  void update(double dt) {
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
    required this.tailCurveAmp,
    required this.tailWidthJitter,
    required this.coreWidthJitter,
    required this.headStretch,
    required this.headSkew,
  }) : debris = _buildDebris(debrisSeed, style.debrisCount);

  static List<_DebrisSpec> _buildDebris(int seed, int count) {
    final r = Random(seed);
    return List.generate(count, (_) {
      return _DebrisSpec(
        distFactor: r.nextDouble() * 0.32,
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
    progress = (_elapsedSeconds / lifetimeSeconds).clamp(0.0, 1.0);

    x += cos(angle) * (speedPxPerSec * dt) / w;
    y += sin(angle) * (speedPxPerSec * dt) / h;

    if (x < -0.25 || x > 1.25 || y < -0.25 || y > 1.25) {
      isFinished = true;
    }
  }
}

class _StarFieldPainter extends CustomPainter {
  final List<_Star> stars;
  final List<_ShootingStar> shootingStars;
  final bool subtle;
  final bool hdrBoost;
  final _QualityBudget? budget;
  final List<Offset> nebulaCenters;
  final List<double> nebulaRotSpeed;
  final List<bool> nebulaEnabled;
  final List<Color> nebulaColors;
  final List<_NebulaSpeck> nebulaSpecks;
  final ui.Picture? cachedFarLayer;
  final Size? cachedFarLayerSize;
  final ui.Picture? cachedNebulaLayer;
  final Size? cachedNebulaLayerSize;
  final DeepSpaceMode mode;
  final ValueNotifier<double> time;
  final double devicePixelRatio;
  final int frame;

  _StarFieldPainter({
    required this.stars,
    required this.shootingStars,
    required this.subtle,
    this.hdrBoost = false,
    required this.budget,
    required this.nebulaCenters,
    required this.nebulaRotSpeed,
    required this.nebulaEnabled,
    required this.nebulaColors,
    required this.nebulaSpecks,
    required this.cachedFarLayer,
    required this.cachedFarLayerSize,
    this.cachedNebulaLayer,
    this.cachedNebulaLayerSize,
    required this.mode,
    required this.time,
    required this.devicePixelRatio,
    required this.frame,
  }) : super(repaint: time);

  static void recordStaticLayers({
    required Canvas canvas,
    required Size size,
    required double timeSeconds,
    required bool subtle,
    required bool hdrBoost,
    required _QualityBudget? budget,
    required List<Offset> nebulaCenters,
    required List<double> nebulaRotSpeed,
    required List<bool> nebulaEnabled,
    required List<Color> nebulaColors,
    required List<_NebulaSpeck> nebulaSpecks,
    required int frame,
  }) {
    final painter = _StarFieldPainter(
      stars: const [],
      shootingStars: const [],
      subtle: subtle,
      hdrBoost: hdrBoost,
      budget: budget,
      nebulaCenters: nebulaCenters,
      nebulaRotSpeed: nebulaRotSpeed,
      nebulaEnabled: nebulaEnabled,
      nebulaColors: nebulaColors,
      nebulaSpecks: nebulaSpecks,
      cachedFarLayer: null,
      cachedFarLayerSize: null,
      mode: DeepSpaceMode.background,
      time: ValueNotifier<double>(timeSeconds),
      devicePixelRatio: 1.0,
      frame: frame,
    );
    painter._paintNebulaClouds(canvas, size, timeSeconds);
    painter._paintDeepSpaceVignette(canvas, size);
    if (hdrBoost) {
      painter._paintHdrGradePass(canvas, size);
    }
  }

  double _hash01(double v) {
    final x = sin(v * 12.9898) * 43758.5453;
    return x - x.floorToDouble();
  }

  void _drawSoftSpikes(
    Canvas canvas,
    Offset pos,
    double radius,
    Color color,
    double alpha,
  ) {
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final spikeLen = radius * 2.1;
    final spikeW = max(0.35, radius * 0.22);

    for (int i = 0; i < 2; i++) {
      final ang = i * pi / 2;
      paint.shader = ui.Gradient.linear(
        pos,
        pos + Offset(cos(ang) * spikeLen, sin(ang) * spikeLen),
        [
          color.withValues(alpha: alpha * 0.75),
          color.withValues(alpha: 0.0),
        ],
        const [0.0, 1.0],
      );
      paint.strokeWidth = spikeW;
      canvas.drawLine(
        pos + Offset(cos(ang) * radius * 0.5, sin(ang) * radius * 0.5),
        pos + Offset(cos(ang) * spikeLen, sin(ang) * spikeLen),
        paint,
      );
    }
    paint.shader = null;
  }

  void _paintNebulaClouds(Canvas canvas, Size size, double timeSeconds) {
    final b = budget;
    if (b == null || subtle) return;

    final w = size.width;
    final h = size.height;
    final paint = Paint();
    final nebulaAlphaMul = b.nebulaAlpha * (subtle ? 0.35 : 0.55);

    if (b.noiseField && !subtle && frame % 4 == 0) {
      for (int i = 0; i < nebulaCenters.length; i++) {
        if (i < nebulaEnabled.length && !nebulaEnabled[i]) continue;
        DeepSpaceNoise.paintNebulaField(
          canvas: canvas,
          size: size,
          timeSeconds: timeSeconds + i * 1.7,
          tint: nebulaColors[i],
          alphaMul: nebulaAlphaMul * 0.12,
          gridCols: b.noiseGridCols,
          gridRows: b.noiseGridRows,
          panX: nebulaCenters[i].dx * 2.0,
          panY: nebulaCenters[i].dy * 2.0,
        );
      }
    }

    for (int i = 0; i < nebulaCenters.length; i++) {
      if (i < nebulaEnabled.length && !nebulaEnabled[i]) continue;
      final c = nebulaCenters[i];
      final rot = i < nebulaRotSpeed.length ? nebulaRotSpeed[i] * timeSeconds : 0.0;
      final drift = Offset(
        sin(timeSeconds * 0.06 + i * 1.7) * 0.06,
        cos(timeSeconds * 0.05 + i * 1.3) * 0.045,
      );
      final baseCenter = Offset((c.dx + drift.dx) * w, (c.dy + drift.dy) * h);
      final baseRadius = min(w, h) * (subtle ? 0.42 : 0.52);
      paint.blendMode = BlendMode.screen;

      final blobCount = b.nebulaBlobCount;
      for (int j = 0; j < blobCount; j++) {
        final phase = i * 3.11 + j * 1.87;
        final wobble = 0.10 + 0.05 * sin(timeSeconds * 0.08 + phase);
        final rotX = cos(rot + phase) * 0.08 * w;
        final rotY = sin(rot + phase) * 0.07 * h;
        final blobOffset = Offset(
          (sin(timeSeconds * 0.11 + phase) * 0.11 +
                  sin(timeSeconds * 0.03 + phase * 2.3) * 0.05) *
              w +
              rotX,
          (cos(timeSeconds * 0.10 + phase) * 0.09 +
                  cos(timeSeconds * 0.028 + phase * 2.1) * 0.05) *
              h +
              rotY,
        );
        final center = baseCenter + blobOffset;
        final radius = baseRadius * (0.55 + j * 0.12) * (1.0 + wobble);

        paint.shader = ui.Gradient.radial(
          center,
          radius,
          [
            nebulaColors[i].withValues(alpha: (0.045 - j * 0.008) * nebulaAlphaMul),
            nebulaColors[i].withValues(alpha: (0.016 - j * 0.004) * nebulaAlphaMul),
            Colors.transparent,
          ],
          const [0.0, 0.55, 1.0],
        );
        canvas.drawCircle(center, radius, paint);
      }

      if (b.filaments && !subtle) {
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
                alpha: (0.045 + 0.028 * _hash01(seed + 1.4)) * nebulaAlphaMul,
              ),
              nebulaColors[i].withValues(
                alpha: (0.018 + 0.018 * _hash01(seed + 6.7)) * nebulaAlphaMul,
              ),
              Colors.transparent,
            ],
            const [0.0, 0.55, 1.0],
          );
          canvas.drawCircle(center2, rr, paint);
        }
      }

      final coreCenter = baseCenter +
          Offset(
            sin(timeSeconds * 0.12 + i) * 12,
            cos(timeSeconds * 0.10 + i) * 10,
          );
      final coreRadius = baseRadius * (0.30 + 0.03 * sin(timeSeconds * 0.16 + i));
      paint.shader = ui.Gradient.radial(
        coreCenter,
        coreRadius,
        [
          Colors.white.withValues(
            alpha: (hdrBoost ? 0.026 : 0.018) * nebulaAlphaMul,
          ),
          nebulaColors[i].withValues(
            alpha: (hdrBoost ? 0.046 : 0.038) * nebulaAlphaMul,
          ),
          Colors.transparent,
        ],
        const [0.0, 0.62, 1.0],
      );
      paint.blendMode = BlendMode.plus;
      canvas.drawCircle(coreCenter, coreRadius, paint);

      if (b.dustLanes && !subtle) {
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
  }

  void _paintHdrGradePass(Canvas canvas, Size size) {
    final paint = Paint()
      ..blendMode = BlendMode.screen
      ..shader = ui.Gradient.radial(
        Offset(size.width * 0.5, size.height * 0.38),
        size.shortestSide * 0.55,
        [
          Colors.white.withValues(alpha: 0.028),
          Colors.transparent,
        ],
        const [0.0, 1.0],
      );
    canvas.drawRect(Offset.zero & size, paint);
    paint.shader = null;
    paint.blendMode = BlendMode.srcOver;
  }

  void _paintDeepSpaceVignette(Canvas canvas, Size size) {
    final paint = Paint();
    final w = size.width;
    final h = size.height;
    final center = Offset(w * 0.5, h * 0.42);
    final edgeAlpha = hdrBoost
        ? (subtle ? 0.42 : 0.58)
        : (subtle ? 0.38 : 0.52);

    paint.shader = ui.Gradient.radial(
      center,
      size.shortestSide * 0.92,
      [
        Colors.transparent,
        Colors.black.withValues(alpha: edgeAlpha),
      ],
      const [0.42, 1.0],
    );
    paint.blendMode = BlendMode.multiply;
    canvas.drawRect(Offset.zero & size, paint);

    paint.shader = ui.Gradient.linear(
      Offset(0, 0),
      Offset(0, h * 0.22),
      [
        Colors.black.withValues(alpha: subtle ? 0.55 : 0.72),
        Colors.transparent,
      ],
      const [0.0, 1.0],
    );
    canvas.drawRect(Offset.zero & size, paint);

    paint.shader = ui.Gradient.linear(
      Offset(0, h),
      Offset(0, h * 0.78),
      [
        Colors.black.withValues(alpha: subtle ? 0.65 : 0.82),
        Colors.transparent,
      ],
      const [0.0, 1.0],
    );
    canvas.drawRect(Offset.zero & size, paint);
    paint.shader = null;
    paint.blendMode = BlendMode.srcOver;
  }

  void _paintStars(Canvas canvas, Size size, double timeSeconds) {
    final b = budget;
    final w = size.width;
    final h = size.height;
    final paint = Paint();
    final alphaMul = (b?.starAlpha ?? 0.85) * (subtle ? 0.96 : 1.0);
    final floor = b?.subtleStarFloor ?? 0;
    final drawCount = subtle ? max(floor, stars.length) : stars.length;

    for (int i = 0; i < drawCount && i < stars.length; i++) {
      final star = stars[i];
      final op = star.opacityAt(timeSeconds);
      final alpha = op * alphaMul;
      final pos = Offset(star.x * w, star.y * h);

      var starColor = star.color;
      var starRadius = star.size;
      if (star.layer == StarLayer.near) {
        final sparkle = ((op - 0.60) / 0.40).clamp(0.0, 1.0);
        starColor = Color.lerp(star.color, Colors.white, sparkle * 0.24)!;
        starRadius = star.size * (1.0 + 0.14 * sparkle);
      }

      final bloomThreshold = hdrBoost ? 0.72 : 0.78;
      final bloomAlpha = hdrBoost ? 0.17 : 0.14;
      if (!subtle && starRadius > 1.5 && op > bloomThreshold) {
        paint.color = starColor.withValues(alpha: alpha * bloomAlpha);
        canvas.drawCircle(pos, starRadius * (hdrBoost ? 2.35 : 2.2), paint);
      }

      final spikeThreshold = hdrBoost ? 0.66 : 0.72;
      if (!subtle &&
          star.layer == StarLayer.near &&
          starRadius > 1.1 &&
          op > spikeThreshold) {
        _drawSoftSpikes(canvas, pos, starRadius, starColor, alpha * 0.55);
      }

      paint.color = starColor.withValues(alpha: alpha);
      canvas.drawCircle(pos, starRadius, paint);
    }
  }

  void _paintComet(Canvas canvas, _ShootingStar s, Size size, double timeSeconds) {
    final w = size.width;
    final h = size.height;
    final paint = Paint();
    final start = Offset(s.x * w, s.y * h);
    final speedFactor = (s.speedPxPerSec / 800.0).clamp(0.55, 1.45);
    final dustTailLen = min(w, h) * 0.30 * (0.75 + 0.18 * s.sizeScale) * speedFactor * s.style.tailLengthMul;
    final ionTailLen = dustTailLen * 0.72 * s.style.ionTailMul;
    final alpha = s.style.alphaMul.clamp(0.0, 1.0);

    Offset pointOnCurvedTail(double t, double angle, double curveAmp, double length) {
      final base = start - Offset(cos(angle) * length * t, sin(angle) * length * t);
      final lateral = sin(t * pi) * curveAmp * length * 0.22;
      return base +
          Offset(
            cos(angle + pi / 2 + s.headSkew) * lateral,
            sin(angle + pi / 2 + s.headSkew) * lateral,
          );
    }

    void drawTaperedTail({
      required double angle,
      required double length,
      required double curveAmp,
      required List<Color> colors,
      required double baseWidth,
      required int segments,
    }) {
      final tailPaint = Paint()
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      for (int i = 0; i < segments; i++) {
        final t0 = i / segments;
        final t1 = (i + 1) / segments;
        final p0 = pointOnCurvedTail(t0, angle, curveAmp, length);
        final p1 = pointOnCurvedTail(t1, angle, curveAmp, length);
        final tm = (t0 + t1) * 0.5;
        final taper = 0.22 + 0.78 * pow(1.0 - tm, 0.85).toDouble();

        tailPaint.shader = ui.Gradient.linear(
          p0,
          p1,
          colors,
          colors.length == 2
              ? const [0.0, 1.0]
              : const [0.0, 0.55, 1.0],
        );
        tailPaint.strokeWidth = baseWidth * taper;
        canvas.drawLine(p0, p1, tailPaint);
      }
      tailPaint.shader = null;
    }

    // Dust tail along velocity.
    drawTaperedTail(
      angle: s.angle,
      length: dustTailLen,
      curveAmp: s.tailCurveAmp,
      colors: [
        s.color.withValues(alpha: alpha * 0.34),
        s.color.withValues(alpha: alpha * 0.06),
        Colors.transparent,
      ],
      baseWidth: 3.2 * s.sizeScale * s.style.tailWidthMul * s.tailWidthJitter,
      segments: 18,
    );

    // Hot core in dust tail.
    drawTaperedTail(
      angle: s.angle,
      length: dustTailLen * 0.82,
      curveAmp: s.tailCurveAmp * 0.6,
      colors: [
        Colors.white.withValues(alpha: alpha * 0.88),
        s.color.withValues(alpha: alpha * 0.42),
        Colors.transparent,
      ],
      baseWidth: 1.1 * s.sizeScale * s.style.coreWidthMul * s.coreWidthJitter,
      segments: 16,
    );

    // Ion tail points away from the sun.
    final ionAngle = s.sunAngle + pi;
    final ionColor = Color.lerp(const Color(0xFF80D8FF), Colors.white, 0.45)!;
    drawTaperedTail(
      angle: ionAngle,
      length: ionTailLen,
      curveAmp: s.tailCurveAmp * 0.25,
      colors: [
        ionColor.withValues(alpha: alpha * 0.42),
        ionColor.withValues(alpha: alpha * 0.08),
        Colors.transparent,
      ],
      baseWidth: 1.6 * s.sizeScale * s.style.coreWidthMul,
      segments: 14,
    );

    // Layered coma (no per-frame blur).
    final headBase = 8.0 * s.sizeScale * s.style.headMul * s.headStretch;
    for (int ring = 3; ring >= 1; ring--) {
      final t = ring / 3.0;
      paint
        ..shader = null
        ..color = s.color.withValues(alpha: alpha * (0.10 + 0.12 * (1 - t)));
      canvas.drawCircle(start, headBase * (0.45 + t * 0.75), paint);
    }
    paint.color = Colors.white.withValues(alpha: alpha * 0.95);
    canvas.drawCircle(start, max(1.0, 1.4 * s.sizeScale), paint);

    for (final d in s.debris) {
      final dist = d.distFactor * dustTailLen;
      final offset = d.lateralFactor * s.sizeScale;
      final eject = (0.6 + 1.8 * s.progress) *
          (0.4 + 0.6 * _hash01(d.distFactor * 31.7 + timeSeconds * 1.8)) *
          s.sizeScale;
      final debrisPos = start -
          Offset(cos(s.angle) * dist, sin(s.angle) * dist) +
          Offset(
            cos(s.angle + pi / 2) * (offset + eject),
            sin(s.angle + pi / 2) * (offset + eject * 0.6),
          );
      paint.color = s.color.withValues(
        alpha: alpha * 0.35 * d.alpha * (1.0 - s.progress * 0.4),
      );
      canvas.drawCircle(debrisPos, d.radius, paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final timeSeconds = time.value;

    if (mode == DeepSpaceMode.background) {
      canvas.drawColor(const Color(0xFF000000), BlendMode.src);

      if (cachedFarLayer != null && cachedFarLayerSize != null) {
        final drift = Offset(
          sin(timeSeconds * 0.004) * 8,
          cos(timeSeconds * 0.0035) * 6,
        );
        canvas.save();
        canvas.translate(drift.dx, drift.dy);
        canvas.drawPicture(cachedFarLayer!);
        canvas.restore();
      }

      if (cachedNebulaLayer != null &&
          cachedNebulaLayerSize == size &&
          !subtle) {
        canvas.drawPicture(cachedNebulaLayer!);
      } else {
        _paintNebulaClouds(canvas, size, timeSeconds);
        _paintDeepSpaceVignette(canvas, size);
        if (hdrBoost) {
          _paintHdrGradePass(canvas, size);
        }
      }

      _paintStars(canvas, size, timeSeconds);
      return;
    }

    if (mode == DeepSpaceMode.overlay) {
      if (subtle) return;
      for (final s in shootingStars) {
        _paintComet(canvas, s, size, timeSeconds);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StarFieldPainter oldDelegate) {
    return oldDelegate.subtle != subtle ||
        oldDelegate.mode != mode ||
        oldDelegate.devicePixelRatio != devicePixelRatio ||
        oldDelegate.budget != budget ||
        oldDelegate.stars != stars ||
        oldDelegate.shootingStars != shootingStars ||
        oldDelegate.nebulaCenters != nebulaCenters ||
        oldDelegate.nebulaColors != nebulaColors ||
        oldDelegate.nebulaSpecks != nebulaSpecks ||
        oldDelegate.nebulaEnabled != nebulaEnabled ||
        oldDelegate.cachedFarLayer != cachedFarLayer ||
        oldDelegate.cachedNebulaLayer != cachedNebulaLayer ||
        oldDelegate.hdrBoost != hdrBoost;
  }
}