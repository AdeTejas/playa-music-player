import 'package:flutter_test/flutter_test.dart';
import 'package:playa_clean/ui/playback_motion.dart';

void main() {
  test('breath and ring wave stay in normalized range', () {
    for (final t in [0.0, 0.5, 1.2, 3.7, 12.0]) {
      expect(PlaybackMotion.breathNormalized(t), inInclusiveRange(0.0, 1.0));
      expect(PlaybackMotion.ringWave(0, t), inInclusiveRange(0.0, 1.0));
      expect(PlaybackMotion.ringWaveEased(2, t), inInclusiveRange(0.0, 1.0));
      expect(PlaybackMotion.idleShimmer(t), inInclusiveRange(0.0, 1.0));
    }
  });

  test('beatPulse peaks periodically', () {
    final low = PlaybackMotion.beatPulse(0.0, 120);
    final mid = PlaybackMotion.beatPulse(0.25, 120);
    expect(mid, greaterThanOrEqualTo(low));
  });

  test('shipBob scales with thrust', () {
    final quiet = PlaybackMotion.shipBobOffset(1.0, 40, 0.2).abs();
    final loud = PlaybackMotion.shipBobOffset(1.0, 40, 1.0).abs();
    expect(loud, greaterThan(quiet));
  });

  test('RCS puffs are sparse — low average duty over time', () {
    const lateral = Offset(-1, 0);
    var samples = 0;
    var firing = 0.0;
    for (var i = 0; i < 240; i++) {
      final t = i * 0.016;
      final v = PlaybackMotion.rcsPuffIntensity(
        timeSeconds: t,
        podPhase: 1.4,
        stabDemand: 0.75,
        demandBias: 0.85,
        pitchRadians: 0.008,
        podDirection: lateral,
      );
      samples++;
      if (v > 0.05) firing++;
    }
    final duty = firing / samples;
    expect(duty, lessThan(0.35));
    expect(duty, greaterThan(0.02));
  });

  test('RCS roll authority modulates lateral pods over time', () {
    const port = Offset(-1, 0);
    const starboard = Offset(1, 0);
    var diverged = false;
    for (var i = 0; i < 120; i++) {
      final t = i * 0.025;
      final portVal = PlaybackMotion.rcsPuffIntensity(
        timeSeconds: t,
        podPhase: 0.0,
        stabDemand: 0.8,
        demandBias: 1.0,
        pitchRadians: 0.0,
        podDirection: port,
      );
      final starVal = PlaybackMotion.rcsPuffIntensity(
        timeSeconds: t,
        podPhase: 1.4,
        stabDemand: 0.8,
        demandBias: 1.0,
        pitchRadians: 0.0,
        podDirection: starboard,
      );
      if ((portVal - starVal).abs() > 0.12) diverged = true;
    }
    expect(diverged, isTrue);
  });
}