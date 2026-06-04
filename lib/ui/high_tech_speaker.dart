import 'dart:math';
import 'package:flutter/material.dart';
import '../services/settings_service.dart';

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
    this.accentColor = const Color(0xFFFF9F40), // default Jedi Survivor Coruscant Paint accent
  });

  @override
  State<HighTechSpeaker> createState() => _HighTechSpeakerState();
}

class _HighTechSpeakerState extends State<HighTechSpeaker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  double _lowBand = 0.0;
  double _highBand = 0.0;
  Duration _lastElapsed = Duration.zero;

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
    // One-pole low-pass with separate attack/release constants.
    final tau = target >= current ? tauAttack : tauRelease;
    final a = 1.0 - exp(-dtSeconds / max(1e-6, tau));
    return current + (target - current) * a;
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(HighTechSpeaker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isPlaying && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final posSeconds = (widget.position?.inMicroseconds ?? 0) / 1e6;
        // Use monotonic time (no visible looping) while still allowing the
        // track position to influence phase when playing.
        final animSeconds =
            ((_controller.lastElapsedDuration?.inMicroseconds ?? 0) / 1e6);
        // When paused/stopped, visualizer must freeze.
        final t = widget.isPlaying ? (posSeconds + animSeconds) : posSeconds;

        final energy =
            (widget.isPlaying ? 1.0 : 0.0) * widget.volume.clamp(0.0, 1.0);

        // Super-smooth bands with attack/release behavior.
        if (widget.isPlaying) {
          final elapsed = _controller.lastElapsedDuration ?? Duration.zero;
          final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
          final dtSeconds = dt.isFinite && dt > 0 ? dt : (1 / 60.0);
          _lastElapsed = elapsed;

          final beatHz = _beatHz();

          // Target bands: low = sub/beat, high = sparkle/transients.
          // These are *not* true FFT; they are a lightweight proxy that
          // looks reactive without heavy DSP.
          final lowTarget =
              pow(0.5 + 0.5 * sin(2 * pi * beatHz * t), 1.35).toDouble();
          final highTarget = (0.5 +
                  0.5 *
                      sin(
                        2 * pi * (beatHz * 6.0) * t +
                            sin(t * 1.73) * 1.20 +
                            sin(t * 0.23) * 0.90,
                      ))
              .clamp(0.0, 1.0);

          _lowBand = _smoothBand(
            _lowBand,
            lowTarget,
            dtSeconds,
            tauAttack: 0.10,
            tauRelease: 0.22,
          );
          _highBand = _smoothBand(
            _highBand,
            highTarget,
            dtSeconds,
            tauAttack: 0.06,
            tauRelease: 0.16,
          );
        }

        final lowBand = widget.isPlaying ? _lowBand : 0.0;
        final highBand = widget.isPlaying ? _highBand : 0.0;

        return SizedBox(
          height: 120,
          width: double.infinity,
          child: CustomPaint(
            painter: _HypnoSpeakerPainter(
              t: t,
              isPlaying: widget.isPlaying,
              energy: energy,
              lowBand: lowBand,
              highBand: highBand,
              accentColor: widget.accentColor,
            ),
          ),
        );
      },
    );
  }
}

class _HypnoSpeakerPainter extends CustomPainter {
  final double t;
  final bool isPlaying;
  final double energy;
  final double lowBand;
  final double highBand;
  final Color accentColor;

  double get _intensityMul {
    final isNeon = SettingsService.instance.themeMode == SettingsService.themeNeon;
    return isNeon ? 2.1 : 1.45;
  }

  _HypnoSpeakerPainter({
    required this.t,
    required this.isPlaying,
    required this.energy,
    required this.lowBand,
    required this.highBand,
    required this.accentColor,
  });

  double _hash(double x) {
    final s = sin(x * 12.9898) * 43758.5453;
    return s - s.floorToDouble();
  }

  double _smoothstep(double edge0, double edge1, double x) {
    final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  Path _catmullRom(List<Offset> pts) {
    if (pts.length < 2) return Path();
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 0; i < pts.length - 1; i++) {
      final p0 = pts[i == 0 ? 0 : i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = pts[(i + 2) < pts.length ? (i + 2) : (pts.length - 1)];

      final c1 = p1 + (p2 - p0) / 6.0;
      final c2 = p2 - (p3 - p1) / 6.0;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final r = min(w, h) * 0.5;
    final pad = r * 0.10;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        (w - (2 * r)) / 2,
        (h - (2 * r)) / 2,
        2 * r,
        2 * r,
      ).deflate(pad),
      Radius.circular(r * 0.22),
    );

    final e = (0.10 + 0.90 * energy).clamp(0.0, 1.0);

    // Background panel
    canvas.drawRRect(rect, Paint()..color = const Color(0xFF07090C));

    // High-tech rim: outer bevel + neon edge + inner bevel.
    final rimOuter = rect;
    final rimInner = rect.deflate(r * 0.10);
    final rimNeon = rect.deflate(r * 0.055);

    // Premium depth: subtle outer shadow.
    canvas.drawRRect(
      rimOuter,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.085
        ..color = Colors.black.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.22),
    );

    // Outer bevel / metal ring (sweep highlight)
    final metalRect = rimOuter.outerRect;
    canvas.drawRRect(
      rimOuter,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.070
        ..shader = const SweepGradient(
          center: Alignment.center,
          startAngle: 0,
          endAngle: 2 * pi,
          colors: [
            Color(0xFF0E1014),
            Color(0xFF2D3540),
            Color(0xFF10141B),
            Color(0xFF3A4656),
            Color(0xFF0E1014),
          ],
          stops: [0.00, 0.22, 0.50, 0.78, 1.00],
        ).createShader(metalRect),
    );

    // Specular sweep (premium gloss) - intensity reacts more to highs.
    final specA = (0.08 + 0.22 * e * (0.35 + 0.65 * highBand)).clamp(0.0, 0.30);
    canvas.drawRRect(
      rimOuter.deflate(r * 0.014),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, r * 0.012)
        ..shader = SweepGradient(
          center: Alignment.center,
          startAngle: -pi / 2,
          endAngle: 3 * pi / 2,
          colors: [
            Colors.transparent,
            Colors.white.withValues(alpha: specA),
            Colors.transparent,
          ],
          stops: const [0.18, 0.25, 0.33],
          transform: GradientRotation(t * 0.08),
        ).createShader(metalRect)
        ..blendMode = BlendMode.plus,
    );

    // Neon edge (glow-in-the-dark feel)
    final neonAlpha = (0.22 + 0.48 * e * (0.55 + 0.45 * lowBand)).clamp(
      0.0,
      1.0,
    );

    // Outer halo (wide, soft) - feels like charged phosphor.
    final intensity = _intensityMul;
    canvas.drawRRect(
      rimNeon,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.060
        ..color = accentColor.withValues(
          alpha: (neonAlpha * 0.35 * intensity).clamp(0.0, 0.75),
        )
        ..blendMode = BlendMode.plus
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.28),
    );
    canvas.drawRRect(
      rimNeon,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.030
        ..color = accentColor.withValues(alpha: (neonAlpha * intensity).clamp(0.0, 1.0))
        ..blendMode = BlendMode.plus
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.11),
    );
    canvas.drawRRect(
      rimNeon,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, r * 0.010)
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            Colors.white.withValues(alpha: (neonAlpha * 0.55).clamp(0.0, 0.55)),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(rimNeon.outerRect)
        ..blendMode = BlendMode.plus,
    );

    // Inner bevel
    canvas.drawRRect(
      rimInner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.030
        ..color = const Color(0xFF1E232B).withValues(alpha: 0.95),
    );

    canvas.save();
    canvas.clipRRect(rect);

    final inner = rect.deflate(r * 0.16);
    final center = Offset(
      rect.left + rect.width / 2,
      rect.top + rect.height / 2,
    );
    final slow = t * 2 * pi * 0.20;
    final fast = t * 2 * pi * 0.75;

    // Premium interior vignette (adds depth).
    final vignetteRect = inner.outerRect;
    canvas.drawRect(
      vignetteRect,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
          stops: const [0.55, 1.0],
        ).createShader(vignetteRect),
    );

    // Hypnotic "ribbons" (no rings/arcs/sweep)
    final ribbonArea = Rect.fromLTWH(
      inner.left,
      inner.top + inner.height * 0.12,
      inner.width,
      inner.height * 0.76,
    );
    final ribbons = isPlaying ? 5 : 3;
    for (int i = 0; i < ribbons; i++) {
      final fi = i.toDouble();
      final yBase =
          ribbonArea.top + ribbonArea.height * (0.18 + 0.64 * (fi / (ribbons)));
      final amp =
          ribbonArea.height *
          (0.05 + 0.13 * e * (0.55 + 0.45 * lowBand)) *
          (1.0 - fi * 0.10);
      final phase = slow + fi * 1.7;
      final freq = 1.2 + fi * 0.35;
      final wobble = 0.55 + 0.45 * sin((fast * 0.85) + fi + highBand * 1.25);

      // Build smooth spline points.
      const steps = 92;
      final pts = <Offset>[];
      for (int s = 0; s <= steps; s++) {
        final nx = (s / steps);
        final x = ribbonArea.left + ribbonArea.width * nx;
        final env = 0.22 + 0.78 * sin(pi * nx);

        // Drift & shimmer; pauses at 0 when not playing.
        final drift =
            sin((t * 0.07) + fi * 0.9) * ribbonArea.height * 0.012 * e;
        final y =
            yBase +
            drift +
            sin(phase + nx * 2 * pi * freq) * amp * env +
            sin(phase * 0.71 + nx * 2 * pi * (freq * 0.53)) * amp * 0.38 * env;

        pts.add(Offset(x, y));
      }
      final path = _catmullRom(pts);

      final alpha = ((isPlaying ? 0.88 : 0.0) *
              (0.65 + 0.35 * wobble) *
               (0.55 + 0.45 * e) *
               _intensityMul)
          .clamp(0.0, 1.0);
      final strokeW = ribbonArea.height * (0.10 - fi * 0.010);
      final bounds = path.getBounds();
      final shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          accentColor.withValues(alpha: alpha.clamp(0.0, 1.0)),
          Colors.white.withValues(alpha: (alpha * 0.16).clamp(0.0, 0.34)),
          accentColor.withValues(alpha: (alpha * 0.70).clamp(0.0, 1.0)),
          Colors.transparent,
        ],
        stops: const [0.0, 0.26, 0.52, 0.80, 1.0],
      ).createShader(bounds);

      // Glow pass
      canvas.drawPath(
        path,
        Paint()
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = strokeW
          ..shader = shader
          ..blendMode = BlendMode.plus
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            r * (0.165 + 0.070 * highBand) * _intensityMul,
          ),
      );
      // Highlight pass (thin and crisp)
      canvas.drawPath(
        path,
        Paint()
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = max(1.0, strokeW * 0.18)
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.transparent,
              Colors.white.withValues(alpha: (alpha * 0.811).clamp(0.0, 0.97)),
              Colors.transparent,
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(bounds)
          ..blendMode = BlendMode.plus,
      );
    }

    // Diaphragm "breath" in the center
    final breath = isPlaying ? lowBand : 0.0;
    final diaphragmR = r * (0.18 + 0.040 * breath * e);
    final glowA = (isPlaying ? 0.80 : 0.0) * (0.55 + 0.45 * breath) * e * 0.98;
    final diaphragmRect = Rect.fromCircle(center: center, radius: diaphragmR);
    canvas.drawCircle(
      center,
      diaphragmR * 1.55,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accentColor.withValues(alpha: glowA.clamp(0.0, 0.44)),
            Colors.transparent,
          ],
          stops: const [0.0, 1.0],
        ).createShader(
          Rect.fromCircle(center: center, radius: diaphragmR * 1.6),
        )
        ..blendMode = BlendMode.plus,
    );
    canvas.drawOval(
      diaphragmRect,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF0B0F14), Color(0xFF050609)],
          stops: [0.0, 1.0],
        ).createShader(diaphragmRect),
    );
    canvas.drawOval(
      diaphragmRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.04
        ..color = const Color(0xFF1E232B),
    );

    // Subtle shimmer grain (deterministic)
    final grainPaint = Paint()..blendMode = BlendMode.plus;
    for (int i = 0; i < 28; i++) {
      final hx = _hash(i + 13.0);
      final hy = _hash(i + 71.0);
      final p = Offset(
        inner.left + hx * inner.width,
        inner.top + hy * inner.height,
      );
      final tw = 0.5 + 0.5 * sin(fast + i * 0.7);
      final a =
          (isPlaying ? 0.18 : 0.0) *
          _smoothstep(0.0, 1.0, tw) *
          e *
          (0.55 + 0.45 * highBand);
      grainPaint.color = Colors.white.withValues(alpha: a.clamp(0.0, 0.125));
      canvas.drawCircle(p, r * (0.010 + 0.010 * _hash(i + 99.0)), grainPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HypnoSpeakerPainter oldDelegate) {
    return t != oldDelegate.t ||
        isPlaying != oldDelegate.isPlaying ||
        energy != oldDelegate.energy ||
        lowBand != oldDelegate.lowBand ||
        highBand != oldDelegate.highBand ||
        accentColor != oldDelegate.accentColor;
  }
}
