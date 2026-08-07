// Regression test for the stale-nebula-texture crash seen on a physical
// device: a _StarFieldPainter built before a cache refresh holds a snapshot of
// the baked nebula texture. If the refresh disposes that texture in the same
// frame, the painter's drawImageRect asserts on a disposed image. The refresh
// must retire the old texture (disposing it only after a rebuild that swaps the
// painter) instead of disposing it synchronously.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:playa_clean/ui/deep_space_background.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('nebula refresh retires the texture instead of disposing it in-frame',
      (tester) async {
    tester.view.physicalSize = const Size(480, 270);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Wrapper lets us force a rebuild with the same layout, so the live painter
    // captures the baked texture (without a rebuild the painter would still hold
    // the null first-build snapshot and the crash would not reproduce).
    final rebuildTick = ValueNotifier<int>(0);
    addTearDown(rebuildTick.dispose);

    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('spaceCapture'),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox.expand(
            child: ValueListenableBuilder<int>(
              valueListenable: rebuildTick,
              builder: (context, value, child) =>
                  const DeepSpaceBackground(hdrBoost: true, hdrIntensity: 1.0, seed: 7),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));

    // Rebuild with the same constraints: the painter now references the baked
    // texture, and _needsStarReinit stays false so the cache survives.
    rebuildTick.value = 1;
    await tester.pump(const Duration(milliseconds: 16));

    // Jump far past the 15s cache lifetime so the stale refresh fires while the
    // current painter still holds the old texture. Painting must not touch a
    // disposed image in the same frame.
    await tester.pump(const Duration(seconds: 20));

    expect(tester.takeException(), isNull,
        reason: 'painting must not assert on a disposed nebula texture');
  });
}
