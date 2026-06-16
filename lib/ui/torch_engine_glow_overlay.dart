import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/player_controller.dart';
import '../services/settings_service.dart';
import 'torch_plume_engine.dart';

/// Soft engine-light bleed from the torch ship into the deep-space backdrop.
class TorchEngineGlowOverlay extends StatefulWidget {
  final PlayerController ctrl;

  const TorchEngineGlowOverlay({required this.ctrl, super.key});

  @override
  State<TorchEngineGlowOverlay> createState() => _TorchEngineGlowOverlayState();
}

class _TorchEngineGlowOverlayState extends State<TorchEngineGlowOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _animTime = ValueNotifier<double>(0.0);
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
    _animTime.dispose();
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
      _animTime.value = _animSeconds;
    }
  }

  @override
  Widget build(BuildContext context) {
    _maybeStartTicker();

    final settings = SettingsService.instance;
    if (!settings.expensiveEffectsEnabled) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<Duration>(
      stream: widget.ctrl.player.positionStream,
      builder: (context, posSnap) {
        final pos = posSnap.data ?? Duration.zero;
        final dur = widget.ctrl.player.duration;
        if (dur == null || dur.inMilliseconds <= 0) {
          return const SizedBox.shrink();
        }

        final progress =
            (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0);
        final playbackSeconds = pos.inMilliseconds / 1000.0;
        final item = widget.ctrl.currentMediaItem;
        final rawBpm = item?.extras?['bpm'];
        final bpm = rawBpm is num && rawBpm > 0 ? rawBpm.toDouble() : null;

        final accent = settings.resolveNowPlayingAccent(item: item);
        final budget = TorchEffectBudget.resolve(
          profile: TorchContentProfile.music,
        );

        return RepaintBoundary(
          child: CustomPaint(
            painter: _TorchEngineGlowPainter(
              progress: progress,
              animTime: _animTime,
              playbackTimeSeconds: playbackSeconds,
              accent: accent,
              bpm: bpm,
              budget: budget,
              isPlaying: widget.ctrl.player.playing,
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}

class _TorchEngineGlowPainter extends CustomPainter {
  final double progress;
  final ValueNotifier<double> animTime;
  final double playbackTimeSeconds;
  final Color accent;
  final double? bpm;
  final TorchEffectBudget budget;
  final bool isPlaying;

  _TorchEngineGlowPainter({
    required this.progress,
    required this.animTime,
    required this.playbackTimeSeconds,
    required this.accent,
    required this.bpm,
    required this.budget,
    required this.isPlaying,
  }) : super(repaint: animTime);

  @override
  void paint(Canvas canvas, Size size) {
    if (budget.tier == TorchEffectTier.minimal || size.isEmpty) return;

    final animTimeSeconds = animTime.value;
    final beatStrength =
        TorchPlumeEngine.beatStrength(playbackTimeSeconds, bpm);
    final flicker = TorchPlumeEngine.flicker(
      animTimeSeconds: animTimeSeconds,
      beatStrength: beatStrength,
      beatWeight: 0.12,
    );

    final anchorX = progress * size.width;
    final anchorY = size.height * 0.56;
    final radius = max(size.shortestSide * 0.42 * budget.glowAlphaMul, 1.0);
    final warm = TorchPlumeEngine.warmExhaust(accent);
    final playMul = isPlaying ? 1.0 : 0.35;
    final intensity =
        (0.22 + 0.38 * beatStrength) * flicker * playMul * budget.glowAlphaMul;

    final shader = ui.Gradient.radial(
      Offset(anchorX, anchorY),
      radius,
      [
        (Color.lerp(Colors.white, warm, 0.35) ?? warm)
            .withValues(alpha: (0.16 * intensity).clamp(0.0, 0.24)),
        Colors.transparent,
      ],
    );

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = shader
        ..blendMode = BlendMode.plus,
    );

    final streakLen = max(size.width * 0.18 * budget.plumeLengthMul, 1.0);
    final streakShader = ui.Gradient.linear(
      Offset(anchorX, anchorY),
      Offset(max(0.0, anchorX - streakLen), anchorY),
      [
        Colors.white.withValues(alpha: (0.08 * intensity).clamp(0.0, 0.12)),
        Colors.transparent,
      ],
    );

    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(anchorX - streakLen * 0.35, anchorY),
        width: streakLen,
        height: max(size.height * 0.12, 1.0),
      ),
      Paint()
        ..shader = streakShader
        ..blendMode = BlendMode.plus
        ..maskFilter = budget.outerBlur > 0
            ? MaskFilter.blur(BlurStyle.normal, budget.outerBlur)
            : null,
    );
  }

  @override
  bool shouldRepaint(covariant _TorchEngineGlowPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      playbackTimeSeconds != oldDelegate.playbackTimeSeconds ||
      accent != oldDelegate.accent ||
      bpm != oldDelegate.bpm ||
      budget != oldDelegate.budget ||
      isPlaying != oldDelegate.isPlaying;
}