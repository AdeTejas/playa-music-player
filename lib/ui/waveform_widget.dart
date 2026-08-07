import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../design/design_system.dart';
import '../services/settings_service.dart';
import 'rocinante_ship_painter.dart';

enum WaveformDisplayMode {
  /// Full torch ship + plume (music hero dock).
  standard,

  /// Slim scrubber under turntable — smaller ship, no diamonds.
  compact,

  /// Audiobook scrubber — soft plume, minimal motion.
  calm,
}

class WaveformWidget extends StatefulWidget {
  final String path;
  final AudioPlayer player;
  final Color playedColor;
  final Color unplayedColor;
  final bool showDuration;
  final MediaItem? item;
  final WaveformDisplayMode displayMode;
  final List<Map<String, dynamic>>? bookmarks;
  final bool isVisible;

  const WaveformWidget({
    required this.path,
    required this.player,
    required this.playedColor,
    this.unplayedColor = Colors.transparent,
    this.showDuration = true,
    this.item,
    this.displayMode = WaveformDisplayMode.standard,
    this.bookmarks,
    this.isVisible = true,
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
  int _lastBookmarkHitIndex = -1;

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
          final centerY = height / 2;
          final step = width / (_waveformData.length - 1);
          final newPath = Path();
          newPath.moveTo(0, centerY);
          for (int i = 0; i < _waveformData.length; i++) {
            final x = i * step;
            final amplitude = _waveformData[i];
            final ampH = amplitude * height * 0.675;
            newPath.lineTo(x, centerY - ampH / 2);
          }
          for (int i = _waveformData.length - 1; i >= 0; i--) {
            final x = i * step;
            final amplitude = _waveformData[i];
            final ampH = amplitude * height * 0.675;
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

              // Haptic pulse when hitting a bookmark
              if (widget.bookmarks != null && widget.bookmarks!.isNotEmpty) {
                final currentMs = pos.inMilliseconds;
                for (int i = 0; i < widget.bookmarks!.length; i++) {
                  final b = widget.bookmarks![i];
                  final bPos = b['position'] as int? ?? 0;
                  if ((currentMs - bPos).abs() < 250) {
                    if (_lastBookmarkHitIndex != i) {
                      _lastBookmarkHitIndex = i;
                      HapticFeedback.selectionClick();
                    }
                    break;
                  }
                  if (i == widget.bookmarks!.length - 1) {
                    _lastBookmarkHitIndex = -1;
                  }
                }
              }
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
                            playedColor: _resolveWaveformAccent(
                              widget.playedColor,
                              SettingsService.instance.themeMode,
                              widget.path,
                              widget.item,
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
                            displayMode: widget.displayMode,
                            bookmarks: widget.bookmarks,
                            durationMs: dur?.inMilliseconds ?? 0,
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
    if (themeMode == SettingsService.themeNeon) {
      return _neonAccent(accent);
    }
    if (themeMode == SettingsService.themeAlbumArt) {
      final key = item?.id ?? item?.title ?? path;
      return _albumArtAccent(accent, key);
    }
    return accent;
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

  /// Neon theme keeps the user's hue and just maxes saturation/value, matching
  /// [SettingsService.resolveAccentColor] so the ship matches the rest of the UI.
  Color _neonAccent(Color accent) {
    final hsv = HSVColor.fromColor(accent);
    return hsv.withSaturation(1.0).withValue(1.0).toColor();
  }

  Color _albumArtAccent(Color accent, String key) {
    final rnd = Random(key.hashCode);
    return HSLColor.fromAHSL(
      1.0,
      rnd.nextDouble() * 360,
      0.70 + rnd.nextDouble() * 0.18,
      0.42 + rnd.nextDouble() * 0.12,
    ).toColor();
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
  final WaveformDisplayMode displayMode;
  final List<Map<String, dynamic>>? bookmarks;
  final int durationMs;

  PreciseWaveformPainter({
    required this.waveformData,
    required this.progress,
    required this.timeSeconds,
    required this.playedColor,
    this.unplayedColor = Colors.transparent,
    this.bpm,
    this.cachedPath,
    this.displayMode = WaveformDisplayMode.standard,
    this.bookmarks,
    this.durationMs = 0,
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
        final height = amplitude * size.height * 0.675;
        path.lineTo(x, centerY - height / 2);
      }
      for (int i = waveformData.length - 1; i >= 0; i--) {
        final x = i * step;
        final amplitude = waveformData[i];
        final height = amplitude * size.height * 0.675;
        path.lineTo(x, centerY + height / 2);
      }
      path.close();
    }

    final width = size.width;
    final beatStrength = _computeBeatStrength(timeSeconds, bpm);
    // Stern anchored to the playhead: the ship is parked fully visible at the
    // waveform's start (progress=0, stern at x=0) and flies right as the track
    // plays, with the plasma trail streaming from the stern over the played region.
    final playheadX = (progress * width).clamp(0.0, width);
    final shipLen = size.height * (displayMode == WaveformDisplayMode.compact ? 0.45 : 0.7125);
    final cursorX = playheadX + shipLen * 0.45;
    final cursorY = centerY;
    final rawTail = cursorX - (shipLen * 0.45);
    final tailX = rawTail.clamp(0.0, width);

    // Draw Played (Waveform + Plasma Trail)
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, tailX, size.height));

    // Engine plume behind the ship
    _drawEnginePlume(
      canvas: canvas,
      nozzleX: tailX,
      centerY: centerY,
      height: size.height,
      baseColor: playedColor,
      t: timeSeconds,
      beatStrength: beatStrength,
    );

    final transitionWidth = shipLen * 1.5;
    final gradStartX = tailX.clamp(0.0, width);
    final gradEndX = (tailX - transitionWidth).clamp(0.0, width);

    final midAccent = Color.lerp(Colors.white, playedColor, 0.45) ?? playedColor;

    final mainShader = ui.Gradient.linear(
      Offset(gradStartX, 0),
      Offset(gradEndX, 0),
      [
        Colors.white,
        midAccent,
        playedColor,
      ],
      [0.0, 0.2, 1.0],
      TileMode.clamp,
    );

    canvas.drawPath(
      path,
      Paint()
        ..shader = mainShader
        ..style = PaintingStyle.fill,
    );

    final glowStartX = tailX.clamp(0.0, width);
    final glowEndX = (tailX - transitionWidth * 0.5).clamp(0.0, width);
    final glowShader = ui.Gradient.linear(
      Offset(glowStartX, 0),
      Offset(glowEndX, 0),
      [
        Colors.white.withValues(alpha: 0.5),
        playedColor.withValues(alpha: 0.25),
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
        )
        ..blendMode = BlendMode.plus,
    );

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
      Offset(cursorX, cursorY),
      size.height,
      playedColor,
      progress,
      timeSeconds,
      beatStrength,
    );
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
  }) {
    final shipLen = height * 0.7125;
    final flicker = 1.0 + 0.08 * beatStrength + 0.035 * sin(t * 22.0) + 0.02 * cos(t * 41.0);
    final wobble = 1.0 + 0.045 * sin(t * 9.0) + 0.03 * sin(t * 15.0 + 0.9);
    final oscillation = sin(t * 7.0) * height * (0.02 + 0.008 * beatStrength);

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

    canvas.drawCircle(
      Offset(nozzleX, centerY),
      height * 0.075,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(nozzleX, centerY),
          height * 0.18,
          [
            Colors.white.withValues(alpha: 0.95),
            baseColor.withValues(alpha: 0.35),
            Colors.transparent,
          ],
          [0.0, 0.45, 1.0],
        )
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    canvas.drawPath(
      haloPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(nozzleX, centerY),
          Offset(nozzleX - plumeLen * 1.25, centerY),
          [
            baseColor.withValues(alpha: 0.28),
            baseColor.withValues(alpha: 0.16),
            baseColor.withValues(alpha: 0.0),
          ],
          [0.0, 0.55, 1.0],
        )
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );

    canvas.drawPath(
      corePath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(nozzleX, centerY),
          Offset(nozzleX - plumeLen * 0.95, centerY),
          [
            Colors.white.withValues(alpha: 0.98),
            baseColor.withValues(alpha: 0.72),
            baseColor.withValues(alpha: 0.0),
          ],
          [0.0, 0.26, 1.0],
        )
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // Heat-haze shimmer across the exhaust body.
    final plumeShimmerShader = ui.Gradient.linear(
      Offset(nozzleX, 0),
      Offset(nozzleX - plumeLen * 0.9, 0),
      [
        Colors.white.withValues(alpha: 0.0),
        Colors.white.withValues(alpha: 0.07),
        Colors.white.withValues(alpha: 0.0),
      ],
      [0.0, 0.5, 1.0],
      TileMode.repeated,
    );
    canvas.save();
    canvas.clipPath(haloPath);
    canvas.drawPath(
      haloPath,
      Paint()
        ..shader = plumeShimmerShader
        ..blendMode = BlendMode.overlay,
    );
    canvas.restore();

    final diamondPaint =
        Paint()
          ..blendMode = BlendMode.plus
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6);
    if (displayMode == WaveformDisplayMode.standard) {
      const diamondCount = 6;
      for (int i = 1; i <= diamondCount; i++) {
        final ratio = i / (diamondCount + 1);
        final x = nozzleX - plumeLen * (0.14 + 0.70 * ratio);
        final y = centerY + sin(t * 6.5 + i) * height * 0.012;
        final intensity = (1.0 - ratio) * 0.55;

        final beatScale = 0.9 + 0.2 * beatStrength;
        final w =
            height *
            0.06 *
            (1.0 - 0.25 * ratio) *
            (0.85 + 0.2 * sin(t * 7.0 + i)) *
            beatScale;
        final h = w * 2.15;
        final chainColor =
            Color.lerp(baseColor, Color.lerp(baseColor, Colors.black, 0.4), ratio) ??
            baseColor;
        final diamondColor = Color.lerp(Colors.white, chainColor, ratio) ?? Colors.white;
        diamondPaint.color = diamondColor.withValues(alpha: intensity);
        canvas.drawOval(
          Rect.fromCenter(center: Offset(x, y), width: w, height: h),
          diamondPaint,
        );

        if (intensity > 0.3) {
          // Chromatic aberration: cyan/red edge shift on the hot diamonds.
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(x + w * 0.35, y),
              width: w,
              height: h,
            ),
            Paint()
              ..color = Colors.cyanAccent.withValues(alpha: intensity * 0.16)
              ..blendMode = BlendMode.plus
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6),
          );
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(x - w * 0.35, y),
              width: w,
              height: h,
            ),
            Paint()
              ..color = const Color(0xFFFF5252).withValues(alpha: intensity * 0.12)
              ..blendMode = BlendMode.plus
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6),
          );
        }
      }
    }

    // Ember particles drifting back along the plume tail.
    for (int i = 0; i < 4; i++) {
      final life = (t * 3.1 + i * 2.7) % 1.0;
      final ex = nozzleX - plumeLen * (0.5 + life * 0.95);
      final ey = centerY + sin(t * 9.0 + i * 2.4) * height * 0.15 * (0.35 + life);
      final er = height * 0.014 * (1.0 - life * 0.5);
      canvas.drawCircle(
        Offset(ex, ey),
        er,
        Paint()
          ..color = baseColor.withValues(alpha: 0.35 * beatStrength * (1.0 - life))
          ..blendMode = BlendMode.plus
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
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
    double beatStrength,
  ) {
    final shipLen =
        height *
        (displayMode == WaveformDisplayMode.compact ? 0.45 : 0.7125);

    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(pi / 2);
    RocinanteShipPainter(
      shipLen: shipLen,
      color: color,
      timeSeconds: timeSeconds,
      beatStrength: beatStrength,
      drawDiamonds: displayMode == WaveformDisplayMode.standard,
    ).paint(canvas, Size(shipLen, shipLen));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PreciseWaveformPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      timeSeconds != oldDelegate.timeSeconds ||
      playedColor != oldDelegate.playedColor ||
      unplayedColor != oldDelegate.unplayedColor ||
      waveformData != oldDelegate.waveformData ||
      displayMode != oldDelegate.displayMode;
}
