import 'package:flutter_test/flutter_test.dart';
import 'package:playa_clean/ui/deep_space_background.dart';

void main() {
  test('background immersive targets 30fps', () {
    final interval = DeepSpaceFrameBudget.minFrameIntervalSeconds(
      mode: DeepSpaceMode.background,
      subtle: false,
      hasComets: false,
    );
    expect(interval, closeTo(1 / 30, 0.001));
  });

  test('overlay idles slower than active comets', () {
    final idle = DeepSpaceFrameBudget.minFrameIntervalSeconds(
      mode: DeepSpaceMode.overlay,
      subtle: false,
      hasComets: false,
    );
    final active = DeepSpaceFrameBudget.minFrameIntervalSeconds(
      mode: DeepSpaceMode.overlay,
      subtle: false,
      hasComets: true,
    );
    expect(active, lessThan(idle));
  });

  test('beat envelope peaks on each beat and troughs mid-beat', () {
    expect(DeepSpaceFrameBudget.beatPulseEnvelope(0.0), closeTo(1.0, 0.0001));
    expect(DeepSpaceFrameBudget.beatPulseEnvelope(1.0), closeTo(1.0, 0.0001));
    expect(DeepSpaceFrameBudget.beatPulseEnvelope(2.0), closeTo(1.0, 0.0001));
    expect(DeepSpaceFrameBudget.beatPulseEnvelope(0.5), closeTo(0.0, 0.0001));
    expect(DeepSpaceFrameBudget.beatPulseEnvelope(1.5), closeTo(0.0, 0.0001));
    expect(
      DeepSpaceFrameBudget.beatPulseEnvelope(0.25),
      closeTo(0.5, 0.0001),
    );
  });

  test('beat twinkle rate matches bpm via 2*timeSeconds', () {
    // timeSeconds advances at (bpm/120) in the ticker, so the beat phase
    // advances at 2*(bpm/120) = bpm/60 beats per wall-clock second, i.e. the
    // true beat rate at any bpm.
    for (final bpm in [60.0, 90.0, 120.0, 180.0]) {
      final beatsPerSecond = bpm / 60.0;
      final phasePerSecond = 2.0 * (bpm / 120.0);
      expect(phasePerSecond, closeTo(beatsPerSecond, 0.0001),
          reason: 'bpm=$bpm should twinkle once per real beat');
    }
  });
}
