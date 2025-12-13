import 'dart:math';
import 'package:flutter/material.dart';

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
    this.accentColor = const Color(0xFFFFB300),
  });

  @override
  State<HighTechSpeaker> createState() => _HighTechSpeakerState();
}

class _HighTechSpeakerState extends State<HighTechSpeaker>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void didUpdateWidget(HighTechSpeaker oldWidget) {
    super.didUpdateWidget(oldWidget);
    // No beat anchoring: visualizer is time-driven, not BPM-driven.
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
        final t = (widget.isPlaying ? posSeconds : 0.0) + animSeconds;
        final idle = !widget.isPlaying;
        final energy = (idle ? 0.35 : 1.0) * widget.volume.clamp(0.0, 1.0);

        return CustomPaint(
          size: const Size(double.infinity, 120),
          painter: _HypnoSpeakerPainter(
            t: t,
            isPlaying: widget.isPlaying,
            energy: energy,
            accentColor: widget.accentColor,
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
  final Color accentColor;

  static const double _kRibbonIntensityMul = 1.45;

  _HypnoSpeakerPainter({
    required this.t,
    required this.isPlaying,
    required this.energy,
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

    // Background panel
    canvas.drawRRect(rect, Paint()..color = const Color(0xFF07090C));
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.06
        ..color = const Color(0xFF1E232B),
    );

    canvas.save();
    canvas.clipRRect(rect);

    final inner = rect.deflate(r * 0.16);
    final center = Offset(
      rect.left + rect.width / 2,
      rect.top + rect.height / 2,
    );
    final e = (0.12 + 0.88 * energy).clamp(0.0, 1.0);
    final slow = t * 2 * pi * 0.20;
    final fast = t * 2 * pi * 0.75;

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
      final amp = ribbonArea.height * (0.06 + 0.12 * e) * (1.0 - fi * 0.10);
      final phase = slow + fi * 1.7;
      final freq = 1.2 + fi * 0.35;
      final wobble = 0.55 + 0.45 * sin(fast + fi);

      // Build smooth spline points.
      const steps = 64;
      final pts = <Offset>[];
      for (int s = 0; s <= steps; s++) {
        final nx = (s / steps);
        final x = ribbonArea.left + ribbonArea.width * nx;
        final env = 0.22 + 0.78 * sin(pi * nx);

        // Slow drift prevents a "tileable" loop feel.
        final drift = sin((t * 0.07) + fi * 0.9) * ribbonArea.height * 0.015;
        final y =
            yBase +
            drift +
            sin(phase + nx * 2 * pi * freq) * amp * env +
            sin(phase * 0.71 + nx * 2 * pi * (freq * 0.53)) * amp * 0.38 * env;

        pts.add(Offset(x, y));
      }
      final path = _catmullRom(pts);

      final alpha = ((isPlaying ? 0.86 : 0.52) *
              (0.65 + 0.35 * wobble) *
              0.85 *
              _kRibbonIntensityMul)
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
            r * 0.187 * _kRibbonIntensityMul,
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
          ..strokeWidth = max(1.0, strokeW * 0.22)
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
    final breath = 0.5 + 0.5 * sin(fast * 0.9);
    final diaphragmR = r * (0.18 + 0.03 * breath * e);
    final glowA =
        (isPlaying ? 0.655 : 0.374) * (0.55 + 0.45 * breath) * e * 0.85;
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
          (isPlaying ? 0.172 : 0.109) * _smoothstep(0.0, 1.0, tw) * e * 0.85;
      grainPaint.color = Colors.white.withValues(alpha: a.clamp(0.0, 0.125));
      canvas.drawCircle(p, r * (0.010 + 0.010 * _hash(i + 99.0)), grainPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HypnoSpeakerPainter oldDelegate) {
    return true;
  }
}
