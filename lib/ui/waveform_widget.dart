import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../services/settings_service.dart';
import '../design/design_system.dart';

import 'torch_ship_painter.dart';

class WaveformWidget extends StatefulWidget {
  final String path;
  final AudioPlayer player;
  final Color playedColor;
  final Color unplayedColor;
  final bool showDuration;
  final MediaItem? item;

  const WaveformWidget({
    required this.path,
    required this.player,
    required this.playedColor,
    this.unplayedColor = Colors.transparent,
    this.showDuration = true,
    this.item,
    super.key,
  });

  @override
  State<WaveformWidget> createState() => _WaveformWidgetState();
}

class _WaveformWidgetState extends State<WaveformWidget> {
  List<double> _waveformData = [];
  Path? _cachedPath;
  Size? _cachedSize;
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

    final rnd = Random(widget.path.hashCode);
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
    return LayoutBuilder(
      builder: (context, constraints) {
        // If parent doesn't constrain height, fall back to the legacy 60px.
        final height =
            constraints.hasBoundedHeight && constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : 60.0;

        if (_isExtracting && _waveformData.isEmpty) {
          return SizedBox(
            height: height,
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        if (_waveformData.isEmpty) {
          return SizedBox(height: height);
        }

        final width = constraints.maxWidth;
        final sizeKey = Size(width, height);

        // Cache the path for this width
        if (_cachedPath == null || _cachedSize != sizeKey) {
          _cachedSize = sizeKey;
          // We can't easily cache based on width in State without checking if width changed.
          // But LayoutBuilder runs when constraints change.
          // Let's rebuild path here.
          final centerY = height / 2;
          final step = width / (_waveformData.length - 1);
          final newPath = Path();
          newPath.moveTo(0, centerY);
          for (int i = 0; i < _waveformData.length; i++) {
            final x = i * step;
            final amplitude = _waveformData[i];
            final ampH = amplitude * height * 0.88;
            newPath.lineTo(x, centerY - ampH / 2);
          }
          for (int i = _waveformData.length - 1; i >= 0; i--) {
            final x = i * step;
            final amplitude = _waveformData[i];
            final ampH = amplitude * height * 0.8;
            newPath.lineTo(x, centerY + ampH / 2);
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
                height: height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: PreciseWaveformPainter(
                            waveformData: _waveformData,
                            progress: currentProgress.clamp(0.0, 1.0),
                            timeSeconds: timeSeconds,
                            playedColor: SettingsService.instance.resolveAccentColor(
                              widget.playedColor,
                              item: widget.item,
                            ),
                            unplayedColor: widget.unplayedColor == Colors.transparent
                                ? _resolveUnplayedColor(
                                    widget.playedColor,
                                    SettingsService.instance.themeMode,
                                    widget.path,
                                    widget.item,
                                  )
                                : widget.unplayedColor,
                            bpm: _extractBpm(widget.item),
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
                                style: TextStyle(
                                  color: PlayaColors.onSurfaceVariant,
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

  Color _resolveWaveformAccent(
    Color accent,
    String themeMode,
    String path,
    MediaItem? item,
  ) {
    // Delegate to central resolver for consistency
    return SettingsService.instance.resolveAccentColor(accent, item: item);
  }

  Color _resolveUnplayedColor(
    Color accent,
    String themeMode,
    String path,
    MediaItem? item,
  ) {
    final base = _resolveWaveformAccent(accent, themeMode, path, item);
    return base.withValues(alpha: 0.18);
  }

  double? _extractBpm(MediaItem? item) {
    final rawBpm = item?.extras?['bpm'];
    if (rawBpm is num) {
      final bpmValue = rawBpm.toDouble();
      return bpmValue > 0 ? bpmValue : null;
    }
    return null;
  }


}

class PreciseWaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final double progress;
  final double timeSeconds;
  final Color playedColor;
  final Color unplayedColor;
  final double? bpm;
  final Path? cachedPath;

  PreciseWaveformPainter({
    required this.waveformData,
    required this.progress,
    required this.timeSeconds,
    required this.playedColor,
    required this.unplayedColor,
    this.bpm,
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
        final height = amplitude * size.height * 0.88;
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

    // Draw Unplayed (Background) - Subtle "Flight Path" - HIDDEN
    // canvas.drawPath(
    //   path,
    //   Paint()
    //     ..color = unplayedColor.withValues(alpha: 0.15) // Very subtle
    //     ..style = PaintingStyle.stroke
    //     ..strokeWidth = 1.0,
    // );
    // Also fill with very low opacity - HIDDEN
    // canvas.drawPath(
    //   path,
    //   Paint()
    //     ..color = unplayedColor.withValues(alpha: 0.05)
    //     ..style = PaintingStyle.fill,
    // );

    final width = size.width;
    final beatStrength = _computeBeatStrength(timeSeconds, bpm);
    // Cursor moves naturally at constant speed (progress-based), no beat sync
    final cursorX = (progress * width).clamp(0.0, width);
    final cursorY = centerY;
    final shipLen = size.height * 0.8; // Reduced from 0.95 (approx 15% smaller)
    // Ensure the tail/nozzle X is clamped so clipping/shaders don't paint the whole canvas
    final rawTail = cursorX - (shipLen * 0.45);
    final tailX = rawTail.clamp(0.0, width);

    // Sample waveform amplitude near the cursor to drive thruster intensity
    final cursorIdx = (progress * (waveformData.length - 1)).round().clamp(0, waveformData.length - 1);
    final exitAmplitude = waveformData[cursorIdx];
    final windowStart = max(0, cursorIdx - 4);
    double plumeEnergy = 0;
    for (int i = windowStart; i <= cursorIdx; i++) {
      plumeEnergy = max(plumeEnergy, waveformData[i]);
    }
    final waveformAmplitude = (exitAmplitude * 0.6 + plumeEnergy * 0.4).clamp(0.0, 1.0);

    // Draw Played (Waveform + Plasma Trail)
    canvas.save();
    // Clip cleanly at the nozzle so the waveform appears to emerge from the thrusters
    canvas.clipRect(Rect.fromLTWH(0, 0, tailX, size.height));

    // Engine plume behind the ship — amplitude-modulated by the waveform
    _drawEnginePlume(
      canvas: canvas,
      nozzleX: tailX,
      centerY: centerY,
      height: size.height,
      baseColor: playedColor,
      t: timeSeconds,
      beatStrength: beatStrength,
      waveformAmplitude: waveformAmplitude,
    );

    // 1. Amplitude-responsive Plasma-to-Track Gradient
    // Louder sections produce a longer, hotter plasma transition
    final transitionWidth = shipLen * (0.8 + 0.8 * waveformAmplitude);
    final gradStartX = tailX.clamp(0.0, width);
    final gradEndX = (tailX - transitionWidth).clamp(0.0, width);

    // Hotter gradient when amplitude is high — more white/cyan at the nozzle
    final hotStop = 0.25 * (1.0 - waveformAmplitude);
    final coolStop = 0.2 + 0.15 * (1.0 - waveformAmplitude);

    final mainShader = ui.Gradient.linear(
      Offset(gradStartX, 0),
      Offset(gradEndX, 0),
      [
        Colors.white,
        Colors.cyanAccent,
        playedColor,
      ],
      [0.0, coolStop, 1.0],
      TileMode.clamp,
    );

    canvas.drawPath(
      path,
      Paint()
        ..shader = mainShader
        ..style = PaintingStyle.fill,
    );

    // Base solid-ish fill (scaled with amplitude)
    canvas.drawPath(
      path,
      Paint()
        ..color = playedColor.withValues(alpha: (0.10 + 0.12 * waveformAmplitude).clamp(0.0, 1.0))
        ..style = PaintingStyle.fill,
    );

    // 2. Amplitude-responsive Plasma Glow Overlay (Bloom)
    final glowIntensity = 0.2 + 0.8 * waveformAmplitude;
    final glowStartX = tailX.clamp(0.0, width);
    final glowEndX = (tailX - transitionWidth * 0.5).clamp(0.0, width);
    final glowShader = ui.Gradient.linear(
      Offset(glowStartX, 0),
      Offset(glowEndX, 0),
      [
        Colors.white.withValues(alpha: (0.65 * glowIntensity).clamp(0.0, 1.0)),
        Colors.cyanAccent.withValues(alpha: (0.35 * glowIntensity).clamp(0.0, 1.0)),
        Colors.transparent,
      ],
      [0.0, 0.35, 1.0],
    );

    // Stronger outer glow layer
    canvas.drawPath(
      path,
      Paint()
        ..shader = glowShader
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11.0)
        ..blendMode = BlendMode.plus,
    );

    // Inner tighter glow
    canvas.drawPath(
      path,
      Paint()
        ..shader = glowShader
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.0)
        ..blendMode = BlendMode.plus,
    );

    // 3. Turbulence / Heat Haze — intensity follows amplitude
    final turbulenceAlpha = (0.1 * waveformAmplitude).clamp(0.0, 1.0);
    final turbulenceShader = ui.Gradient.linear(
      Offset(tailX, 0),
      Offset(tailX - transitionWidth, 0),
      [
        Colors.white.withValues(alpha: 0.0),
        Colors.white.withValues(alpha: turbulenceAlpha),
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

    // Subtle outline/stroke — brighter when loud
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15
        ..color = Colors.white.withValues(alpha: (0.12 + 0.15 * waveformAmplitude).clamp(0.0, 1.0))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.9),
    );

    // === Fixed throat: waveform exits the bell at bell's width ===
    // Pinch zone extends LEFT from the nozzle into the played area
    const throatScale = 0.10;
    final throatDist = shipLen * 0.35;
    final throatStartX = (tailX - throatDist).clamp(0.0, width);
    final throatEndX = tailX;

    // Stage 1: Tight throat right at the nozzle
    if (throatEndX > throatStartX) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(throatStartX, 0, throatDist, size.height));

      canvas.save();
      canvas.translate(0, centerY);
      canvas.scale(1.0, throatScale);
      canvas.translate(0, -centerY);

      final throatShader = ui.Gradient.linear(
        Offset(gradStartX, 0),
        Offset(gradEndX, 0),
        [
          Colors.white,
          Colors.cyanAccent,
          playedColor.withValues(alpha: 0.9),
        ],
        [0.0, hotStop, 1.0],
      );

      canvas.drawPath(
        path,
        Paint()
          ..shader = throatShader
          ..style = PaintingStyle.fill,
      );
      canvas.restore();
      canvas.restore();
    }

    canvas.restore();

    // === Full un-pinched section (played area past the throat) ===
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, throatStartX, size.height));

    canvas.drawPath(
      path,
      Paint()
        ..color = playedColor.withValues(alpha: (0.10 + 0.12 * waveformAmplitude).clamp(0.0, 1.0))
        ..style = PaintingStyle.fill,
    );

    final fullMainShader = ui.Gradient.linear(
      Offset(gradStartX, 0),
      Offset(gradEndX, 0),
      [
        Colors.white,
        Colors.cyanAccent,
        playedColor,
      ],
      [0.0, coolStop, 1.0],
      TileMode.clamp,
    );

    canvas.drawPath(
      path,
      Paint()
        ..shader = fullMainShader
        ..style = PaintingStyle.fill,
    );

    final fullGlowShader = ui.Gradient.linear(
      Offset(gradStartX, 0),
      Offset(gradEndX, 0),
      [
        Colors.white.withValues(alpha: (0.55 * glowIntensity).clamp(0.0, 1.0)),
        Colors.cyanAccent.withValues(alpha: (0.25 * glowIntensity).clamp(0.0, 1.0)),
        Colors.transparent,
      ],
      [0.0, 0.3, 1.0],
    );

    canvas.drawPath(
      path,
      Paint()
        ..shader = fullGlowShader
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9.0)
        ..blendMode = BlendMode.plus,
    );

    canvas.restore();

    canvas.save();
    canvas.translate(cursorX, cursorY);
    canvas.rotate(pi / 2);
    TorchShipPainter(
      height: size.height * 0.8,
      progress: progress,
      timeSeconds: timeSeconds,
      color: playedColor,
      bpm: bpm,
      drawPlume: false,
    ).paint(canvas, Size(size.height * 0.8, size.height * 0.8));
    canvas.restore();
  }

  double _computeBeatStrength(double timeSeconds, double? bpm) {
    final effectiveBpm = (bpm != null && bpm > 0) ? bpm : 120.0;
    final cycle = 60.0 / effectiveBpm;
    final phase = (timeSeconds % cycle) / cycle;
    return 0.35 + 0.65 * ((cos(2 * pi * phase) + 1.0) / 2.0);
  }

  void _drawEnginePlume({
    required Canvas canvas,
    required double nozzleX,
    required double centerY,
    required double height,
    required Color baseColor,
    required double t,
    required double beatStrength,
    required double waveformAmplitude,
  }) {
    final shipLen = height * 0.8;
    // Plume intensity scales with waveform amplitude
    final ampFactor = 0.3 + 0.7 * waveformAmplitude;
    final flicker = ampFactor * (1.0 + 0.08 * beatStrength + 0.035 * sin(t * 22.0) + 0.02 * cos(t * 41.0));
    final wobble = 1.0 + 0.045 * sin(t * 9.0) + 0.03 * sin(t * 15.0 + 0.9);
    final oscillation = sin(t * 7.0) * height * (0.02 + 0.008 * beatStrength);

    final plumeLen = shipLen * 2.25 * flicker;
    final coreHalfWidth = height * 0.11 * ampFactor;
    final haloHalfWidth = height * 0.26 * ampFactor;

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

    // Enhanced Nozzle Flare + Energy Burst — modulated by waveform amplitude
    final flareIntensity = (0.9 + 0.6 * beatStrength) * ampFactor;
    final flareRadius = height * (0.09 + 0.04 * beatStrength) * ampFactor;

    // Stronger central burst
    canvas.drawCircle(
      Offset(nozzleX, centerY),
      flareRadius,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(nozzleX, centerY),
          height * 0.22 * ampFactor,
          [
            Colors.white.withValues(alpha: 0.95 * ampFactor.clamp(0.0, 1.0)),
            Colors.cyanAccent.withValues(alpha: (0.55 * flareIntensity).clamp(0.0, 1.0)),
            Colors.transparent,
          ],
          [0.0, 0.35, 1.0],
        )
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Wider outer halo for more "power coming out" feel
    canvas.drawCircle(
      Offset(nozzleX, centerY),
      flareRadius * 1.6,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(nozzleX, centerY),
          height * 0.32 * ampFactor,
          [
            Colors.cyanAccent.withValues(alpha: (0.25 * flareIntensity).clamp(0.0, 1.0)),
            Colors.transparent,
          ],
          [0.0, 1.0],
        )
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    // Ion halo
    canvas.drawPath(
      haloPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(nozzleX, centerY),
          Offset(nozzleX - plumeLen * 1.25, centerY),
          [
            Colors.cyan.withValues(alpha: (0.28 * ampFactor).clamp(0.0, 1.0)),
            baseColor.withValues(alpha: (0.16 * ampFactor).clamp(0.0, 1.0)),
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
            Colors.white.withValues(alpha: (0.98 * ampFactor).clamp(0.0, 1.0)),
            Colors.cyanAccent.withValues(alpha: (0.72 * ampFactor).clamp(0.0, 1.0)),
            Colors.blue.withValues(alpha: 0.0),
          ],
          [0.0, 0.26, 1.0],
        )
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Shock diamonds (Mach disks) - scale with amplitude
    final diamondPaint =
        Paint()
          ..blendMode = BlendMode.plus
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6);
    const diamondCount = 6;
    for (int i = 1; i <= diamondCount; i++) {
      final ratio = i / (diamondCount + 1);
      final x = nozzleX - plumeLen * (0.14 + 0.70 * ratio);
      final y = centerY + sin(t * 6.5 + i) * height * 0.012;
      final intensity = (1.0 - ratio) * 0.55 * ampFactor;

      final w =
          height *
          0.06 *
          (1.0 - 0.25 * ratio) *
          (0.85 + 0.2 * sin(t * 7.0 + i));
      final h = w * 2.15;
      diamondPaint.color = Colors.white.withValues(alpha: intensity.clamp(0.0, 1.0));
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: w, height: h),
        diamondPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant PreciseWaveformPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      playedColor != oldDelegate.playedColor ||
      unplayedColor != oldDelegate.unplayedColor ||
      waveformData != oldDelegate.waveformData;
}
