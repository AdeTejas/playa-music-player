import 'package:flutter_test/flutter_test.dart';
import 'package:playa_clean/ui/high_tech_speaker.dart';

void main() {
  test('flower of life has 19 circles on a 2-ring hex lattice', () {
    final centers = SacredFlowerGeometry.flowerCenters(10);
    expect(centers, hasLength(SacredFlowerGeometry.flowerOfLifeCircleCount));
    expect(centers.first, Offset.zero);
  });

  test('adjacent pairs match hex neighbor spacing', () {
    const spacing = 12.0;
    final centers = SacredFlowerGeometry.flowerCenters(spacing);
    final pairs = SacredFlowerGeometry.adjacentPairs(centers, spacing);
    expect(pairs, isNotEmpty);
    for (final (a, b) in pairs) {
      expect((a - b).distance, closeTo(spacing, 0.01));
    }
  });

  test('vesica lens path is non-empty for touching circles', () {
    const r = 10.0;
    final path = SacredFlowerGeometry.vesicaLens(
      const Offset(0, 0),
      const Offset(r, 0),
      r,
    );
    expect(path.getBounds().width, greaterThan(0));
    expect(path.getBounds().height, greaterThan(0));
  });
}