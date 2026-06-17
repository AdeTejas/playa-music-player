import 'package:flutter_test/flutter_test.dart';
import 'package:playa_clean/ui/deep_space_background.dart';

void main() {
  test('background immersive targets 30fps', () {
    final interval = DeepSpaceFrameBudget.minFrameIntervalSeconds(
      mode: DeepSpaceMode.background,
      subtle: false,
      hasComets: false,
      appActive: true,
    );
    expect(interval, closeTo(1 / 30, 0.001));
  });

  test('overlay idles slower than active comets', () {
    final idle = DeepSpaceFrameBudget.minFrameIntervalSeconds(
      mode: DeepSpaceMode.overlay,
      subtle: false,
      hasComets: false,
      appActive: true,
    );
    final active = DeepSpaceFrameBudget.minFrameIntervalSeconds(
      mode: DeepSpaceMode.overlay,
      subtle: false,
      hasComets: true,
      appActive: true,
    );
    expect(active, lessThan(idle));
  });

  test('paused app does not repaint', () {
    final interval = DeepSpaceFrameBudget.minFrameIntervalSeconds(
      mode: DeepSpaceMode.background,
      subtle: false,
      hasComets: false,
      appActive: false,
    );
    expect(interval, double.infinity);
  });
}