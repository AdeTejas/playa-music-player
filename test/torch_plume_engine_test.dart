import 'dart:math';
import 'dart:ui' as ui;

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

  test('rocinante cluster has twin equal engines', () {
    final cluster = TorchPlumeEngine.rocinanteCluster(8);
    expect(cluster, hasLength(2));
    expect(cluster[0].scale, closeTo(0.55, 0.01));
    expect(cluster[1].scale, closeTo(0.55, 0.01));
    expect(cluster[0].offset, closeTo(-3.84, 0.01));
    expect(cluster[1].offset, closeTo(3.84, 0.01));
  });

  test('epstein cluster is center-dominant with flanking bells', () {
    final cluster = TorchPlumeEngine.epsteinCluster(8);
    expect(cluster, hasLength(3));
    expect(cluster[0].offset, 0.0);
    expect(cluster[0].scale, 1.0);
    expect(cluster[1].scale, closeTo(0.50, 0.01));
    expect(cluster[2].scale, closeTo(0.50, 0.01));
    expect(cluster[1].offset, closeTo(-7.6, 0.01));
    expect(cluster[2].offset, closeTo(7.6, 0.01));
    expect(cluster[1].offset, lessThan(cluster[0].offset));
    expect(cluster[2].offset, greaterThan(cluster[0].offset));
  });

  test('roci drive cluster is a single center bell', () {
    final cluster = TorchPlumeEngine.rociDriveCluster(8);
    expect(cluster, hasLength(1));
    expect(cluster[0].offset, 0.0);
    expect(cluster[0].scale, 1.0);
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
    expect(core.g, greaterThan(accent.g));
    expect(sheath.b, greaterThan(sheath.r));
    expect(sheath.b, greaterThan(warm.b));
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

  test('buildExhaustWaveformPath spans track width', () {
    final data = List<double>.generate(50, (i) => 0.5 + 0.4 * sin(i * 0.3));
    const width = 400.0;
    const height = 80.0;
    const centerY = 40.0;
    const shipLen = 64.0;
    const nozzleX = 300.0;

    final path = TorchPlumeEngine.buildExhaustWaveformPath(
      waveformData: data,
      width: width,
      height: height,
      centerY: centerY,
      nozzleX: nozzleX,
      shipLen: shipLen,
    );
    final bounds = path.getBounds();
    expect(bounds.width, closeTo(width, 2.0));
    expect(bounds.height, greaterThan(height * 0.15));
  });

  test('exhaustWaveformGradientColors uses raptor palette', () {
    const base = Color(0xFFC9A86A);
    final colors = TorchPlumeEngine.exhaustWaveformGradientColors(base);
    expect(colors, hasLength(4));
    expect(colors.first, TorchPlumeEngine.raptorCore(base));
  });

  test('engineMetrics matches ship bell proportions', () {
    final m = TorchPlumeEngine.engineMetrics(80);
    expect(m.shipWidth, 20);
    expect(m.bellHalfW, closeTo(10.26, 0.01));
    expect(m.throatHalfW, closeTo(4.51, 0.01));
    expect(m.engineFaceOffset, 40);
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

  test('waveformTinted horizontal plume paints without error', () {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final budget = TorchEffectBudget.resolveForWaveform();
    TorchPlumeEngine.paintHorizontalPlume(
      canvas: canvas,
      nozzleX: 200,
      centerY: 60,
      height: 120,
      shipLen: 96,
      baseColor: const Color(0xFFFF8A3D),
      animTimeSeconds: 3.5,
      beatStrength: 0.8,
      waveformAmplitude: 0.7,
      budget: budget,
      blendScale: TorchPlumeEngine.waveformBlendScale,
      cluster: TorchPlumeEngine.rociDriveCluster(
        TorchPlumeEngine.engineMetrics(96).bellHalfW,
      ),
      waveformTinted: true,
    );
    expect(recorder.endRecording(), isNotNull);
  });

  test('waveformTinted plume stays accent-coherent (no cool-blue clash)', () {
    const base = Color(0xFFFF8A3D);
    final tinted = TorchPlumeEngine.exhaustWaveformGradientColors(
      base,
      waveformAmplitude: 0.7,
    );
    final tintedBody = tinted[3];
    final sheath = TorchPlumeEngine.raptorSheath(base);
    // The tinted body keeps the accent hue exactly (only alpha varies)...
    expect(tintedBody.r, closeTo(base.r, 1e-6));
    expect(tintedBody.g, closeTo(base.g, 1e-6));
    expect(tintedBody.b, closeTo(base.b, 1e-6));
    // ...while the untinted plume sheath stays cool (much bluer than accent).
    expect(sheath.b, greaterThan(tintedBody.b));
    expect(sheath.g, greaterThan(tintedBody.g));
    expect(sheath.r, lessThan(tintedBody.r));
  });

  test('music full-tier budget enables waveform turbulence', () {
    final budget = TorchEffectBudget.resolve(profile: TorchContentProfile.music);
    expect(budget.drawTurbulence, isTrue);
  });

  test('audiobook budget disables waveform turbulence', () {
    final budget =
        TorchEffectBudget.resolve(profile: TorchContentProfile.audiobook);
    expect(budget.drawTurbulence, isFalse);
  });

  test('paintWaveformTurbulence paints without error when enabled', () {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const budget = TorchEffectBudget(
      tier: TorchEffectTier.full,
      profile: TorchContentProfile.music,
      plumeLengthMul: 1.0,
      plumeAlphaMul: 1.0,
      glowAlphaMul: 1.0,
      diamondCount: 8,
      outerBlur: 14.0,
      innerBlur: 6.0,
      coreBlur: 4.0,
      nozzleBlur: 8.0,
      drawOuterHalo: true,
      drawTurbulence: true,
      drawSecondGlow: true,
      drawSideIons: true,
    );

    final data = List<double>.filled(50, 0.5);
    final path = TorchPlumeEngine.buildExhaustWaveformPath(
      waveformData: data,
      width: 400,
      height: 80,
      centerY: 40,
      nozzleX: 300,
      shipLen: 64,
    );
    TorchPlumeEngine.paintWaveformTurbulence(
      canvas: canvas,
      path: path,
      nozzleX: 300,
      transitionWidth: 80,
      waveformAmplitude: 0.7,
      budget: budget,
    );
    expect(recorder.endRecording(), isNotNull);
  });
}
