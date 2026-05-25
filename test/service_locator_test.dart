import 'package:flutter_test/flutter_test.dart';
import 'package:playa_clean/services/service_locator.dart';
import 'package:playa_clean/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ServiceLocator overrides', () {
    tearDown(() {
      ServiceLocator.instance.resetOverrides();
    });

    test('defaults to real singletons when no override is set', () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.instance.init();

      final settings = ServiceLocator.instance.settings;
      expect(settings, same(SettingsService.instance));
      expect(settings.screensaverEnabled, isFalse);
    });

    test('allows overriding SettingsService and respects reset', () async {
      SharedPreferences.setMockInitialValues({});

      final fakeSettings = SettingsService.instance; // we can reuse the real one as "fake" for demo
      // In real tests you would use a mock or subclass.
      ServiceLocator.instance.settingsOverride = fakeSettings;

      final resolved = ServiceLocator.instance.settings;
      expect(resolved, same(fakeSettings));

      // After reset we fall back to the real singleton
      ServiceLocator.instance.resetOverrides();
      final afterReset = ServiceLocator.instance.settings;
      expect(afterReset, same(SettingsService.instance));
    });
  });
}
