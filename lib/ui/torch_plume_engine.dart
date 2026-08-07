import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../services/settings_service.dart';
import '../utils/content_mode.dart';

/// Rendering quality for torch ship / plume effects.
enum TorchEffectTier {
  full,
  reduced,
  minimal,
}

/// Visual profile tuned for music vs audiobook content.
enum TorchContentProfile {
  music,
  audiobook,
}

/// Adaptive budget for blur layers, diamonds, and plume intensity.
class TorchEffectBudget {
  final TorchEffectTier tier;
  final TorchContentProfile profile;

  final double plumeLengthMul;
  final double plumeAlphaMul;
  final double glowAlphaMul;
  final int diamondCount;
  final double outerBlur;
  final double innerBlur;
  final double coreBlur;
  final double nozzleBlur;
  final bool drawOuterHalo;
  final bool drawTurbulence;
  final bool drawSecondGlow;
  final bool drawSideIons;

  const TorchEffectBudget({
    required this.tier,
    required this.profile,
    required this.plumeLengthMul,
    required this.plumeAlphaMul,
    required this.glowAlphaMul,
    required this.diamondCount,
    required this.outerBlur,
    required this.innerBlur,
    required this.coreBlur,
    required this.nozzleBlur,
    required this.drawOuterHalo,
    required this.drawTurbulence,
    required this.drawSecondGlow,
    required this.drawSideIons,
  });

  /// Torch ship on the Now Playing waveform always uses music visuals.
  factory TorchEffectBudget.resolveForWaveform({SettingsService? settings}) {
    final budget = TorchEffectBudget.resolve(
      profile: TorchContentProfile.music,
      settings: settings,
    );
    if (budget.tier != TorchEffectTier.minimal) return budget;

    return const TorchEffectBudget(
      tier: TorchEffectTier.reduced,
      profile: TorchContentProfile.music,
      plumeLengthMul: 0.82,
      plumeAlphaMul: 0.78,
      glowAlphaMul: 0.72,
      diamondCount: 5,
      outerBlur: 8.0,
      innerBlur: 3.5,
      coreBlur: 2.0,
      nozzleBlur: 4.5,
      drawOuterHalo: true,
      drawTurbulence: false,
      drawSecondGlow: false,
      drawSideIons: false,
    );
  }

  factory TorchEffectBudget.resolve({
    required TorchContentProfile profile,
    SettingsService? settings,
  }) {
    final s = settings ?? SettingsService.instance;
    final tier = !s.expensiveEffectsEnabled
        ? TorchEffectTier.minimal
        : (s.effectiveHighQualityBlur
            ? TorchEffectTier.full
            : TorchEffectTier.reduced);

    final isAudiobook = profile == TorchContentProfile.audiobook;

    return switch (tier) {
      TorchEffectTier.full => TorchEffectBudget(
          tier: tier,
          profile: profile,
          plumeLengthMul: isAudiobook ? 0.62 : 1.0,
          plumeAlphaMul: isAudiobook ? 0.55 : 1.0,
          glowAlphaMul: isAudiobook ? 0.50 : 1.0,
          diamondCount: isAudiobook ? 0 : 8,
          outerBlur: isAudiobook ? 10.0 : 14.0,
          innerBlur: isAudiobook ? 5.0 : 6.0,
          coreBlur: isAudiobook ? 3.0 : 4.0,
          nozzleBlur: isAudiobook ? 6.0 : 8.0,
          drawOuterHalo: !isAudiobook,
          drawTurbulence: !isAudiobook,
          drawSecondGlow: true,
          drawSideIons: true,
        ),
      TorchEffectTier.reduced => TorchEffectBudget(
          tier: tier,
          profile: profile,
          plumeLengthMul: isAudiobook ? 0.55 : 0.88,
          plumeAlphaMul: isAudiobook ? 0.48 : 0.82,
          glowAlphaMul: isAudiobook ? 0.42 : 0.72,
          diamondCount: isAudiobook ? 0 : 3,
          outerBlur: 9.0,
          innerBlur: 4.0,
          coreBlur: 2.5,
          nozzleBlur: 5.0,
          drawOuterHalo: !isAudiobook,
          drawTurbulence: false,
          drawSecondGlow: false,
          drawSideIons: true,
        ),
      TorchEffectTier.minimal => TorchEffectBudget(
          tier: tier,
          profile: profile,
          plumeLengthMul: isAudiobook ? 0.48 : 0.72,
          plumeAlphaMul: isAudiobook ? 0.40 : 0.65,
          glowAlphaMul: isAudiobook ? 0.35 : 0.55,
          diamondCount: 0,
          outerBlur: 0.0,
          innerBlur: 0.0,
          coreBlur: 0.0,
          nozzleBlur: 0.0,
          drawOuterHalo: false,
          drawTurbulence: false,
          drawSecondGlow: false,
          drawSideIons: false,
        ),
    };
  }

  static TorchContentProfile profileFor(ContentMode mode) {
    return mode == ContentMode.audiobook
        ? TorchContentProfile.audiobook
        : TorchContentProfile.music;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TorchEffectBudget &&
          tier == other.tier &&
          profile == other.profile;

  @override
  int get hashCode => Object.hash(tier, profile);
}

/// Shared torch-drive plume path builder and painters.
class TorchPlumeEngine {
  TorchPlumeEngine._();

  static double beatStrength(double playbackTimeSeconds, double? bpm) {
    final effectiveBpm = (bpm != null && bpm > 0) ? bpm : 120.0;
    final cycle = 60.0 / effectiveBpm;
    final phase = (playbackTimeSeconds % cycle) / cycle;
    return 0.35 + 0.65 * ((cos(2 * pi * phase) + 1.0) / 2.0);
  }

  static double flicker({
    required double animTimeSeconds,
    required double beatStrength,
    double beatWeight = 0.08,
    double highFreqWeight = 0.035,
  }) {
    return 1.0 +
        beatWeight * beatStrength +
        highFreqWeight * sin(animTimeSeconds * 22.0) +
        0.02 * cos(animTimeSeconds * 41.0);
  }

  static double wobble(double animTimeSeconds) {
    return 1.0 +
        0.045 * sin(animTimeSeconds * 9.0) +
        0.03 * sin(animTimeSeconds * 15.0 + 0.9);
  }

  static Color warmExhaust(Color base) =>
      Color.lerp(const Color(0xFFFFF3E0), base, 0.55) ?? base;

  static Color ionCool(Color base) =>
      Color.lerp(const Color(0xFF80D8FF), base, 0.42) ?? base;

  /// Methane Raptor palette — white core, pale blue sheath, faint fringe.
  static const Color _raptorSheath = Color(0xFFB3E5FC);
  static const Color _raptorSheathDeep = Color(0xFF90CAF9);
  static const Color _raptorFringe = Color(0xFFE1F5FE);

  static Color raptorCore(Color base) =>
      Color.lerp(Colors.white, base, 0.08) ?? Colors.white;

  static Color raptorSheath(Color base) =>
      Color.lerp(_raptorSheath, base, 0.12) ?? _raptorSheath;

  static Color raptorSheathDeep(Color base) =>
      Color.lerp(_raptorSheathDeep, base, 0.10) ?? _raptorSheathDeep;

  static Color raptorFringe(Color base) =>
      Color.lerp(_raptorFringe, base, 0.06) ?? _raptorFringe;

  /// Triple Raptor cluster offsets (Starship V3 engine row).
  static List<({double offset, double scale})> raptorCluster(double bellHalfW) => [
        (offset: -bellHalfW * 0.72, scale: 0.58),
        (offset: 0.0, scale: 1.0),
        (offset: bellHalfW * 0.72, scale: 0.58),
      ];

  /// Twin Epstein drive cluster offsets (Rocinante stern cowl).
  static List<({double offset, double scale})> rocinanteCluster(double bellHalfW) => [
        (offset: -bellHalfW * 0.48, scale: 0.55),
        (offset: bellHalfW * 0.48, scale: 0.55),
      ];

  /// Center-dominant Epstein cluster (Epstein torch cruiser).
  /// One large main bell flanked by two smaller bells peeking past its sides.
  static List<({double offset, double scale})> epsteinCluster(double bellHalfW) => [
        (offset: 0.0, scale: 1.0),
        (offset: -bellHalfW * 0.95, scale: 0.50),
        (offset: bellHalfW * 0.95, scale: 0.50),
      ];

  /// Faithful Rocinante drive: a single large center Epstein bell.
  /// The Roci's propulsion is one main drive cone, not a cluster.
  static List<({double offset, double scale})> rociDriveCluster(double bellHalfW) => [
        (offset: 0.0, scale: 1.0),
      ];

  static double _raptorWobble(double animTimeSeconds) =>
      1.0 +
      0.012 * sin(animTimeSeconds * 9.0) +
      0.008 * sin(animTimeSeconds * 15.0 + 0.9);

  /// Softens torch layers when painted inside the Now Playing waveform.
  static const double waveformBlendScale = 0.58;

  /// Shared exhaust geometry scale (plume width, throat glow, bell mouth).
  static const double raptorExhaustSizeMul = 1.14;

  /// Vertical pinch at the nozzle — waveform exits the bell at engine width.
  static const double waveformThroatScale = 0.10;

  /// Exhaust-aligned gradient stops for waveform fill (matches Raptor plume).
  static List<Color> exhaustWaveformGradientColors(
    Color base, {
    double waveformAmplitude = 0.5,
  }) {
    final amp = waveformAmplitude.clamp(0.0, 1.0);
    return [
      raptorCore(base),
      Color.lerp(raptorCore(base), raptorSheath(base), 0.55)!,
      raptorSheath(base),
      base.withValues(alpha: 0.82 + 0.18 * amp),
    ];
  }

  static const List<double> exhaustWaveformGradientStops = [
    0.0,
    0.08,
    0.26,
    1.0,
  ];

  /// Waveform ribbon path that tapers at the nozzle and expands aft.
  static Path buildExhaustWaveformPath({
    required List<double> waveformData,
    required double width,
    required double height,
    required double centerY,
    required double nozzleX,
    required double shipLen,
    double topMul = 0.88,
    double bottomMul = 0.80,
  }) {
    if (waveformData.isEmpty) return Path();

    final envelope = waveformEnvelopeScales(
      shipLen: shipLen,
      canvasHeight: height,
    );
    final step = width / max(1, waveformData.length - 1);
    final path = Path();

    path.moveTo(0, centerY);
    for (int i = 0; i < waveformData.length; i++) {
      final x = i * step;
      final expansion = waveformExpansionScale(
        x: x,
        nozzleX: nozzleX,
        shipLen: shipLen,
      );
      final ampH =
          waveformData[i] * height * envelope.top * topMul * expansion;
      path.lineTo(x, centerY - ampH / 2);
    }
    for (int i = waveformData.length - 1; i >= 0; i--) {
      final x = i * step;
      final expansion = waveformExpansionScale(
        x: x,
        nozzleX: nozzleX,
        shipLen: shipLen,
      );
      final ampH =
          waveformData[i] * height * envelope.bottom * bottomMul * expansion;
      path.lineTo(x, centerY + ampH / 2);
    }
    path.close();
    return path;
  }

  /// Ribbon height multipliers aligned to triple-Raptor cluster span.
  static ({double top, double bottom}) waveformEnvelopeScales({
    required double shipLen,
    required double canvasHeight,
  }) {
    final clusterHalf = engineMetrics(shipLen).bellHalfW * 1.30;
    final top = (clusterHalf * 2.75 / canvasHeight).clamp(0.48, 0.88);
    final bottom = (clusterHalf * 2.45 / canvasHeight).clamp(0.42, 0.80);
    return (top: top, bottom: bottom);
  }

  /// Vertical scale along the exhaust axis — narrow at the nozzle, expanding aft.
  static double waveformExpansionScale({
    required double x,
    required double nozzleX,
    required double shipLen,
  }) {
    final dist = (nozzleX - x).clamp(0.0, nozzleX);
    final throatDist = shipLen * 0.35;
    const throatExit = 0.40;
    final expandDist = shipLen * 0.92;

    if (dist <= throatDist) {
      final t = dist / throatDist;
      return waveformThroatScale + (throatExit - waveformThroatScale) * t;
    }

    final beyond = dist - throatDist;
    if (beyond < expandDist) {
      final t = beyond / expandDist;
      final eased = t * t * (3.0 - 2.0 * t);
      return throatExit + (1.0 - throatExit) * eased;
    }
    return 1.0;
  }

  /// Engine bell / throat proportions shared with [TorchShipPainter].
  static ({
    double shipWidth,
    double bellHalfW,
    double throatHalfW,
    double engineFaceOffset,
  }) engineMetrics(double shipLen) {
    final shipWidth = shipLen * 0.25;
    final bellHalfW = shipWidth * 0.45 * raptorExhaustSizeMul;
    return (
      shipWidth: shipWidth,
      bellHalfW: bellHalfW,
      throatHalfW: bellHalfW * 0.44,
      engineFaceOffset: shipLen * 0.50,
    );
  }

  /// Glowing nozzle throat at the engine bell mouth (paint after the hull).
  static void paintEngineThroat({
    required Canvas canvas,
    required double nozzleX,
    required double centerY,
    required double shipLen,
    required Color baseColor,
    required double seekPulse,
    required TorchEffectBudget budget,
    double beatStrength = 0.5,
    double waveformAmplitude = 0.5,
    bool vertical = false,
    double blendScale = 1.0,
    List<({double offset, double scale})>? cluster,
  }) {
    if (budget.tier == TorchEffectTier.minimal) return;

    final metrics = engineMetrics(shipLen);
    final pulse =
        (1.0 + 0.38 * seekPulse.clamp(0.0, 1.0)) *
        (0.75 + 0.25 * beatStrength) *
        budget.glowAlphaMul *
        blendScale;
    final amp =
        (0.45 + 0.55 * waveformAmplitude) * budget.plumeAlphaMul * blendScale;

    for (final engine in (cluster ?? raptorCluster(metrics.bellHalfW))) {
      _paintSingleEngineThroat(
        canvas: canvas,
        nozzleX: nozzleX,
        centerY: centerY,
        engineOffset: engine.offset,
        engineScale: engine.scale,
        metrics: metrics,
        baseColor: baseColor,
        pulse: pulse,
        amp: amp,
        shipLen: shipLen,
        budget: budget,
        vertical: vertical,
      );
    }
  }

  static void _paintSingleEngineThroat({
    required Canvas canvas,
    required double nozzleX,
    required double centerY,
    required double engineOffset,
    required double engineScale,
    required ({
      double shipWidth,
      double bellHalfW,
      double throatHalfW,
      double engineFaceOffset,
    }) metrics,
    required Color baseColor,
    required double pulse,
    required double amp,
    required double shipLen,
    required TorchEffectBudget budget,
    required bool vertical,
  }) {
    final core = raptorCore(baseColor);
    final sheath = raptorSheath(baseColor);
    final sheathDeep = raptorSheathDeep(baseColor);
    final bellHalfW = metrics.bellHalfW * engineScale;
    final throatHalfW = metrics.throatHalfW * engineScale;
    final depth = shipLen * 0.11;
    final axisPos = centerY + engineOffset;

    if (vertical) {
      final baseY = axisPos;
      final innerY = baseY - depth;

      final ductPath = Path()
        ..moveTo(-bellHalfW, baseY)
        ..lineTo(-throatHalfW, innerY)
        ..lineTo(throatHalfW, innerY)
        ..lineTo(bellHalfW, baseY)
        ..close();

      canvas.drawPath(
        ductPath,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, innerY),
            Offset(0, baseY),
            [
              sheathDeep.withValues(alpha: (0.16 * pulse * amp).clamp(0.0, 1.0)),
              core.withValues(alpha: (0.58 * pulse * amp).clamp(0.0, 1.0)),
              sheath.withValues(alpha: (0.24 * pulse * amp).clamp(0.0, 1.0)),
            ],
            [0.0, 0.62, 1.0],
          )
          ..blendMode = BlendMode.plus
          ..maskFilter = budget.coreBlur > 0
              ? MaskFilter.blur(BlurStyle.normal, budget.coreBlur)
              : null,
      );

      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(0, baseY),
          width: bellHalfW * 2.0,
          height: throatHalfW * 2.7,
        ),
        Paint()
          ..shader = ui.Gradient.radial(
            Offset(0, baseY + throatHalfW * 0.08),
            bellHalfW * 1.08,
            [
              core.withValues(alpha: (0.82 * pulse * amp).clamp(0.0, 1.0)),
              sheath.withValues(alpha: (0.38 * pulse * amp).clamp(0.0, 1.0)),
              Colors.transparent,
            ],
            [0.0, 0.55, 1.0],
          )
          ..blendMode = BlendMode.plus
          ..maskFilter = budget.nozzleBlur > 0
              ? MaskFilter.blur(BlurStyle.normal, budget.nozzleBlur * 0.65)
              : null,
      );
      return;
    }

    final innerX = nozzleX + depth;
    final ductPath = Path()
      ..moveTo(nozzleX, axisPos - bellHalfW)
      ..lineTo(innerX, axisPos - throatHalfW)
      ..lineTo(innerX, axisPos + throatHalfW)
      ..lineTo(nozzleX, axisPos + bellHalfW)
      ..close();

    canvas.drawPath(
      ductPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(innerX, axisPos),
          Offset(nozzleX, axisPos),
          [
            sheathDeep.withValues(alpha: (0.16 * pulse * amp).clamp(0.0, 1.0)),
            core.withValues(alpha: (0.58 * pulse * amp).clamp(0.0, 1.0)),
            sheath.withValues(alpha: (0.24 * pulse * amp).clamp(0.0, 1.0)),
          ],
          [0.0, 0.62, 1.0],
        )
        ..blendMode = BlendMode.plus
        ..maskFilter = budget.coreBlur > 0
            ? MaskFilter.blur(BlurStyle.normal, budget.coreBlur)
            : null,
    );

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(nozzleX, axisPos),
        width: bellHalfW * 2.0,
        height: throatHalfW * 2.7,
      ),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(nozzleX - throatHalfW * 0.08, axisPos),
          bellHalfW * 1.08,
          [
            core.withValues(alpha: (0.82 * pulse * amp).clamp(0.0, 1.0)),
            sheath.withValues(alpha: (0.38 * pulse * amp).clamp(0.0, 1.0)),
            Colors.transparent,
          ],
          [0.0, 0.55, 1.0],
        )
        ..blendMode = BlendMode.plus
        ..maskFilter = budget.nozzleBlur > 0
            ? MaskFilter.blur(BlurStyle.normal, budget.nozzleBlur * 0.65)
            : null,
    );

    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(nozzleX, axisPos),
        width: throatHalfW * 1.55,
        height: throatHalfW * 0.42 * pulse,
      ),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(nozzleX, axisPos),
          Offset(nozzleX - bellHalfW * 0.35, axisPos),
          [
            core.withValues(alpha: (0.68 * pulse * amp).clamp(0.0, 1.0)),
            core.withValues(alpha: 0.0),
          ],
        )
        ..blendMode = BlendMode.plus,
    );
  }

  /// @deprecated Use [paintEngineThroat]. Kept for call-site compatibility.
  static void paintNozzleBridge({
    required Canvas canvas,
    required double nozzleX,
    required double shipX,
    required double centerY,
    required double height,
    required Color baseColor,
    required double seekPulse,
    required TorchEffectBudget budget,
  }) {
    paintEngineThroat(
      canvas: canvas,
      nozzleX: nozzleX,
      centerY: centerY,
      shipLen: height * 0.8,
      baseColor: baseColor,
      seekPulse: seekPulse,
      budget: budget,
    );
  }

  /// Faint trajectory for the unplayed portion of the track.
  static void paintFlightCorridor({
    required Canvas canvas,
    required Path path,
    required Color unplayedColor,
    required TorchEffectBudget budget,
  }) {
    if (budget.tier == TorchEffectTier.minimal) return;

    canvas.drawPath(
      path,
      Paint()
        ..color = unplayedColor.withValues(alpha: 0.06)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = unplayedColor.withValues(alpha: 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.85,
    );
  }

  /// White heat-haze shimmer across the played waveform ribbon (legacy
  /// turbulence layer). Gated by [TorchEffectBudget.drawTurbulence] so music
  /// tiers get the shimmer while calm audiobook scrubbers stay clean.
  static void paintWaveformTurbulence({
    required Canvas canvas,
    required Path path,
    required double nozzleX,
    required double transitionWidth,
    required double waveformAmplitude,
    required TorchEffectBudget budget,
  }) {
    if (!budget.drawTurbulence || budget.tier == TorchEffectTier.minimal) {
      return;
    }
    final alpha = (0.10 * waveformAmplitude.clamp(0.0, 1.0)).clamp(0.0, 1.0);
    if (alpha <= 0.001) return;

    final startX = nozzleX.clamp(0.0, 1e9);
    final endX = max(0.0, startX - transitionWidth);
    if (endX >= startX) return;

    final shader = ui.Gradient.linear(
      Offset(startX, 0),
      Offset(endX, 0),
      [
        Colors.white.withValues(alpha: 0.0),
        Colors.white.withValues(alpha: alpha),
        Colors.white.withValues(alpha: 0.0),
      ],
      const [0.0, 0.5, 1.0],
      TileMode.repeated,
    );

    canvas.drawPath(
      path,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.fill
        ..blendMode = BlendMode.overlay,
    );
  }

  /// Playhead-local drive signal for waveform + plume reactivity (Now Playing).
  static double computeWaveformDrive({
    required List<double> waveformData,
    required double progress,
    required double beatStrength,
    int windowRadius = 10,
  }) {
    if (waveformData.isEmpty) {
      return (0.38 + 0.42 * beatStrength).clamp(0.38, 1.0);
    }

    final cursorIdx = (progress * (waveformData.length - 1))
        .round()
        .clamp(0, waveformData.length - 1);
    final windowStart = max(0, cursorIdx - windowRadius);
    final windowEnd = min(waveformData.length - 1, cursorIdx + 2);

    var peak = 0.0;
    var mean = 0.0;
    var count = 0;
    for (int i = windowStart; i <= windowEnd; i++) {
      final sample = waveformData[i];
      peak = max(peak, sample);
      mean += sample;
      count++;
    }
    mean = count > 0 ? mean / count : peak;

    final local = (waveformData[cursorIdx] * 0.45 + peak * 0.35 + mean * 0.20)
        .clamp(0.0, 1.0);
    final shaped = sqrt(local);
    return (0.34 + 0.48 * shaped + 0.18 * beatStrength).clamp(0.38, 1.0);
  }

  /// Waveform-driven Mach diamond visibility (Now Playing).
  static double diamondProminence(double waveformAmplitude) =>
      (0.72 + 0.28 * waveformAmplitude.clamp(0.0, 1.0)).clamp(0.72, 1.0);

  static int resolveActiveDiamondCount({
    required int diamondCount,
    required double waveformAmplitude,
    required double engineScale,
  }) {
    if (diamondCount <= 0) return 0;
    final engineCap = engineScale >= 0.95
        ? diamondCount
        : max(2, (diamondCount * 0.62).round());
    return max(
      2,
      (engineCap * (0.62 + 0.38 * waveformAmplitude.clamp(0.0, 1.0))).round(),
    );
  }

  /// Mach diamond shock disks along the exhaust axis.
  static void paintMachDiamonds({
    required Canvas canvas,
    required double axisX,
    required double axisY,
    required double plumeLen,
    required double throatHalfW,
    required double ampFactor,
    required int diamondCount,
    required double animTimeSeconds,
    required TorchEffectBudget budget,
    double engineScale = 1.0,
    bool horizontal = true,
    double waveformAmplitude = 0.5,
    double blendScale = 1.0,
  }) {
    final activeCount = resolveActiveDiamondCount(
      diamondCount: diamondCount,
      waveformAmplitude: waveformAmplitude,
      engineScale: engineScale,
    );
    if (activeCount <= 0) return;

    final prominence =
        diamondProminence(waveformAmplitude) * blendScale.clamp(0.0, 1.0);
    final sizeMul =
        (1.05 + 0.45 * waveformAmplitude.clamp(0.0, 1.0)) * blendScale;
    final blurSigma = budget.innerBlur > 0
        ? budget.innerBlur *
            (0.34 + 0.28 * (1.0 - waveformAmplitude.clamp(0.0, 1.0)) +
                0.18 * (1.0 - blendScale.clamp(0.0, 1.0)))
        : 0.0;

    final sheathPaint = Paint()
      ..blendMode = blendScale < 0.85 ? BlendMode.screen : BlendMode.plus
      ..maskFilter =
          blurSigma > 0 ? MaskFilter.blur(BlurStyle.normal, blurSigma) : null;
    final corePaint = Paint()
      ..blendMode = blendScale < 0.85 ? BlendMode.screen : BlendMode.plus;

    final scaledThroat = throatHalfW * engineScale;
    for (int i = 1; i <= activeCount; i++) {
      final ratio = i / (activeCount + 1);
      final intensity = prominence *
          (1.0 - ratio * 0.42) *
          ampFactor *
          engineScale;
      final pulse = 0.9 + 0.1 * sin(animTimeSeconds * 9.0 + i * 1.7);
      final wobble = sin(animTimeSeconds * 5.0 + i) * scaledThroat * 0.05;

      late final double x;
      late final double y;
      late final double w;
      late final double h;

      if (horizontal) {
        x = axisX - plumeLen * (0.12 + 0.74 * ratio);
        y = axisY + wobble;
        w = scaledThroat *
            0.58 *
            (1.0 - 0.14 * ratio) *
            pulse *
            sizeMul;
        h = scaledThroat *
            3.1 *
            (1.0 - 0.08 * ratio) *
            (0.92 + 0.08 * sin(animTimeSeconds * 6.5 + i)) *
            sizeMul;
      } else {
        y = axisY + plumeLen * (0.12 + 0.74 * ratio);
        x = axisX + wobble;
        h = scaledThroat *
            0.58 *
            (1.0 - 0.14 * ratio) *
            pulse *
            sizeMul;
        w = scaledThroat *
            3.1 *
            (1.0 - 0.08 * ratio) *
            (0.92 + 0.08 * sin(animTimeSeconds * 6.5 + i)) *
            sizeMul;
      }

      final center = Offset(x, y);
      final outerRect = Rect.fromCenter(center: center, width: w, height: h);
      final innerRect = Rect.fromCenter(
        center: center,
        width: w * 0.52,
        height: h * 0.52,
      );

      sheathPaint.shader = ui.Gradient.radial(
        center,
        max(w, h) * 0.62,
        [
          raptorCore(Colors.white)
              .withValues(alpha: (intensity * 0.82).clamp(0.0, 1.0)),
          raptorSheath(Colors.white)
              .withValues(alpha: (intensity * 0.46).clamp(0.0, 1.0)),
          raptorSheathDeep(Colors.white)
              .withValues(alpha: (intensity * 0.16).clamp(0.0, 1.0)),
          Colors.transparent,
        ],
        [0.0, 0.28, 0.62, 1.0],
      );
      canvas.drawOval(outerRect, sheathPaint);

      corePaint.shader = ui.Gradient.radial(
        center,
        min(w, h) * 0.42,
        [
          Colors.white.withValues(alpha: (intensity * 0.72).clamp(0.0, 1.0)),
          Colors.white.withValues(alpha: (intensity * 0.18).clamp(0.0, 1.0)),
          Colors.transparent,
        ],
        [0.0, 0.45, 1.0],
      );
      canvas.drawOval(innerRect, corePaint);
      
      // --- Visual: Shockdisk Chromatic Aberration (CEO Polish) ---
      if (budget.tier == TorchEffectTier.full && intensity > 0.6) {
        canvas.drawOval(
          innerRect.shift(const Offset(1, 0)),
          Paint()..color = Colors.cyanAccent.withValues(alpha: 0.12 * intensity)..blendMode = BlendMode.plus,
        );
        canvas.drawOval(
          innerRect.shift(const Offset(-1, 0)),
          Paint()..color = Colors.redAccent.withValues(alpha: 0.12 * intensity)..blendMode = BlendMode.plus,
        );
      }
    }
  }

  static Path _buildRaptorPlumePath({
    required double nozzleX,
    required double axisY,
    required double plumeLen,
    required double throatHalfW,
    required double bellHalfW,
    required double exitHalfW,
    required double lenScale,
    required double wobbleVal,
    required double animTimeSeconds,
    required double oscillation,
  }) {
    final len = plumeLen * lenScale;
    final tipX = nozzleX - len;
    final expandX = nozzleX - len * 0.17;
    final midX = nozzleX - len * 0.52;
    final twist = sin(animTimeSeconds * 11.0) * throatHalfW * 0.04;

    final p = Path();
    p.moveTo(nozzleX, axisY - throatHalfW);
    p.cubicTo(
      nozzleX - len * 0.03,
      axisY - throatHalfW * 0.98,
      nozzleX - len * 0.09,
      axisY - bellHalfW * 0.96,
      expandX,
      axisY - bellHalfW * wobbleVal + twist,
    );
    p.cubicTo(
      midX,
      axisY - exitHalfW * 0.82 * wobbleVal,
      tipX + len * 0.22,
      axisY - exitHalfW * 0.28 + twist * 0.25,
      tipX,
      axisY + oscillation,
    );
    p.cubicTo(
      tipX + len * 0.22,
      axisY + exitHalfW * 0.28 - twist * 0.25,
      midX,
      axisY + exitHalfW * 0.82 * wobbleVal,
      expandX,
      axisY + bellHalfW * wobbleVal - twist,
    );
    p.cubicTo(
      nozzleX - len * 0.09,
      axisY + bellHalfW * 0.96,
      nozzleX - len * 0.03,
      axisY + throatHalfW * 0.98,
      nozzleX,
      axisY + throatHalfW,
    );
    p.close();
    return p;
  }

  static void _paintSingleHorizontalRaptor({
    required Canvas canvas,
    required double nozzleX,
    required double axisY,
    required double plumeLen,
    required double throatHalfW,
    required double bellHalfW,
    required double engineScale,
    required Color baseColor,
    required double ampFactor,
    required double animTimeSeconds,
    required double beatStrength,
    required double height,
    required TorchEffectBudget budget,
    required double waveformAmplitude,
    bool drawDiamonds = true,
    double blendScale = 1.0,
    bool waveformTinted = false,
  }) {
    final List<Color>? tinted = waveformTinted
        ? exhaustWaveformGradientColors(
            baseColor,
            waveformAmplitude: waveformAmplitude,
          )
        : null;
    final core = tinted?[0] ?? raptorCore(baseColor);
    final coreMid = tinted?[1] ??
        Color.lerp(raptorCore(baseColor), raptorSheath(baseColor), 0.55)!;
    final sheath = tinted?[2] ?? raptorSheath(baseColor);
    final fringe = tinted?[3] ?? raptorFringe(baseColor);
    final sheathDeep = tinted != null
        ? Color.lerp(sheath, fringe, 0.30)!
        : raptorSheathDeep(baseColor);
    final effectiveAmp =
        ampFactor * blendScale.clamp(0.0, 1.0) * (tinted != null ? 1.45 : 1.0);
    final haloHead = tinted != null ? core : sheath;
    final haloMid = tinted != null ? coreMid : fringe;
    final plumeBlend = blendScale < 0.85 ? BlendMode.screen : BlendMode.plus;
    final wobbleVal = _raptorWobble(animTimeSeconds);
    final oscillation =
        sin(animTimeSeconds * 5.0) * height * (0.003 + 0.001 * beatStrength);

    final scaledThroat = throatHalfW * engineScale;
    final scaledBell = bellHalfW * engineScale;
    final haloHalfW =
        scaledBell * (1.56 + 0.24 * effectiveAmp) * (tinted != null ? 1.35 : 1.0);
    final coreHalfW =
        scaledThroat * (0.94 + 0.10 * effectiveAmp) * (tinted != null ? 1.40 : 1.0);

    final haloPath =
        _buildRaptorPlumePath(
          nozzleX: nozzleX,
          axisY: axisY,
          plumeLen: plumeLen,
          throatHalfW: scaledThroat,
          bellHalfW: scaledBell,
          exitHalfW: haloHalfW,
          lenScale: 1.12,
          wobbleVal: wobbleVal,
          animTimeSeconds: animTimeSeconds,
          oscillation: oscillation,
        );
    final corePath =
        _buildRaptorPlumePath(
          nozzleX: nozzleX,
          axisY: axisY,
          plumeLen: plumeLen,
          throatHalfW: scaledThroat,
          bellHalfW: scaledBell,
          exitHalfW: coreHalfW,
          lenScale: 0.96,
          wobbleVal: wobbleVal,
          animTimeSeconds: animTimeSeconds,
          oscillation: oscillation,
        );

    final haloBlur = budget.outerBlur > 0
        ? MaskFilter.blur(BlurStyle.normal, budget.outerBlur)
        : null;
    canvas.drawPath(
      haloPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(nozzleX, axisY),
          Offset(nozzleX - plumeLen * 1.18, axisY),
          [
            haloHead.withValues(alpha: (0.22 * effectiveAmp).clamp(0.0, 1.0)),
            haloMid.withValues(alpha: (0.10 * effectiveAmp).clamp(0.0, 1.0)),
            fringe.withValues(alpha: 0.0),
          ],
          [0.0, 0.55, 1.0],
        )
        ..blendMode = plumeBlend
        ..maskFilter = haloBlur,
    );

    if (budget.drawOuterHalo) {
      canvas.drawPath(
        _buildRaptorPlumePath(
          nozzleX: nozzleX,
          axisY: axisY,
          plumeLen: plumeLen,
          throatHalfW: scaledThroat,
          bellHalfW: scaledBell,
          exitHalfW: haloHalfW * 1.14,
          lenScale: 1.26,
          wobbleVal: wobbleVal,
          animTimeSeconds: animTimeSeconds,
          oscillation: oscillation,
        ),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(nozzleX, axisY),
            Offset(nozzleX - plumeLen * 1.35, axisY),
            [
              sheathDeep.withValues(alpha: (0.07 * effectiveAmp).clamp(0.0, 1.0)),
              Colors.transparent,
            ],
          )
          ..blendMode = plumeBlend
          ..maskFilter = haloBlur,
      );
    }

    final coreBlur = budget.coreBlur > 0
        ? MaskFilter.blur(BlurStyle.normal, budget.coreBlur)
        : null;
    canvas.drawPath(
      corePath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(nozzleX, axisY),
          Offset(nozzleX - plumeLen * 0.92, axisY),
          [
            Color.lerp(baseColor, core, 0.55)!.withValues(
              alpha: (0.52 * effectiveAmp * budget.glowAlphaMul).clamp(0.0, 1.0),
            ),
            sheath.withValues(alpha: (0.34 * effectiveAmp).clamp(0.0, 1.0)),
            fringe.withValues(alpha: 0.0),
          ],
          [0.0, 0.22, 1.0],
        )
        ..blendMode = plumeBlend
        ..maskFilter = coreBlur,
    );

    if (drawDiamonds) {
      paintMachDiamonds(
        canvas: canvas,
        axisX: nozzleX,
        axisY: axisY,
        plumeLen: plumeLen,
        throatHalfW: throatHalfW,
        ampFactor: effectiveAmp,
        diamondCount: budget.diamondCount,
        animTimeSeconds: animTimeSeconds,
        budget: budget,
        engineScale: engineScale,
        horizontal: true,
        waveformAmplitude: waveformAmplitude,
        blendScale: blendScale,
      );
    }
  }

  /// Mach diamonds on top of ship hull (Now Playing).
  static void paintHorizontalPlumeDiamonds({
    required Canvas canvas,
    required double nozzleX,
    required double centerY,
    required double height,
    required Color baseColor,
    required double animTimeSeconds,
    required double beatStrength,
    required double waveformAmplitude,
    required TorchEffectBudget budget,
    double seekPulse = 0.0,
    double? shipLen,
    double blendScale = 1.0,
    List<({double offset, double scale})>? cluster,
  }) {
    if (budget.diamondCount <= 0) return;

    final effectiveShipLen = shipLen ?? height * 0.8;
    final metrics = engineMetrics(effectiveShipLen);
    final seekBoost = 1.0 + 0.24 * seekPulse.clamp(0.0, 1.0);
    final ampFactor =
        (0.45 + 0.55 * waveformAmplitude) *
        budget.plumeAlphaMul *
        seekBoost *
        blendScale;
    final flickerVal = flicker(
      animTimeSeconds: animTimeSeconds,
      beatStrength: beatStrength,
      beatWeight: 0.08 + 0.06 * seekPulse,
    );
    final plumeLen =
        effectiveShipLen * 2.42 * flickerVal * budget.plumeLengthMul * seekBoost;
    final throatHalfW =
        metrics.throatHalfW * (0.92 + 0.08 * ampFactor) * raptorExhaustSizeMul;
    final bellHalfW = metrics.bellHalfW;

    for (final engine in (cluster ?? raptorCluster(bellHalfW))) {
      paintMachDiamonds(
        canvas: canvas,
        axisX: nozzleX,
        axisY: centerY + engine.offset,
        plumeLen: plumeLen,
        throatHalfW: throatHalfW,
        ampFactor: ampFactor,
        diamondCount: budget.diamondCount,
        animTimeSeconds: animTimeSeconds,
        budget: budget,
        engineScale: engine.scale,
        horizontal: true,
        waveformAmplitude: waveformAmplitude,
        blendScale: blendScale,
      );
    }
  }

  /// Horizontal engine plume behind the waveform ship.
  static void paintHorizontalPlume({
    required Canvas canvas,
    required double nozzleX,
    required double centerY,
    required double height,
    required Color baseColor,
    required double animTimeSeconds,
    required double beatStrength,
    required double waveformAmplitude,
    required TorchEffectBudget budget,
    double seekPulse = 0.0,
    double? shipLen,
    bool drawDiamonds = false,
    double blendScale = 1.0,
    List<({double offset, double scale})>? cluster,
    bool waveformTinted = false,
  }) {
    final effectiveShipLen = shipLen ?? height * 0.8;
    final metrics = engineMetrics(effectiveShipLen);
    final seekBoost = 1.0 + 0.24 * seekPulse.clamp(0.0, 1.0);
    final ampFactor =
        (0.45 + 0.55 * waveformAmplitude) * budget.plumeAlphaMul * seekBoost;
    final flickerVal = flicker(
      animTimeSeconds: animTimeSeconds,
      beatStrength: beatStrength,
      beatWeight: 0.08 + 0.06 * seekPulse,
    );

    final plumeLen =
        effectiveShipLen * 2.42 * flickerVal * budget.plumeLengthMul * seekBoost *
        (waveformTinted ? 1.18 : 1.0);
    final throatHalfW =
        metrics.throatHalfW * (0.92 + 0.08 * ampFactor) * raptorExhaustSizeMul;
    final bellHalfW =
        metrics.bellHalfW * (0.95 + 0.12 * ampFactor) * raptorExhaustSizeMul;

    for (final engine in (cluster ?? raptorCluster(metrics.bellHalfW))) {
      _paintSingleHorizontalRaptor(
        canvas: canvas,
        nozzleX: nozzleX,
        axisY: centerY + engine.offset,
        plumeLen: plumeLen,
        throatHalfW: throatHalfW,
        bellHalfW: bellHalfW,
        engineScale: engine.scale,
        baseColor: baseColor,
        ampFactor: ampFactor,
        animTimeSeconds: animTimeSeconds,
        beatStrength: beatStrength,
        height: height,
        budget: budget,
        waveformAmplitude: waveformAmplitude,
        drawDiamonds: drawDiamonds,
        blendScale: blendScale,
        waveformTinted: waveformTinted,
      );
    }
  }

  /// Vertical side-ion plumes on the ship hull (rotated canvas).
  static void paintVerticalSideIons({
    required Canvas canvas,
    required double shipLen,
    required double shipWidth,
    required Color accent,
    required double animTimeSeconds,
    required double beatStrength,
    required TorchEffectBudget budget,
  }) {
    if (!budget.drawSideIons) return;

    final flickerVal = flicker(
      animTimeSeconds: animTimeSeconds,
      beatStrength: beatStrength,
      beatWeight: 0.12,
      highFreqWeight: 0.05,
    );
    final wobbleVal = _raptorWobble(animTimeSeconds);
    final plumeLen = shipLen * 1.55 * flickerVal * budget.plumeLengthMul;
    final sheath = raptorSheath(accent);
    final fringe = raptorFringe(accent);

    final metrics = engineMetrics(shipLen);
    final throatHalfW = metrics.throatHalfW;
    final bellHalfW = metrics.bellHalfW;

    Path buildDrivePlume({required double exitHalfW, required double lenScale}) {
      final baseY = shipLen * 0.45;
      final len = plumeLen * lenScale;
      final tipY = baseY + len;
      final expandY = baseY + len * 0.17;
      final midY = baseY + len * 0.52;
      final twist = sin(animTimeSeconds * 11.0) * throatHalfW * 0.04;
      final p = Path();
      p.moveTo(-throatHalfW, baseY);
      p.cubicTo(
        -throatHalfW * 0.96,
        baseY + len * 0.04,
        -bellHalfW * 0.94,
        baseY + len * 0.10,
        -exitHalfW * 0.92 * wobbleVal + twist,
        expandY,
      );
      p.cubicTo(
        -exitHalfW * 0.78 * wobbleVal,
        midY,
        -exitHalfW * 0.24 + twist * 0.35,
        tipY - len * 0.22,
        0,
        tipY,
      );
      p.cubicTo(
        exitHalfW * 0.24 - twist * 0.35,
        tipY - len * 0.22,
        exitHalfW * 0.78 * wobbleVal,
        midY,
        exitHalfW * 0.92 * wobbleVal - twist,
        expandY,
      );
      p.cubicTo(
        bellHalfW * 0.94,
        baseY + len * 0.10,
        throatHalfW * 0.96,
        baseY + len * 0.04,
        throatHalfW,
        baseY,
      );
      p.close();
      return p;
    }

    final haloPath =
        buildDrivePlume(exitHalfW: bellHalfW * 1.35, lenScale: 1.25);
    final outerHaze =
        buildDrivePlume(exitHalfW: bellHalfW * 1.85, lenScale: 1.48);
    final alphaMul = budget.plumeAlphaMul;

    final outerBlur = budget.outerBlur > 0
        ? MaskFilter.blur(BlurStyle.normal, budget.outerBlur)
        : null;

    canvas.drawPath(
      haloPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, shipLen * 0.45),
          Offset(0, shipLen * 0.45 + plumeLen * 1.35),
          [
            sheath.withValues(alpha: 0.34 * alphaMul),
            fringe.withValues(alpha: 0.14 * alphaMul),
            fringe.withValues(alpha: 0.0),
          ],
          [0.0, 0.55, 1.0],
        )
        ..maskFilter = outerBlur
        ..blendMode = BlendMode.plus,
    );

    if (budget.drawOuterHalo) {
      canvas.drawPath(
        outerHaze,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, shipLen * 0.45),
            Offset(0, shipLen * 0.45 + plumeLen * 1.6),
            [
              raptorSheathDeep(accent).withValues(alpha: 0.10 * alphaMul),
              fringe.withValues(alpha: 0.03 * alphaMul),
              Colors.transparent,
            ],
            [0.0, 0.4, 1.0],
          )
          ..blendMode = BlendMode.plus
          ..maskFilter = outerBlur,
      );
    }
  }

  static Path _buildVerticalRaptorPlumePath({
    required double axisX,
    required double baseY,
    required double plumeLen,
    required double throatHalfW,
    required double bellHalfW,
    required double exitHalfW,
    required double lenScale,
    required double wobbleVal,
    required double animTimeSeconds,
  }) {
    final len = plumeLen * lenScale;
    final tipY = baseY + len;
    final expandY = baseY + len * 0.17;
    final midY = baseY + len * 0.52;
    final twist = sin(animTimeSeconds * 11.0) * throatHalfW * 0.04;
    final p = Path();
    p.moveTo(axisX - throatHalfW, baseY);
    p.cubicTo(
      axisX - throatHalfW * 0.96,
      baseY + len * 0.04,
      axisX - bellHalfW * 0.94,
      baseY + len * 0.10,
      axisX - bellHalfW * wobbleVal + twist,
      expandY,
    );
    p.cubicTo(
      axisX - exitHalfW * 0.82 * wobbleVal,
      midY,
      axisX - exitHalfW * 0.28 + twist * 0.25,
      tipY - len * 0.22,
      axisX,
      tipY,
    );
    p.cubicTo(
      axisX + exitHalfW * 0.28 - twist * 0.25,
      tipY - len * 0.22,
      axisX + exitHalfW * 0.82 * wobbleVal,
      midY,
      axisX + bellHalfW * wobbleVal - twist,
      expandY,
    );
    p.cubicTo(
      axisX + bellHalfW * 0.94,
      baseY + len * 0.10,
      axisX + throatHalfW * 0.96,
      baseY + len * 0.04,
      axisX + throatHalfW,
      baseY,
    );
    p.close();
    return p;
  }

  static void _paintSingleVerticalRaptor({
    required Canvas canvas,
    required double axisX,
    required double baseY,
    required double plumeLen,
    required double throatHalfW,
    required double bellHalfW,
    required double engineScale,
    required Color accent,
    required double alphaMul,
    required double animTimeSeconds,
    required TorchEffectBudget budget,
  }) {
    final core = raptorCore(accent);
    final sheath = raptorSheath(accent);
    final fringe = raptorFringe(accent);
    final wobbleVal = _raptorWobble(animTimeSeconds);

    final scaledThroat = throatHalfW * engineScale;
    final scaledBell = bellHalfW * engineScale;
    final haloHalfW = scaledBell * 1.42;
    final coreHalfW = scaledThroat * 0.92;

    final haloPath = _buildVerticalRaptorPlumePath(
      axisX: axisX,
      baseY: baseY,
      plumeLen: plumeLen,
      throatHalfW: scaledThroat,
      bellHalfW: scaledBell,
      exitHalfW: haloHalfW,
      lenScale: 1.12,
      wobbleVal: wobbleVal,
      animTimeSeconds: animTimeSeconds,
    );
    final corePath = _buildVerticalRaptorPlumePath(
      axisX: axisX,
      baseY: baseY,
      plumeLen: plumeLen,
      throatHalfW: scaledThroat,
      bellHalfW: scaledBell,
      exitHalfW: coreHalfW,
      lenScale: 0.98,
      wobbleVal: wobbleVal,
      animTimeSeconds: animTimeSeconds,
    );

    final outerBlur = budget.outerBlur > 0
        ? MaskFilter.blur(BlurStyle.normal, budget.outerBlur)
        : null;
    canvas.drawPath(
      haloPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(axisX, baseY),
          Offset(axisX, baseY + plumeLen * 1.15),
          [
            sheath.withValues(alpha: 0.34 * alphaMul),
            fringe.withValues(alpha: 0.14 * alphaMul),
            fringe.withValues(alpha: 0.0),
          ],
          [0.0, 0.55, 1.0],
        )
        ..maskFilter = outerBlur
        ..blendMode = BlendMode.plus,
    );

    final coreBlur = budget.coreBlur > 0
        ? MaskFilter.blur(BlurStyle.normal, budget.coreBlur)
        : null;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(axisX, baseY),
        width: scaledBell * 1.7,
        height: scaledThroat * 2.3,
      ),
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(axisX, baseY),
          scaledBell * 0.92,
          [
            core.withValues(alpha: 0.78 * alphaMul),
            sheath.withValues(alpha: 0.38 * alphaMul),
            Colors.transparent,
          ],
          [0.0, 0.55, 1.0],
        )
        ..blendMode = BlendMode.plus,
    );

    canvas.drawPath(
      corePath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(axisX, baseY),
          Offset(axisX, baseY + plumeLen * 0.95),
          [
            core.withValues(alpha: 0.95 * alphaMul),
            sheath.withValues(alpha: 0.72 * alphaMul),
            fringe.withValues(alpha: 0.0),
          ],
          [0.0, 0.22, 1.0],
        )
        ..maskFilter = coreBlur
        ..blendMode = BlendMode.plus,
    );

    final diamondCount = engineScale >= 0.95
        ? budget.diamondCount
        : max(0, budget.diamondCount - 2);
    paintMachDiamonds(
      canvas: canvas,
      axisX: axisX,
      axisY: baseY,
      plumeLen: plumeLen,
      throatHalfW: throatHalfW,
      ampFactor: alphaMul,
      diamondCount: diamondCount,
      animTimeSeconds: animTimeSeconds,
      budget: budget,
      engineScale: engineScale,
      horizontal: false,
    );
  }

  static void paintVerticalCorePlume({
    required Canvas canvas,
    required double shipLen,
    required double shipWidth,
    required Color accent,
    required Color accentCool,
    required double animTimeSeconds,
    required double beatStrength,
    required TorchEffectBudget budget,
    List<({double offset, double scale})>? cluster,
  }) {
    final flickerVal = flicker(
      animTimeSeconds: animTimeSeconds,
      beatStrength: beatStrength,
      beatWeight: 0.12,
      highFreqWeight: 0.05,
    );
    final plumeLen = shipLen * 1.55 * flickerVal * budget.plumeLengthMul;
    final alphaMul = budget.plumeAlphaMul * budget.glowAlphaMul;

    final metrics = engineMetrics(shipLen);
    final throatHalfW = metrics.throatHalfW;
    final bellHalfW = metrics.bellHalfW;
    final baseY = shipLen * 0.45;

    for (final engine in (cluster ?? raptorCluster(metrics.bellHalfW))) {
      _paintSingleVerticalRaptor(
        canvas: canvas,
        axisX: engine.offset,
        baseY: baseY,
        plumeLen: plumeLen,
        throatHalfW: throatHalfW,
        bellHalfW: bellHalfW,
        engineScale: engine.scale,
        accent: accent,
        alphaMul: alphaMul,
        animTimeSeconds: animTimeSeconds,
        budget: budget,
      );
    }
  }
}