import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:playa_clean/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
}
