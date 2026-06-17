import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../design/design_system.dart';
import '../services/settings_service.dart';
import '../services/waveform_envelope_service.dart';
import 'now_playing_layout.dart';
import 'playback_motion.dart';
import 'torch_plume_engine.dart';
import 'torch_ship_painter.dart';

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
  final bool showDuration;
  final MediaItem? item;
  final WaveformDisplayMode displayMode;

  const WaveformWidget({
    required this.path,
    required this.player,
    required this.playedColor,
    this.showDuration = true,
    this.item,
    this.displayMode = WaveformDisplayMode.standard,
    super.key,
  });

  @override
  State<WaveformWidget> createState() => _WaveformWidgetState();
}

class _WaveformWidgetState extends State<WaveformWidget> {
  List<double> _waveformData = [];
  bool _isExtracting = false;
  bool _usingProceduralPreview = false;
  String? _loadError;

  int _lastSeekAtMs = 0;
  Duration? _pendingSeek;

  List<double> _proceduralPreview() =>
      WaveformEnvelopeService.instance.proceduralFallback(
        widget.path,
        samples: 300,
      );

  @override
  void initState() {
    super.initState();
    _waveformData = _proceduralPreview();
    _usingProceduralPreview = true;
    _loadWaveform();
  }

  @override
  void didUpdateWidget(covariant WaveformWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _waveformData = _proceduralPreview();
      _usingProceduralPreview = true;
      _loadError = null;
      _loadWaveform();
    }
  }

  @override
  void dispose() {
    _isExtracting = false;
    super.dispose();
  }

  Future<void> _loadWaveform() async {
    if (_isExtracting) return;
    if (!_usingProceduralPreview && _waveformData.isNotEmpty) return;

    _isExtracting = true;
    _loadError = null;

    List<double> data;
    try {
      data = await WaveformEnvelopeService.instance
          .loadEnvelope(widget.path, samples: 300)
          .timeout(
            const Duration(seconds: 6),
            onTimeout: () =>
                WaveformEnvelopeService.instance.proceduralFallback(
              widget.path,
              samples: 300,
            ),
          );
    } catch (e, st) {
      debugPrint('[WaveformWidget] load failed for ${widget.path}: $e\n$st');
      data = WaveformEnvelopeService.instance.proceduralFallback(
        widget.path,
        samples: 300,
      );
      _loadError = e.toString();
    }

    if (data.isEmpty) {
      data = WaveformEnvelopeService.instance.proceduralFallback(
        widget.path,
        samples: 300,
      );
    }

    if (!mounted) return;

    final preview = _proceduralPreview();
    final unchanged = _listEquals(data, preview) || _listEquals(data, _waveformData);
    if (unchanged && _usingProceduralPreview) {
      _isExtracting = false;
      return;
    }

    setState(() {
      _waveformData = data;
      _usingProceduralPreview = false;
      _isExtracting = false;
    });
  }

  bool _listEquals(List<double> a, List<double> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
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

        if (_waveformData.isEmpty) {
          return SizedBox(
            height: height,
            child: Center(
              child: TextButton(
                onPressed: _loadWaveform,
                child: Text(
                  _loadError == null ? 'Load waveform' : 'Retry waveform',
                  style: TextStyle(
                    color: SettingsService.instance.rawAccent,
                    fontSize: 11,
                  ),
                ),
              ),
            ),
          );
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
                            playedColor: SettingsService.instance
                                .resolveNowPlayingAccent(item: widget.item),
                            bpm: _extractBpm(widget.item),
                            displayMode: widget.displayMode,
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
                            color: SettingsService.instance
                                .resolveNowPlayingAccent(item: widget.item),
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
  final double? bpm;
  final WaveformDisplayMode displayMode;

  PreciseWaveformPainter({
    required this.waveformData,
    required this.progress,
    required this.timeSeconds,
    required this.playedColor,
    this.bpm,
    this.displayMode = WaveformDisplayMode.standard,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (waveformData.isEmpty) return;

    final width = size.width;
    final height = size.height;
    if (width <= 1 || height <= 1 || !width.isFinite || !height.isFinite) {
      return;
    }
    final centerY = height / 2;
    final shipScale = switch (displayMode) {
      WaveformDisplayMode.compact => NowPlayingLayoutMetrics.shipFillCompact,
      WaveformDisplayMode.calm => NowPlayingLayoutMetrics.shipFillCalm,
      WaveformDisplayMode.standard => NowPlayingLayoutMetrics.shipFillStandard,
    };
    final shipLen = height * shipScale;
    final metrics = TorchPlumeEngine.engineMetrics(shipLen);
    final budget = displayMode == WaveformDisplayMode.calm
        ? TorchEffectBudget.resolve(profile: TorchContentProfile.audiobook)
        : TorchEffectBudget.resolveForWaveform();
    final blendScale = TorchPlumeEngine.waveformBlendScale *
        (displayMode == WaveformDisplayMode.calm
            ? 0.50
            : displayMode == WaveformDisplayMode.compact
                ? 0.72
                : 1.0);
    final drawDiamonds = displayMode == WaveformDisplayMode.standard;

    final beatStrength = PlaybackMotion.beatDrive(timeSeconds, bpm);
    final waveformAmplitude = TorchPlumeEngine.computeWaveformDrive(
      waveformData: waveformData,
      progress: progress,
      beatStrength: beatStrength,
    );
    final thrust = waveformAmplitude;

    final cursorX = (progress * width).clamp(0.0, width);
    final nozzleX =
        (cursorX - metrics.engineFaceOffset).clamp(0.0, width);

    final path = TorchPlumeEngine.buildExhaustWaveformPath(
      waveformData: waveformData,
      width: width,
      height: height,
      centerY: centerY,
      nozzleX: nozzleX,
      shipLen: shipLen,
    );

    final transitionWidth = shipLen * (0.55 + 0.85 * waveformAmplitude);
    final gradStartX = nozzleX.clamp(0.0, width);
    final gradEndX = max(
      0.0,
      min(gradStartX - max(1.0, transitionWidth), width),
    );
    final glowIntensity = (0.22 + 0.78 * waveformAmplitude) *
        (displayMode == WaveformDisplayMode.calm ? 0.55 : 1.0);

    final core = TorchPlumeEngine.raptorCore(playedColor);
    final sheath = TorchPlumeEngine.raptorSheath(playedColor);

    // --- Exhaust plume + waveform ribbon (played region) ---
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, nozzleX + 3, height));

    TorchPlumeEngine.paintHorizontalPlume(
      canvas: canvas,
      nozzleX: nozzleX,
      centerY: centerY,
      height: height,
      shipLen: shipLen,
      baseColor: playedColor,
      animTimeSeconds: timeSeconds,
      beatStrength: beatStrength,
      waveformAmplitude: waveformAmplitude,
      budget: budget,
      drawDiamonds: false,
      blendScale: blendScale,
    );

    final mainShader = ui.Gradient.linear(
      Offset(gradStartX, centerY),
      Offset(gradEndX, centerY),
      TorchPlumeEngine.exhaustWaveformGradientColors(
        playedColor,
        waveformAmplitude: waveformAmplitude,
      ),
      TorchPlumeEngine.exhaustWaveformGradientStops,
      TileMode.clamp,
    );

    canvas.drawPath(
      path,
      Paint()
        ..shader = mainShader
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = playedColor.withValues(
          alpha: (0.08 + 0.10 * waveformAmplitude).clamp(0.0, 1.0),
        )
        ..style = PaintingStyle.fill,
    );

    final glowShader = ui.Gradient.linear(
      Offset(gradStartX, centerY),
      Offset((nozzleX - transitionWidth * 0.55).clamp(0.0, width), centerY),
      [
        core.withValues(alpha: (0.52 * glowIntensity).clamp(0.0, 1.0)),
        sheath.withValues(alpha: (0.28 * glowIntensity).clamp(0.0, 1.0)),
        Colors.transparent,
      ],
      const [0.0, 0.32, 1.0],
    );

    canvas.drawPath(
      path,
      Paint()
        ..shader = glowShader
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10.0)
        ..blendMode = BlendMode.screen,
    );

    canvas.drawPath(
      path,
      Paint()
        ..shader = glowShader
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5)
        ..blendMode = BlendMode.plus,
    );

    // Nozzle bloom — bridges plume core into the ribbon throat.
    final bloomR = metrics.bellHalfW * (1.05 + 0.25 * thrust);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(nozzleX, centerY),
        width: bloomR * 2.2,
        height: metrics.throatHalfW * 2.8 * (0.85 + 0.15 * thrust),
      ),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(nozzleX, centerY),
          bloomR,
          [
            core.withValues(alpha: (0.55 * glowIntensity).clamp(0.0, 1.0)),
            sheath.withValues(alpha: (0.22 * glowIntensity).clamp(0.0, 1.0)),
            Colors.transparent,
          ],
          const [0.0, 0.48, 1.0],
        )
        ..blendMode = BlendMode.plus
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0),
    );

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = core.withValues(
          alpha: (0.10 + 0.14 * waveformAmplitude).clamp(0.0, 1.0),
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8),
    );

    canvas.restore();

    if (drawDiamonds) {
      TorchPlumeEngine.paintHorizontalPlumeDiamonds(
        canvas: canvas,
        nozzleX: nozzleX,
        centerY: centerY,
        height: height,
        shipLen: shipLen,
        baseColor: playedColor,
        animTimeSeconds: timeSeconds,
        beatStrength: beatStrength,
        waveformAmplitude: waveformAmplitude,
        budget: budget,
        blendScale: blendScale,
      );
    }

    final pitch = 0.010 * thrust;
    final bob = PlaybackMotion.shipBobOffset(timeSeconds, height, thrust);
    final shipSize = Size(shipLen, shipLen);

    canvas.save();
    canvas.translate(cursorX, centerY + bob);
    canvas.rotate(pi / 2 + pitch);
    TorchShipPainter(
      height: shipLen,
      progress: progress,
      playbackTimeSeconds: timeSeconds,
      animTimeSeconds: timeSeconds,
      color: playedColor,
      bpm: bpm,
      drawPlume: false,
      thrustLevel: thrust,
      pitchRadians: pitch,
      budget: budget,
    ).paint(canvas, shipSize);
    canvas.restore();

    // --- Engine throat on bell mouth (hull → exhaust hand-off) ---
    TorchPlumeEngine.paintEngineThroat(
      canvas: canvas,
      nozzleX: nozzleX,
      centerY: centerY,
      shipLen: shipLen,
      baseColor: playedColor,
      seekPulse: 0,
      budget: budget,
      beatStrength: beatStrength,
      waveformAmplitude: waveformAmplitude,
      blendScale: blendScale,
    );

  }

  @override
  bool shouldRepaint(covariant PreciseWaveformPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      timeSeconds != oldDelegate.timeSeconds ||
      playedColor != oldDelegate.playedColor ||
      waveformData != oldDelegate.waveformData ||
      bpm != oldDelegate.bpm ||
      displayMode != oldDelegate.displayMode;
}
