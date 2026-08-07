import 'package:flutter_test/flutter_test.dart';

import 'package:playa_clean/services/equalizer_service.dart';

void main() {
  // These run on the host (Windows), so Platform.isAndroid is false: every
  // EqualizerService call must no-op / return safe fallbacks without touching
  // the method channel.
  test('initialize is a no-op outside Android', () async {
    await EqualizerService.initializeEqualizer(0);
  });

  test('effects report unsupported outside Android', () async {
    expect(await EqualizerService.getVirtualizerSupported(), isFalse);
    expect(await EqualizerService.getBassBoostSupported(), isFalse);
    expect(await EqualizerService.getVirtualizerStrength(), 0);
    expect(await EqualizerService.getBassBoostStrength(), 0);
    expect(await EqualizerService.isVirtualizerEnabled(), isFalse);
    expect(await EqualizerService.isBassBoostEnabled(), isFalse);
  });

  test('reverb falls back to empty preset list outside Android', () async {
    expect(await EqualizerService.getPresetReverbPresets(), isEmpty);
    expect(await EqualizerService.getCurrentPresetReverb(), 0);
    expect(await EqualizerService.isPresetReverbEnabled(), isFalse);
  });

  test('setters and release no-op outside Android', () async {
    await EqualizerService.setVirtualizerStrength(500);
    await EqualizerService.setVirtualizerEnabled(true);
    await EqualizerService.setBassBoostStrength(400);
    await EqualizerService.setBassBoostEnabled(true);
    await EqualizerService.usePresetReverb(2);
    await EqualizerService.setPresetReverbEnabled(true);
    await EqualizerService.release();
  });

  test('restoreEffectsFromSettings is a no-op outside Android', () async {
    await EqualizerService.restoreEffectsFromSettings();
  });
}
