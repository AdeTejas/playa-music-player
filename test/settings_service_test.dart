import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playa_clean/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
    (message) async => const StandardMessageCodec().encodeMessage(<Object?>[]),
  );

  test('SettingsService initializes and persists screensaver settings', () async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();

    expect(SettingsService.instance.screensaverEnabled, isFalse);
    expect(SettingsService.instance.screensaverIdleSeconds, 60);
    expect(SettingsService.instance.effectiveScreensaverEnabled, isFalse);

    await SettingsService.instance.setScreensaverEnabled(true);
    expect(SettingsService.instance.screensaverEnabled, isTrue);
    expect(SettingsService.instance.effectiveScreensaverEnabled, isTrue);

    await SettingsService.instance.setScreensaverIdleSeconds(45);
    expect(SettingsService.instance.screensaverIdleSeconds, 45);
  });

  test('SettingsService persists audio-effect settings', () async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();

    expect(SettingsService.instance.virtualizerEnabled, isFalse);
    expect(SettingsService.instance.virtualizerStrength, 500);
    expect(SettingsService.instance.bassBoostEnabled, isFalse);
    expect(SettingsService.instance.bassBoostStrength, 500);
    expect(SettingsService.instance.presetReverbEnabled, isFalse);
    expect(SettingsService.instance.presetReverbPreset, 0);

    await SettingsService.instance.setVirtualizerEnabled(true);
    await SettingsService.instance.setVirtualizerStrength(700);
    await SettingsService.instance.setBassBoostEnabled(true);
    await SettingsService.instance.setBassBoostStrength(400);
    await SettingsService.instance.setPresetReverbEnabled(true);
    await SettingsService.instance.setPresetReverbPreset(3);

    expect(SettingsService.instance.virtualizerEnabled, isTrue);
    expect(SettingsService.instance.virtualizerStrength, 700);
    expect(SettingsService.instance.bassBoostEnabled, isTrue);
    expect(SettingsService.instance.bassBoostStrength, 400);
    expect(SettingsService.instance.presetReverbEnabled, isTrue);
    expect(SettingsService.instance.presetReverbPreset, 3);
  });

  test('low performance mode gates effects without clobbering prefs',
      () async {
    await SettingsService.instance.setShowWaveforms(false);
    await SettingsService.instance.setShowSpaceBackground(false);
    await SettingsService.instance.setFrostedGlassBlur(true);
    await SettingsService.instance.setLibraryFrostedBackground(true);
    await SettingsService.instance.setKeepScreenOn(true);
    await SettingsService.instance.setScreensaverEnabled(true);

    await SettingsService.instance.setLowPerformanceMode(true);
    expect(SettingsService.instance.lowPerformanceMode, isTrue);
    expect(SettingsService.instance.effectiveShowWaveforms, isFalse);
    expect(SettingsService.instance.effectiveShowSpaceBackground, isFalse);
    expect(SettingsService.instance.effectiveFrostedGlassBlur, isFalse);
    expect(SettingsService.instance.effectiveLibraryFrostedBackground, isFalse);
    expect(SettingsService.instance.effectiveScreensaverEnabled, isFalse);

    expect(SettingsService.instance.showWaveforms, isFalse);
    expect(SettingsService.instance.showSpaceBackground, isFalse);
    expect(SettingsService.instance.frostedGlassBlur, isTrue);
    expect(SettingsService.instance.libraryFrostedBackground, isTrue);
    expect(SettingsService.instance.keepScreenOn, isTrue);
    expect(SettingsService.instance.screensaverEnabled, isTrue);

    await SettingsService.instance.setLowPerformanceMode(false);
    expect(SettingsService.instance.lowPerformanceMode, isFalse);
    expect(SettingsService.instance.effectiveShowWaveforms, isFalse);
    expect(SettingsService.instance.effectiveShowSpaceBackground, isFalse);
    expect(SettingsService.instance.effectiveFrostedGlassBlur, isTrue);
    expect(SettingsService.instance.effectiveLibraryFrostedBackground, isTrue);
    expect(SettingsService.instance.effectiveScreensaverEnabled, isTrue);

    expect(SettingsService.instance.showWaveforms, isFalse);
    expect(SettingsService.instance.showSpaceBackground, isFalse);
    expect(SettingsService.instance.frostedGlassBlur, isTrue);
    expect(SettingsService.instance.libraryFrostedBackground, isTrue);
    expect(SettingsService.instance.keepScreenOn, isTrue);
    expect(SettingsService.instance.screensaverEnabled, isTrue);
  });

  test('battery saver gates effects and wakelock without clobbering prefs',
      () async {
    await SettingsService.instance.setKeepScreenOn(true);
    await SettingsService.instance.setScreensaverEnabled(true);

    await SettingsService.instance.setBatterySaver(true);
    expect(SettingsService.instance.batterySaver, isTrue);
    expect(SettingsService.instance.effectiveShowWaveforms, isFalse);
    expect(SettingsService.instance.effectiveShowSpaceBackground, isFalse);
    expect(SettingsService.instance.effectiveScreensaverEnabled, isFalse);
    expect(SettingsService.instance.keepScreenOn, isTrue);
    expect(SettingsService.instance.screensaverEnabled, isTrue);

    await SettingsService.instance.setBatterySaver(false);
    expect(SettingsService.instance.batterySaver, isFalse);
    expect(SettingsService.instance.effectiveScreensaverEnabled, isTrue);
    expect(SettingsService.instance.keepScreenOn, isTrue);
    expect(SettingsService.instance.screensaverEnabled, isTrue);
  });
}
