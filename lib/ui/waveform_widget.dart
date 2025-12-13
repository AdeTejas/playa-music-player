import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

class WaveformWidget extends StatefulWidget {
  final String path;
  final AudioPlayer player;
  final Color playedColor;
  final Color unplayedColor;
  final bool showDuration;

  const WaveformWidget({
    required this.path,
    required this.player,
    required this.playedColor,
    this.unplayedColor = Colors.transparent,
    this.showDuration = true,
    super.key,
  });

  @override
  State<WaveformWidget> createState() => _WaveformWidgetState();
}

class _WaveformWidgetState extends State<WaveformWidget> {
  List<double> _waveformData = [];
  Path? _cachedPath;
  double? _cachedWidth;
  bool _isExtracting = false;

  int _lastSeekAtMs = 0;
  Duration? _pendingSeek;

  @override
  void initState() {
    super.initState();
    _loadWaveform();
  }

  @override
  void didUpdateWidget(covariant WaveformWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _waveformData = [];
      _cachedPath = null;
      _loadWaveform();
    }
  }

  Future<void> _loadWaveform() async {
    if (_waveformData.isNotEmpty || _isExtracting) return;

    setState(() => _isExtracting = true);

    // Unified Simulation Logic (for consistency across Windows/Android)
    // We use a simulated "organic" waveform that matches the Rocinante/Expanse aesthetic
    // better than raw audio data (which can be too spiky/noisy).

    // Simulate song structure: Intro -> Verse -> Chorus -> Bridge -> Chorus -> Outro
    final rnd = Random(widget.path.hashCode); // Stable random based on path
    final List<double> data = [];

    // Generate smoother, more "plasma-like" data
    for (int i = 0; i < 100; i++) {
      double t = i / 100.0;

      // Base structure (Envelope)
      double envelope = 1.0;
      if (t < 0.1) {
        envelope = t * 10.0; // Fade in
      } else if (t > 0.9) {
        envelope = (1.0 - t) * 10.0; // Fade out
      }

      // Composition of sine waves for organic look
      double val = 0.3;
      val += 0.2 * sin(t * 15 + rnd.nextDouble());
      val += 0.1 * sin(t * 40 + rnd.nextDouble());
      val += 0.05 * sin(t * 80 + rnd.nextDouble());

      // "Beats" (Engine pulses)
      if (i % 4 == 0) val += 0.15 * rnd.nextDouble();

      // Chorus sections (Loud)
      if ((t > 0.3 && t < 0.45) || (t > 0.7 && t < 0.85)) {
        val *= 1.4;
      }

      data.add((val * envelope).clamp(0.05, 1.0));
    }

    if (mounted) {
      setState(() {
        _waveformData = data;
        _isExtracting = false;
      });
    }
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) {
      return '$h:$m:$s';
    }
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    // if (Platform.isWindows) return const SizedBox(); // Removed to allow simulated waveform

    if (_isExtracting && _waveformData.isEmpty) {
      return const SizedBox(
        height: 60,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_waveformData.isEmpty) {
      return const SizedBox(height: 60);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        // Cache the path for this width
        if (_cachedPath == null || _cachedWidth != width) {
          _cachedWidth = width;
          // We can't easily cache based on width in State without checking if width changed.
          // But LayoutBuilder runs when constraints change.
          // Let's rebuild path here.
          const centerY = 30.0;
          final step = width / (_waveformData.length - 1);
          final newPath = Path();
          newPath.moveTo(0, centerY);
          for (int i = 0; i < _waveformData.length; i++) {
            final x = i * step;
            final amplitude = _waveformData[i];
            final height = amplitude * 60 * 0.8;
            newPath.lineTo(x, centerY - height / 2);
          }
          for (int i = _waveformData.length - 1; i >= 0; i--) {
            final x = i * step;
            final amplitude = _waveformData[i];
            final height = amplitude * 60 * 0.8;
            newPath.lineTo(x, centerY + height / 2);
          }
          newPath.close();
          _cachedPath = newPath;
        }

        return StreamBuilder<Duration>(
          stream: widget.player.positionStream,
          builder: (context, posSnapshot) {
            double currentProgress = 0.0;
            double timeSeconds = 0.0;
            final pos = posSnapshot.data;
            final dur = widget.player.duration;
            if (pos != null && dur != null && dur.inMilliseconds > 0) {
              currentProgress = pos.inMilliseconds / dur.inMilliseconds;
              timeSeconds = pos.inMilliseconds / 1000.0;
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate:
                  (details) => _scheduleSeek(details.globalPosition, context),
              onHorizontalDragEnd: (_) => _flushPendingSeek(),
              onTapDown: (details) => _seek(details.globalPosition, context),
              child: SizedBox(
                height: 60,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: PreciseWaveformPainter(
                            waveformData: _waveformData,
                            progress: currentProgress.clamp(0.0, 1.0),
                            timeSeconds: timeSeconds,
                            playedColor: widget.playedColor,
                            unplayedColor: widget.unplayedColor,
                            cachedPath: _cachedPath,
                          ),
                        ),
                      ),
                    ),
                    if (widget.showDuration) ...[
                      Positioned(
                        left: 0,
                        bottom: 0,
                        child: Text(
                          _fmt(posSnapshot.data ?? Duration.zero),
                          style: TextStyle(
                            color: widget.playedColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            shadows: const [
                              Shadow(blurRadius: 2, color: Colors.black),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: StreamBuilder<Duration?>(
                          stream: widget.player.durationStream,
                          builder:
                              (_, durSnap) => Text(
                                _fmt(durSnap.data ?? Duration.zero),
                                style: const TextStyle(
                                  color: Color(0xFFA68B6C), // _on2
                                  fontSize: 10,
                                  shadows: [
                                    Shadow(blurRadius: 2, color: Colors.black),
                                  ],
                                ),
                              ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _seek(Offset globalPosition, BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalPosition);
    final width = box.size.width;
    final dur = widget.player.duration;
    if (dur == null) return;
    final seekMs =
        (local.dx.clamp(0.0, width) / width * dur.inMilliseconds).round();
    await widget.player.seek(Duration(milliseconds: seekMs));
  }

  void _scheduleSeek(Offset globalPosition, BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final dur = widget.player.duration;
    if (dur == null) return;

    final local = box.globalToLocal(globalPosition);
    final width = box.size.width;
    final seekMs =
        (local.dx.clamp(0.0, width) / width * dur.inMilliseconds).round();
    final target = Duration(milliseconds: seekMs);

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSeekAtMs >= 60) {
      _lastSeekAtMs = now;
      _pendingSeek = null;
      widget.player.seek(target);
    } else {
      _pendingSeek = target;
    }
  }

  void _flushPendingSeek() {
    final pending = _pendingSeek;
    if (pending == null) return;
    _pendingSeek = null;
    _lastSeekAtMs = DateTime.now().millisecondsSinceEpoch;
    widget.player.seek(pending);
  }
}

class PreciseWaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final double progress;
  final double timeSeconds;
  final Color playedColor;
  final Color unplayedColor;
  final Path? cachedPath;

  PreciseWaveformPainter({
    required this.waveformData,
    required this.progress,
    required this.timeSeconds,
    required this.playedColor,
    required this.unplayedColor,
    this.cachedPath,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveformData.isEmpty) return;

    final centerY = size.height / 2;
    late final Path path;
    if (cachedPath != null) {
      path = cachedPath!;
    } else {
      final width = size.width;
      final step = width / (waveformData.length - 1);

      path = Path();
      path.moveTo(0, centerY);

      for (int i = 0; i < waveformData.length; i++) {
        final x = i * step;
        final amplitude = waveformData[i];
        final height = amplitude * size.height * 0.8;
        path.lineTo(x, centerY - height / 2);
      }
      for (int i = waveformData.length - 1; i >= 0; i--) {
        final x = i * step;
        final amplitude = waveformData[i];
        final height = amplitude * size.height * 0.8;
        path.lineTo(x, centerY + height / 2);
      }
      path.close();
    }

    // Draw Unplayed (Background) - Subtle "Flight Path"
    canvas.drawPath(
      path,
      Paint()
        ..color = unplayedColor.withValues(alpha: 0.15) // Very subtle
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    // Also fill with very low opacity
    canvas.drawPath(
      path,
      Paint()
        ..color = unplayedColor.withValues(alpha: 0.05)
        ..style = PaintingStyle.fill,
    );

    final width = size.width;
    final cursorX = progress * width;
    final shipLen = size.height * 0.8; // Reduced from 0.95 (approx 15% smaller)
    final tailX = cursorX - (shipLen * 0.45);

    // Draw Played (Waveform + Plasma Trail)
    canvas.save();
    // Clip to the tail of the ship so waveform appears to come out of the engine
    canvas.clipRect(Rect.fromLTWH(0, 0, tailX, size.height));

    // Engine plume behind the ship (separate from the waveform, like exhaust)
    _drawEnginePlume(
      canvas: canvas,
      nozzleX: tailX,
      centerY: centerY,
      height: size.height,
      baseColor: playedColor,
      t: timeSeconds,
    );

    // 1. Unified Plasma-to-Track Gradient (The "Merge")
    // The waveform starts as hot white plasma, cools to cyan, then becomes the track color.
    // We match the transition width to the plume length for visual consistency.
    final transitionWidth = shipLen * 1.5;

    final mainShader = ui.Gradient.linear(
      Offset(tailX, 0),
      Offset(tailX - transitionWidth, 0),
      [
        Colors.white, // Hot Engine Output (At Nozzle)
        Colors.cyanAccent, // Cooling Plasma
        playedColor, // Solid Track
      ],
      [0.0, 0.2, 1.0],
      TileMode.clamp, // Extends 'playedColor' to the left
    );

    canvas.drawPath(
      path,
      Paint()
        ..shader = mainShader
        ..style = PaintingStyle.fill,
    );

    // 2. Plasma Glow Overlay (Bloom)
    // Adds a soft glowing aura around the hot part
    final glowShader = ui.Gradient.linear(
      Offset(tailX, 0),
      Offset(tailX - transitionWidth * 0.5, 0), // Tighter glow
      [
        Colors.white.withValues(alpha: 0.5), // Slightly less intense
        Colors.cyan.withValues(alpha: 0.2),
        Colors.transparent,
      ],
      [0.0, 0.3, 1.0],
    );

    canvas.drawPath(
      path,
      Paint()
        ..shader = glowShader
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          6.0,
        ) // Refined blur
        ..blendMode = BlendMode.plus, // Additive blend for light
    );

    // 3. Turbulence / Heat Haze (Subtle)
    final turbulenceShader = ui.Gradient.linear(
      Offset(tailX, 0),
      Offset(tailX - transitionWidth, 0),
      [
        Colors.white.withValues(alpha: 0.0),
        Colors.white.withValues(alpha: 0.1),
        Colors.white.withValues(alpha: 0.0),
      ],
      [0.0, 0.5, 1.0],
      TileMode.repeated,
    );

    canvas.drawPath(
      path,
      Paint()
        ..shader = turbulenceShader
        ..style = PaintingStyle.fill
        ..blendMode = BlendMode.overlay,
    );

    canvas.restore();

    // Draw Rocinante Cursor
    _drawRocinante(
      canvas,
      Offset(cursorX, centerY),
      size.height,
      playedColor,
      progress,
      timeSeconds,
    );
  }

  void _drawEnginePlume({
    required Canvas canvas,
    required double nozzleX,
    required double centerY,
    required double height,
    required Color baseColor,
    required double t,
  }) {
    final shipLen = height * 0.8;
    // Epstein-inspired drive: long, collimated, white-hot core with blue ion halo.
    final flicker = 1.0 + 0.035 * sin(t * 22.0) + 0.02 * cos(t * 41.0);
    final wobble = 1.0 + 0.045 * sin(t * 9.0) + 0.03 * sin(t * 15.0 + 0.9);
    final oscillation = sin(t * 7.0) * height * 0.02;

    final plumeLen = shipLen * 2.25 * flicker;
    final coreHalfWidth = height * 0.11;
    final haloHalfWidth = height * 0.26;

    Path buildDrivePlume({
      required double halfWidth,
      required double lenScale,
    }) {
      final len = plumeLen * lenScale;
      final tipX = nozzleX - len;
      final c1x = nozzleX - len * 0.28;
      final c2x = nozzleX - len * 0.72;

      final p = Path();
      p.moveTo(nozzleX, centerY - halfWidth);
      p.cubicTo(
        c1x,
        centerY - halfWidth * 0.65,
        c2x,
        centerY - halfWidth * 0.25 * wobble,
        tipX,
        centerY + oscillation,
      );
      p.cubicTo(
        c2x,
        centerY + halfWidth * 0.25 * wobble,
        c1x,
        centerY + halfWidth * 0.65,
        nozzleX,
        centerY + halfWidth,
      );
      p.close();
      return p;
    }

    final haloPath = buildDrivePlume(halfWidth: haloHalfWidth, lenScale: 1.18);
    final corePath = buildDrivePlume(halfWidth: coreHalfWidth, lenScale: 0.98);

    // Nozzle flare
    canvas.drawCircle(
      Offset(nozzleX, centerY),
      height * 0.075,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(nozzleX, centerY),
          height * 0.18,
          [
            Colors.white.withValues(alpha: 0.95),
            Colors.cyanAccent.withValues(alpha: 0.35),
            Colors.transparent,
          ],
          [0.0, 0.45, 1.0],
        )
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Ion halo
    canvas.drawPath(
      haloPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(nozzleX, centerY),
          Offset(nozzleX - plumeLen * 1.25, centerY),
          [
            Colors.cyan.withValues(alpha: 0.28),
            baseColor.withValues(alpha: 0.16),
            Colors.blue.withValues(alpha: 0.0),
          ],
          [0.0, 0.55, 1.0],
        )
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    // White-hot core
    canvas.drawPath(
      corePath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(nozzleX, centerY),
          Offset(nozzleX - plumeLen * 0.95, centerY),
          [
            Colors.white.withValues(alpha: 0.98),
            Colors.cyanAccent.withValues(alpha: 0.72),
            Colors.blue.withValues(alpha: 0.0),
          ],
          [0.0, 0.26, 1.0],
        )
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Shock diamonds (Mach disks) - subtle, banded highlights.
    final diamondPaint =
        Paint()
          ..blendMode = BlendMode.plus
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6);
    const diamondCount = 6;
    for (int i = 1; i <= diamondCount; i++) {
      final ratio = i / (diamondCount + 1);
      final x = nozzleX - plumeLen * (0.14 + 0.70 * ratio);
      final y = centerY + sin(t * 6.5 + i) * height * 0.012;
      final intensity = (1.0 - ratio) * 0.55;

      final w =
          height *
          0.06 *
          (1.0 - 0.25 * ratio) *
          (0.85 + 0.2 * sin(t * 7.0 + i));
      final h = w * 2.15;
      diamondPaint.color = Colors.white.withValues(alpha: intensity);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: w, height: h),
        diamondPaint,
      );
    }
  }

  void _drawRocinante(
    Canvas canvas,
    Offset pos,
    double height,
    Color color,
    double progress,
    double timeSeconds,
  ) {
    // The Rocinante (Tachi) - Corvette Class
    final shipLen = height * 0.8; // Reduced from 0.95 (approx 15% smaller)
    final shipWidth = shipLen * 0.25; // Reduced from 0.35
    final rnd = Random(
      (timeSeconds * 10).floor(),
    ); // Stable random per 100ms (position-driven)

    final accent = color;
    final accentCool = Color.lerp(Colors.cyanAccent, accent, 0.55) ?? accent;
    final accentWarm =
        Color.lerp(const Color(0xFFD84315), accent, 0.45) ?? accent;

    canvas.save();
    canvas.translate(pos.dx, pos.dy);

    // Stabilized (No turbulence)
    const turbulence = 0.0;
    canvas.rotate(pi / 2 + turbulence); // Point right

    // Shadow (offset)
    canvas.drawPath(
      _buildRociHull(shipLen, shipWidth).shift(const Offset(4, 8)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // 1. Drive Plume (Epstein Drive) - more collimated + turbulent edges
    final flicker =
        1.0 + 0.05 * sin(timeSeconds * 22.0) + 0.03 * cos(timeSeconds * 41.0);
    final wobble =
        1.0 +
        0.06 * sin(timeSeconds * 9.0) +
        0.04 * sin(timeSeconds * 15.0 + 0.9);
    final plumeLen = shipLen * 1.55 * flicker;

    Path buildDrivePlume({required double width, required double lenScale}) {
      final baseY = shipLen * 0.45;
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

    // Nozzle flare
    canvas.drawCircle(
      Offset(0, shipLen * 0.45),
      shipWidth * 0.18,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(0, shipLen * 0.45),
          shipWidth * 0.40,
          [
            Colors.white.withValues(alpha: 0.75),
            accentCool.withValues(alpha: 0.40),
            Colors.transparent,
          ],
          [0.0, 0.4, 1.0],
        )
        ..blendMode = BlendMode.plus,
    );

    // Halo (ionized exhaust)
    canvas.drawPath(
      haloPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, shipLen * 0.45),
          Offset(0, shipLen * 0.45 + plumeLen * 1.35),
          [
            accentCool.withValues(alpha: 0.38),
            accent.withValues(alpha: 0.16),
            Colors.blue.withValues(alpha: 0.0),
          ],
          [0.0, 0.55, 1.0],
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
        ..blendMode = BlendMode.plus,
    );

    // Core (white-hot)
    canvas.drawPath(
      corePath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, shipLen * 0.45),
          Offset(0, shipLen * 0.45 + plumeLen * 0.95),
          [
            Colors.white.withValues(alpha: 0.95),
            accentCool.withValues(alpha: 0.78),
            Colors.blue.withValues(alpha: 0.0),
          ],
          [0.0, 0.22, 1.0],
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
        ..blendMode = BlendMode.plus,
    );

    // Shock Diamonds (Mach disks) - slightly irregular to avoid "sticker" look
    const diamondCount = 5;
    final diamondPaint =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.65)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0);

    for (int i = 1; i <= diamondCount; i++) {
      final dy = shipLen * 0.45 + (plumeLen * 0.18 * i);
      final wob = 0.85 + 0.20 * sin(timeSeconds * 7.0 + i);
      final w = shipWidth * 0.32 * (1.0 - (i / (diamondCount + 1))) * wob;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(0, dy), width: w, height: w * 0.6),
        diamondPaint,
      );
    }

    // 2. RCS Thrusters (Random firings)
    if (rnd.nextDouble() > 0.85) {
      _drawRCS(
        canvas,
        Offset(-shipWidth * 0.4, -shipLen * 0.3),
        -pi / 2,
        shipLen,
      );
    }
    if (rnd.nextDouble() > 0.85) {
      _drawRCS(
        canvas,
        Offset(shipWidth * 0.4, -shipLen * 0.3),
        pi / 2,
        shipLen,
      );
    }
    if (rnd.nextDouble() > 0.9) {
      _drawRCS(
        canvas,
        Offset(-shipWidth * 0.3, shipLen * 0.2),
        -pi / 2,
        shipLen,
      );
    }

    // 3. Hull Construction
    final hullPath = _buildRociHull(shipLen, shipWidth);

    // Base Hull Shader (Metallic & Detailed)
    final hullPaint =
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(-shipWidth / 2, 0),
            Offset(shipWidth / 2, 0),
            [
              const Color(0xFF0D0D0D),
              const Color(0xFF4A4A4A), // Highlight
              const Color(0xFF1A1A1A),
              const Color(0xFF050505),
            ],
            [0.0, 0.3, 0.6, 1.0],
          );
    canvas.drawPath(hullPath, hullPaint);

    // Subtle accent edge glow (ties ship into overall app accent)
    canvas.drawPath(
      hullPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = shipLen * 0.015
        ..color = accent.withValues(alpha: 0.14)
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0),
    );

    // 4. MCRN Orange Markings & Details
    canvas.save();
    canvas.clipPath(hullPath);

    final stripePaint =
        Paint()
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

    final blockPaint = Paint()..color = accentWarm;
    canvas.drawRect(
      Rect.fromCenter(
        center: const Offset(0, 0),
        width: shipWidth,
        height: shipLen * 0.15,
      ),
      blockPaint,
    );

    // Panel Lines
    final panelPaint =
        Paint()
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

    // Text / Decals
    final textPaint =
        Paint()
          ..color = Colors.white.withValues(alpha: 0.9)
          ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(-shipWidth * 0.2, 0),
      Offset(shipWidth * 0.2, 0),
      textPaint,
    );

    // Cockpit Window (Lit)
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(0, -shipLen * 0.25),
        width: shipWidth * 0.4,
        height: shipLen * 0.05,
      ),
      Paint()
        ..color = accentCool.withValues(alpha: 0.92)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1),
    );

    // Railgun Barrel (Keel mounted)
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(0, -shipLen * 0.45),
        width: shipWidth * 0.1,
        height: shipLen * 0.1,
      ),
      Paint()..color = const Color(0xFF111111),
    );

    canvas.restore();

    // 5. Engine Bell
    final nozzlePath = Path();
    nozzlePath.moveTo(-shipWidth * 0.35, shipLen * 0.45);
    nozzlePath.lineTo(shipWidth * 0.35, shipLen * 0.45);
    nozzlePath.lineTo(shipWidth * 0.3, shipLen * 0.4);
    nozzlePath.lineTo(-shipWidth * 0.3, shipLen * 0.4);
    nozzlePath.close();
    canvas.drawPath(nozzlePath, Paint()..color = const Color(0xFF080808));

    canvas.restore();
  }

  void _drawRCS(Canvas canvas, Offset pos, double angle, double shipLen) {
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
        ..color = Colors.white.withValues(alpha: 0.3) // SUBTLE
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PreciseWaveformPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      playedColor != oldDelegate.playedColor ||
      unplayedColor != oldDelegate.unplayedColor ||
      waveformData != oldDelegate.waveformData;

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
}
