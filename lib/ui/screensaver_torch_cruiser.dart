import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/service_locator.dart';
import '../services/settings_service.dart';
import 'rocinante_ship_painter.dart';
import 'torch_plume_engine.dart';

/// A small torch ship cruising across the screensaver starfield.
class ScreensaverTorchCruiser extends StatefulWidget {
  const ScreensaverTorchCruiser({super.key});

  @override
  State<ScreensaverTorchCruiser> createState() =>
      _ScreensaverTorchCruiserState();
}

class _ScreensaverTorchCruiserState extends State<ScreensaverTorchCruiser>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _animSeconds = 0;
  Duration _lastElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeStartTicker();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _maybeStartTicker() {
    final disable =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (disable) {
      if (_ticker.isActive) _ticker.stop();
      return;
    }
    if (!_ticker.isActive) _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;
    if (dt.isFinite && dt > 0) {
      _animSeconds += dt;
      if (_animSeconds > 36000) _animSeconds -= 36000;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    _maybeStartTicker();

    final settings = SettingsService.instance;
    if (!settings.expensiveEffectsEnabled) {
      return const SizedBox.shrink();
    }

    final ctrl = ServiceLocator.instance.playerController;
    final accent = Color(settings.accentColor);
    final budget = TorchEffectBudget.resolve(
      profile: TorchContentProfile.music,
    );

    return StreamBuilder<Duration>(
      stream: ctrl.player.positionStream,
      builder: (context, posSnap) {
        final dur = ctrl.player.duration;
        final pos = posSnap.data;
        double progress;
        double playbackSeconds = 0;

        if (dur != null &&
            dur.inMilliseconds > 0 &&
            pos != null &&
            ctrl.player.playing) {
          progress = pos.inMilliseconds / dur.inMilliseconds;
          playbackSeconds = pos.inMilliseconds / 1000.0;
        } else {
          progress = (_animSeconds * 0.012) % 1.0;
        }

        final item = ctrl.currentMediaItem;
        final rawBpm = item?.extras?['bpm'];
        final bpm = rawBpm is num && rawBpm > 0 ? rawBpm.toDouble() : null;

        return LayoutBuilder(
          builder: (context, constraints) {
            return CustomPaint(
              size: Size(constraints.maxWidth, constraints.maxHeight),
              painter: _ScreensaverTorchPainter(
                progress: progress.clamp(0.05, 0.95),
                animTimeSeconds: _animSeconds,
                playbackTimeSeconds: playbackSeconds,
                accent: accent,
                bpm: bpm,
                budget: budget,
              ),
            );
          },
        );
      },
    );
  }
}

class _ScreensaverTorchPainter extends CustomPainter {
  final double progress;
  final double animTimeSeconds;
  final double playbackTimeSeconds;
  final Color accent;
  final double? bpm;
  final TorchEffectBudget budget;

  const _ScreensaverTorchPainter({
    required this.progress,
    required this.animTimeSeconds,
    required this.playbackTimeSeconds,
    required this.accent,
    required this.bpm,
    required this.budget,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (budget.tier == TorchEffectTier.minimal) return;

    final shipH = (size.height * 0.055).clamp(26.0, 48.0);
    final centerY = size.height * 0.40;
    // Stern anchored to the progress point (same convention as the waveform
    // ship) so the hull rides ahead of the trail and leaves the frame stern-last.
    final centerX = progress * size.width + shipH * 0.45;
    final beatStrength =
        TorchPlumeEngine.beatStrength(playbackTimeSeconds, bpm);

    final nozzleX = (centerX - shipH * 0.45).clamp(0.0, size.width);
    final amp = 0.55 + 0.25 * beatStrength;

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, nozzleX + 1, size.height));
    TorchPlumeEngine.paintHorizontalPlume(
      canvas: canvas,
      nozzleX: nozzleX,
      centerY: centerY,
      height: shipH * 1.15,
      shipLen: shipH,
      baseColor: accent,
      animTimeSeconds: animTimeSeconds,
      beatStrength: beatStrength,
      waveformAmplitude: amp,
      budget: budget,
    );
    canvas.restore();

    canvas.save();
    canvas.translate(centerX, centerY);
    canvas.rotate(pi / 2);
    RocinanteShipPainter(
      shipLen: shipH,
      color: accent,
      timeSeconds: animTimeSeconds,
      beatStrength: beatStrength,
      drawPlume: false,
    ).paint(canvas, Size(shipH, shipH));
    canvas.restore();

    TorchPlumeEngine.paintEngineThroat(
      canvas: canvas,
      nozzleX: nozzleX,
      centerY: centerY,
      shipLen: shipH,
      baseColor: accent,
      seekPulse: 0,
      budget: budget,
      beatStrength: beatStrength,
      waveformAmplitude: amp,
    );
  }

  @override
  bool shouldRepaint(covariant _ScreensaverTorchPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      animTimeSeconds != oldDelegate.animTimeSeconds ||
      playbackTimeSeconds != oldDelegate.playbackTimeSeconds ||
      accent != oldDelegate.accent ||
      bpm != oldDelegate.bpm ||
      budget != oldDelegate.budget;
}