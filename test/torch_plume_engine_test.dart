import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playa_clean/services/waveform_envelope_service.dart';
import 'package:playa_clean/ui/torch_plume_engine.dart';
import 'package:playa_clean/utils/content_mode.dart';

void main() {
  test('TorchEffectBudget audiobook profile disables diamonds', () {
    final budget = TorchEffectBudget.resolve(
      profile: TorchContentProfile.audiobook,
    );
    expect(budget.diamondCount, 0);
    expect(budget.plumeLengthMul, lessThan(1.0));
  });

  test('TorchEffectBudget music profile enables diamonds at full tier', () {
    final budget = TorchEffectBudget.resolve(
      profile: TorchContentProfile.music,
    );
    expect(budget.diamondCount, greaterThan(0));
  });

  test('TorchPlumeEngine beatStrength stays in range', () {
    final strength = TorchPlumeEngine.beatStrength(12.5, 128);
    expect(strength, inInclusiveRange(0.35, 1.0));
  });

  test('procedural envelope is stable and normalized', () {
    final a = WaveformEnvelopeService.instance.proceduralFallback('/music/a.mp3');
    final b = WaveformEnvelopeService.instance.proceduralFallback('/music/a.mp3');
    expect(a, equals(b));
    expect(a.length, WaveformEnvelopeService.defaultSamples);
    for (final v in a) {
      expect(v, inInclusiveRange(0.05, 1.0));
    }
  });

  test('warm and ion cool colors derive from accent', () {
    const accent = Color(0xFFFF9F40);
    final warm = TorchPlumeEngine.warmExhaust(accent);
    final cool = TorchPlumeEngine.ionCool(accent);
    expect(warm, isNot(equals(accent)));
    expect(cool, isNot(equals(accent)));
    expect(warm, isNot(equals(cool)));
  });

  test('raptor cluster has triple engines with center dominant', () {
    final cluster = TorchPlumeEngine.raptorCluster(8);
    expect(cluster, hasLength(3));
    expect(cluster[1].scale, 1.0);
    expect(cluster[0].scale, closeTo(0.58, 0.01));
    expect(cluster[2].scale, closeTo(0.58, 0.01));
    expect(cluster[0].offset, closeTo(-5.76, 0.01));
    expect(cluster[2].offset, closeTo(5.76, 0.01));
  });

  test('computeWaveformDrive reacts to local envelope', () {
    final flat = List<double>.filled(300, 0.35);
    final loud = List<double>.generate(300, (i) => i == 150 ? 0.95 : 0.25);
    final quietDrive = TorchPlumeEngine.computeWaveformDrive(
      waveformData: flat,
      progress: 0.5,
      beatStrength: 0.4,
    );
    final loudDrive = TorchPlumeEngine.computeWaveformDrive(
      waveformData: loud,
      progress: 0.5,
      beatStrength: 0.4,
    );
    expect(loudDrive, greaterThan(quietDrive));
    expect(quietDrive, inInclusiveRange(0.38, 1.0));
  });

  test('resolveForWaveform keeps diamonds when global tier is minimal', () {
    final budget = TorchEffectBudget.resolveForWaveform();
    expect(budget.profile, TorchContentProfile.music);
    expect(budget.diamondCount, greaterThan(0));
  });

  test('diamond prominence scales with waveform amplitude', () {
    expect(
      TorchPlumeEngine.diamondProminence(0.0),
      closeTo(0.72, 0.01),
    );
    expect(
      TorchPlumeEngine.diamondProminence(1.0),
      closeTo(1.0, 0.01),
    );
    expect(
      TorchPlumeEngine.resolveActiveDiamondCount(
        diamondCount: 8,
        waveformAmplitude: 0.0,
        engineScale: 1.0,
      ),
      5,
    );
    expect(
      TorchPlumeEngine.resolveActiveDiamondCount(
        diamondCount: 8,
        waveformAmplitude: 1.0,
        engineScale: 1.0,
      ),
      8,
    );
    expect(
      TorchPlumeEngine.resolveActiveDiamondCount(
        diamondCount: 8,
        waveformAmplitude: 1.0,
        engineScale: 0.58,
      ),
      greaterThanOrEqualTo(4),
    );
  });

  test('raptor palette leans white-blue not orange', () {
    const accent = Color(0xFFFF9F40);
    final core = TorchPlumeEngine.raptorCore(accent);
    final sheath = TorchPlumeEngine.raptorSheath(accent);
    final warm = TorchPlumeEngine.warmExhaust(accent);
    expect(core.green, greaterThan(accent.green));
    expect(sheath.blue, greaterThan(sheath.red));
    expect(sheath.blue, greaterThan(warm.blue));
    expect(sheath, isNot(equals(warm)));
  });

  test('waveform envelope scales track engine cluster width', () {
    final scales = TorchPlumeEngine.waveformEnvelopeScales(
      shipLen: 64,
      canvasHeight: 80,
    );
    expect(scales.top, lessThan(0.88));
    expect(scales.bottom, lessThan(0.80));
    expect(scales.top, greaterThan(scales.bottom * 0.9));
    final metrics = TorchPlumeEngine.engineMetrics(64);
    final clusterSpan = metrics.bellHalfW * 1.30 * 2;
    final throatHeight = 80 * scales.top * TorchPlumeEngine.waveformThroatScale;
    expect(throatHeight, lessThan(clusterSpan * 1.35));
  });

  test('waveform expansion scale tapers at nozzle and opens aft', () {
    const shipLen = 64.0;
    const nozzleX = 200.0;

    final atNozzle = TorchPlumeEngine.waveformExpansionScale(
      x: nozzleX,
      nozzleX: nozzleX,
      shipLen: shipLen,
    );
    final atThroatExit = TorchPlumeEngine.waveformExpansionScale(
      x: nozzleX - shipLen * 0.35,
      nozzleX: nozzleX,
      shipLen: shipLen,
    );
    final farAft = TorchPlumeEngine.waveformExpansionScale(
      x: 0,
      nozzleX: nozzleX,
      shipLen: shipLen,
    );

    expect(atNozzle, closeTo(TorchPlumeEngine.waveformThroatScale, 0.001));
    expect(atThroatExit, greaterThan(atNozzle));
    expect(farAft, closeTo(1.0, 0.001));
    expect(atThroatExit, lessThan(farAft));
  });

  test('engineMetrics matches ship bell proportions', () {
    final m = TorchPlumeEngine.engineMetrics(80);
    expect(m.shipWidth, 20);
    expect(m.bellHalfW, 8);
    expect(m.throatHalfW, closeTo(3.36, 0.01));
    expect(m.engineFaceOffset, 36);
  });

  test('profileFor maps content modes', () {
    expect(
      TorchEffectBudget.profileFor(ContentMode.audiobook),
      TorchContentProfile.audiobook,
    );
    expect(
      TorchEffectBudget.profileFor(ContentMode.music),
      TorchContentProfile.music,
    );
  });
}