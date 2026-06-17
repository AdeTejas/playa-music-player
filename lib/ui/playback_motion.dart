import 'dart:math';
import 'dart:ui' show Offset;

import 'torch_plume_engine.dart';

/// Shared breath / beat / ring-wave timing for Now Playing visuals.
class PlaybackMotion {
  PlaybackMotion._();

  static const double breathHz = 1.05;
  static const double ringWaveHz = 1.55;
  static const double ringLag = 0.72;
  static const double idleShimmerHz = 0.55;

  static double breath(double t) => sin(t * breathHz);

  static double breathEased(double t) {
    final b = breath(t);
    return b > 0 ? b * b : -b * 0.35;
  }

  static double breathNormalized(double t) => (breath(t) + 1) * 0.5;

  static double ringWave(int ring, double t) =>
      0.5 + 0.5 * cos(t * ringWaveHz - ring * ringLag);

  static double ringWaveEased(int ring, double t) {
    final w = ringWave(ring, t);
    return w * w;
  }

  static double idleShimmer(double t) =>
      0.10 + 0.06 * (0.5 + 0.5 * cos(t * idleShimmerHz));

  static double beatDrive(double playbackSeconds, double? bpm) =>
      TorchPlumeEngine.beatStrength(playbackSeconds, bpm);

  static double beatPulse(double playbackSeconds, double bpm) {
    final freq = bpm.clamp(60.0, 220.0) / 60.0;
    return (sin(playbackSeconds * freq * 2 * pi) + 1) / 2;
  }

  static double shipBobOffset(double t, double height, double thrust) =>
      breath(t) * height * 0.0018 * thrust;

  /// Per-pod RCS pulse rate (Hz) — real attitude jets typically puff ~2–5 Hz.
  static const double rcsPulseHzMin = 2.2;
  static const double rcsPulseHzMax = 4.6;

  /// Fraction of each pulse cycle the thruster is actually firing.
  static const double rcsDutyMin = 0.07;
  static const double rcsDutyMax = 0.18;

  /// Roll-authority cycle for paired lateral pods (Hz).
  static const double rcsRollAuthorityHz = 1.25;

  static double _hash01(double v) {
    final x = sin(v * 12.9898) * 43758.5453;
    return x - x.floorToDouble();
  }

  /// Short RCS puffs with low duty cycle — not a continuous high-frequency flicker.
  static double rcsPuffIntensity({
    required double timeSeconds,
    required double podPhase,
    required double stabDemand,
    required double demandBias,
    required double pitchRadians,
    required Offset podDirection,
  }) {
    if (stabDemand < 0.04) return 0.0;

    final axisNeed = _rcsAxisDemand(
      timeSeconds: timeSeconds,
      podPhase: podPhase,
      stabDemand: stabDemand,
      pitchRadians: pitchRadians,
      podDirection: podDirection,
    );
    if (axisNeed < 0.05) return 0.0;

    final pulseHz =
        rcsPulseHzMin + _hash01(podPhase * 2.17) * (rcsPulseHzMax - rcsPulseHzMin);
    final cyclePos = (timeSeconds * pulseHz + podPhase * 0.318) % 1.0;
    final duty = (rcsDutyMin + (rcsDutyMax - rcsDutyMin) * demandBias.clamp(0.0, 1.0))
        .clamp(rcsDutyMin, rcsDutyMax);
    if (cyclePos > duty) return 0.0;

    final puff = sin(pi * cyclePos / duty);
    final drive = stabDemand * demandBias * axisNeed;
    return (puff * puff * drive).clamp(0.0, 1.0);
  }

  static double _rcsAxisDemand({
    required double timeSeconds,
    required double podPhase,
    required double stabDemand,
    required double pitchRadians,
    required Offset podDirection,
  }) {
    final pitchNeed = (pitchRadians.abs() * 14.0).clamp(0.0, 1.0);
    final isPitchAxis = podDirection.dy.abs() > podDirection.dx.abs() * 0.6;
    final isLateral = podDirection.dx.abs() > podDirection.dy.abs() * 0.6;

    if (isPitchAxis) {
      var need = 0.32 + 0.68 * max(pitchNeed, stabDemand * 0.45);
      if (pitchRadians > 0.001 && podDirection.dy < 0) need *= 1.12;
      if (pitchRadians < -0.001 && podDirection.dy > 0) need *= 1.12;
      return need.clamp(0.0, 1.0);
    }

    if (isLateral) {
      final rollCycle = cos(timeSeconds * rcsRollAuthorityHz * 2 * pi + podPhase);
      final sideActive = (rollCycle * podDirection.dx) > 0;
      return sideActive
          ? (0.5 + 0.5 * stabDemand).clamp(0.0, 1.0)
          : 0.18 + 0.12 * stabDemand;
    }

    return (0.55 + 0.45 * stabDemand).clamp(0.0, 1.0);
  }
}