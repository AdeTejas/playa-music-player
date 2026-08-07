// Visual paint-cost regression proxy.
//
// NOT a GPU benchmark. It measures CPU software-rasterization time
// (Picture.toImage / RenderRepaintBoundary.toImage) inside the flutter_test
// environment. Purpose: catch catastrophic per-frame cost blowups and enforce
// that the TorchEffectBudget tiers get *cheaper* — not just dimmer. For
// real-device numbers run `flutter run --profile` + DevTools; treat the
// absolute millisecond values here as machine-relative, not truth.
//
// Surfaces measured (the production per-frame hot paths):
//   * waveform hero   — PreciseWaveformPainter, standard mode (plume + ship)
//   * ship (hero/screensaver sizes) — RocinanteShipPainter
//   * screensaver trail — TorchPlumeEngine plume + throat at full/reduced/minimal
//   * deep space      — DeepSpaceBackground full-quality backdrop
import 'dart:math';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:playa_clean/services/settings_service.dart';
import 'package:playa_clean/ui/deep_space_background.dart';
import 'package:playa_clean/ui/rocinante_ship_painter.dart';
import 'package:playa_clean/ui/torch_plume_engine.dart';
import 'package:playa_clean/ui/waveform_widget.dart';

const _w = 1280.0;
const _h = 720.0;

List<double> _waveformData() => List<double>.generate(
      240,
      (i) => 0.35 +
          0.3 * sin(i * 0.4) +
          0.25 * (Random(i).nextDouble()) +
          0.1 * sin(i * 1.7),
    ).map((v) => v.clamp(0.12, 1.0)).toList();

Future<double> _median(List<double> xs) {
  final s = List<double>.from(xs)..sort();
  return Future.value(s[s.length ~/ 2]);
}

/// Median raster ms for a recorded picture (warmup + [runs] timed passes).
Future<double> _pictureMs(ui.Picture picture, {int runs = 3}) async {
  await picture.toImage(_w.toInt(), _h.toInt());
  final samples = <double>[];
  for (int i = 0; i < runs; i++) {
    final sw = Stopwatch()..start();
    await picture.toImage(_w.toInt(), _h.toInt());
    sw.stop();
    samples.add(sw.elapsedMicroseconds / 1000.0);
  }
  return _median(samples);
}

/// Median raster ms across several animated frames of a recorder-based scene.
Future<double> _sceneMs(
  List<ui.Picture> Function() frames, {
  int runs = 2,
}) async {
  final samples = <double>[];
  for (final pic in frames()) {
    samples.add(await _pictureMs(pic, runs: runs));
  }
  return _median(samples);
}

// ---------------------------------------------------------------------------
// Recorder scenes (ship + screensaver trail)
// ---------------------------------------------------------------------------

ui.Picture _recordShipScene(double shipLen, double t, double beat) {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, _w, _h),
    Paint()..color = const Color(0xFF070A0F),
  );
  canvas.save();
  canvas.translate(_w / 2, _h / 2);
  canvas.rotate(pi / 2);
  RocinanteShipPainter(
    shipLen: shipLen,
    color: const Color(0xFF00E5FF),
    timeSeconds: t,
    beatStrength: beat,
    drawPlume: true,
    drawDiamonds: true,
  ).paint(canvas, Size(shipLen, shipLen));
  canvas.restore();
  return rec.endRecording();
}

ui.Picture _recordTrailScene(TorchEffectBudget budget, double t, double beat) {
  const shipLen = 48.0;
  const centerY = _h / 2;
  const nozzleX = _w * 0.47;
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, _w, _h),
    Paint()..color = const Color(0xFF070A0F),
  );
  final amp = 0.55 + 0.25 * beat;
  TorchPlumeEngine.paintHorizontalPlume(
    canvas: canvas,
    nozzleX: nozzleX,
    centerY: centerY,
    height: shipLen * 1.15,
    shipLen: shipLen,
    baseColor: const Color(0xFFC9A86A),
    animTimeSeconds: t,
    beatStrength: beat,
    waveformAmplitude: amp,
    budget: budget,
  );
  TorchPlumeEngine.paintEngineThroat(
    canvas: canvas,
    nozzleX: nozzleX,
    centerY: centerY,
    shipLen: shipLen,
    baseColor: const Color(0xFFC9A86A),
    seekPulse: 0,
    budget: budget,
    beatStrength: beat,
    waveformAmplitude: amp,
  );
  return rec.endRecording();
}

// ---------------------------------------------------------------------------
// Widget captures (waveform hero + deep space)
// ---------------------------------------------------------------------------

Widget _waveformFrame(int i) {
  final t = 0.5 + i * 0.9;
  final p = 0.3 + 0.1 * i;
  return RepaintBoundary(
    key: const ValueKey('wf'),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: CustomPaint(
        painter: PreciseWaveformPainter(
          waveformData: _waveformData(),
          progress: p,
          timeSeconds: t,
          playedColor: const Color(0xFF00E5FF),
          unplayedColor: const Color(0xFF00E5FF).withValues(alpha: 0.1),
          bpm: 128,
          displayMode: WaveformDisplayMode.standard,
        ),
        size: const Size(1600, 360),
      ),
    ),
  );
}

Widget _spaceFrame() {
  return const RepaintBoundary(
    key: ValueKey('space'),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox.expand(
        child: DeepSpaceBackground(hdrBoost: true, hdrIntensity: 1.0, seed: 7),
      ),
    ),
  );
}

Future<double> _waveformHeroMs(WidgetTester tester) async {
  final samples = <double>[];
  for (int i = 0; i < 3; i++) {
    await tester.pumpWidget(_waveformFrame(i));
    await tester.pump(const Duration(milliseconds: 16));
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('wf')),
    );
    await tester.runAsync(() async {
      final sw = Stopwatch()..start();
      await boundary.toImage(pixelRatio: 1.0);
      sw.stop();
      samples.add(sw.elapsedMicroseconds / 1000.0);
    });
  }
  return _median(samples);
}

Future<double> _deepSpaceMs(WidgetTester tester) async {
  final samples = <double>[];
  for (int i = 0; i < 3; i++) {
    await tester.pumpWidget(_spaceFrame());
    // Bake the frame-budget accumulator + nebula cache before timing.
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('space')),
    );
    await tester.runAsync(() async {
      final sw = Stopwatch()..start();
      await boundary.toImage(pixelRatio: 1.0);
      sw.stop();
      samples.add(sw.elapsedMicroseconds / 1000.0);
    });
  }
  return _median(samples);
}

// ---------------------------------------------------------------------------
// Tier plumbing
// ---------------------------------------------------------------------------

Future<TorchEffectBudget> _applyTier({
  required bool lowPerformance,
  required bool highQualityBlur,
}) async {
  final s = SettingsService.instance;
  await s.setLowPerformanceMode(lowPerformance);
  await s.setHighQualityBlur(highQualityBlur);
  await s.setBatterySaver(false);
  return TorchEffectBudget.resolve(profile: TorchContentProfile.music);
}

void _printRow(String label, double ms) {
  // ignore: avoid_print
  print('${label.padRight(34)} ${ms.toStringAsFixed(1).padLeft(8)} ms');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
    (message) async => const StandardMessageCodec().encodeMessage(<Object?>[]),
  );

  testWidgets('visual paint-cost proxy: tier scaling + absolute budgets', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();

    tester.view.physicalSize = const Size(_w, _h);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // ignore: avoid_print
    print('\n--- visual paint-cost proxy (CPU raster, ms/frame median) ---');

    final waveformMs = await _waveformHeroMs(tester);
    _printRow('waveform hero (1600x360)', waveformMs);

    final shipHeroMs = await _sceneMs(
      () => [
        _recordShipScene(256, 0.4, 0.3),
        _recordShipScene(256, 1.3, 0.6),
        _recordShipScene(256, 2.7, 0.9),
      ],
    );
    _printRow('ship hero (len 256)', shipHeroMs);

    final shipSaverMs = await _sceneMs(
      () => [
        _recordShipScene(48, 0.4, 0.3),
        _recordShipScene(48, 1.3, 0.6),
        _recordShipScene(48, 2.7, 0.9),
      ],
    );
    _printRow('ship screensaver (len 48)', shipSaverMs);

    final fullBudget = await _applyTier(lowPerformance: false, highQualityBlur: true);
    final fullMs = await _sceneMs(
      () => [
        _recordTrailScene(fullBudget, 0.4, 0.3),
        _recordTrailScene(fullBudget, 1.3, 0.6),
        _recordTrailScene(fullBudget, 2.7, 0.9),
      ],
    );
    _printRow('screensaver trail - full', fullMs);

    final reducedBudget = await _applyTier(
      lowPerformance: false,
      highQualityBlur: false,
    );
    final reducedMs = await _sceneMs(
      () => [
        _recordTrailScene(reducedBudget, 0.4, 0.3),
        _recordTrailScene(reducedBudget, 1.3, 0.6),
        _recordTrailScene(reducedBudget, 2.7, 0.9),
      ],
    );
    _printRow('screensaver trail - reduced', reducedMs);

    final minimalBudget = await _applyTier(lowPerformance: true, highQualityBlur: false);
    final minimalMs = await _sceneMs(
      () => [
        _recordTrailScene(minimalBudget, 0.4, 0.3),
        _recordTrailScene(minimalBudget, 1.3, 0.6),
        _recordTrailScene(minimalBudget, 2.7, 0.9),
      ],
    );
    _printRow('screensaver trail - minimal', minimalMs);

    final spaceMs = await _deepSpaceMs(tester);
    _printRow('deep space (1280x720 full)', spaceMs);
    // ignore: avoid_print
    print('--------------------------------------------------------------');

    // The tiers must actually get cheaper (slack absorbs scheduler noise on
    // shared CI machines).
    expect(reducedMs, lessThanOrEqualTo(fullMs * 1.30 + 10.0),
        reason: 'reduced tier should not be slower than full');
    expect(minimalMs, lessThanOrEqualTo(reducedMs * 1.30 + 10.0),
        reason: 'minimal tier should not be slower than reduced');
    expect(minimalMs, lessThan(fullMs * 0.95),
        reason: 'minimal tier (zero blur, zero diamonds) must be markedly '
            'cheaper than full');

    // Absolute per-frame budgets. ~15-20x the observed local medians so they
    // stay green on slower CI while still tripping on accidental 10x blowups
    // (extra full-screen pass, doubled blur chain, etc.).
    expect(waveformMs, lessThan(500.0));
    expect(shipHeroMs, lessThan(150.0));
    expect(shipSaverMs, lessThan(40.0));
    expect(fullMs, lessThan(120.0));
    expect(reducedMs, lessThan(120.0));
    expect(minimalMs, lessThan(60.0));
    expect(spaceMs, lessThan(1500.0));
  });
}
