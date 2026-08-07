// On-device consent-flow driver: boots the real app, walks onboarding to the
// telemetry page, opts in, and verifies the choice persists to real storage.
//
// Pre-grant the audio permission so no native dialog blocks the test:
//
//   adb shell pm grant com.paxpiece.playa android.permission.READ_MEDIA_AUDIO
//
// Then run:
//
//   flutter drive \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/onboarding_consent_drive_test.dart \
//     -d <device-id>
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:playa_clean/main.dart' as app;
import 'package:playa_clean/services/settings_service.dart';
import 'package:playa_clean/services/telemetry_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('fresh-install consent flow: opt-in persists on device', (
    tester,
  ) async {
    // Deterministic starting point: fresh install, telemetry off by default.
    await SettingsService.instance.init();
    await SettingsService.instance.setTelemetryConsent(false);
    await SettingsService.instance.setTelemetryConsentSeen(false);
    await SettingsService.instance.setOnboardingComplete(false);
    expect(SettingsService.instance.telemetryConsent, isFalse);

    // Boot the real application (services, telemetry, player, UI).
    await app.main();
    await tester.pump(const Duration(seconds: 2));

    // Page 1 — welcome.
    expect(find.text('Playa'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    await tester.tap(find.text('Get Started'));
    await tester.pump(const Duration(milliseconds: 600));

    // Page 2 — access. The permission is pre-granted via adb (see header),
    // so tapping Allow Access flips straight to granted with no dialog.
    expect(find.text('Access your music'), findsOneWidget);
    if (find.text('Allow Access').evaluate().isNotEmpty) {
      await tester.tap(find.text('Allow Access'));
      await tester.pump(const Duration(milliseconds: 800));
    }
    expect(find.text('Continue'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 600));

    // Page 3 — focus.
    expect(find.text('What are you into?'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 600));

    // Page 4 — telemetry choice.
    expect(find.text('Help improve Playa'), findsOneWidget);
    expect(find.text('Keep everything local'), findsOneWidget);
    expect(SettingsService.instance.telemetryConsentSeen, isTrue);
    expect(SettingsService.instance.telemetryConsent, isFalse);
    // No SDK keys in this build → telemetry must stay inert even when
    // consent is granted (privacy gate holds at the process level too).
    expect(TelemetryService.instance.isConfigured, isFalse);

    // Opt in.
    await tester.tap(find.text('Share anonymous data'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(SettingsService.instance.telemetryConsent, isTrue);

    // Finish onboarding → shell appears.
    await tester.tap(find.text('Start Listening'));
    await tester.pump(const Duration(seconds: 1));
    expect(SettingsService.instance.onboardingComplete, isTrue);

    // Persistence on real device storage (survives process restart).
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('telemetryConsent'), isTrue);
    expect(prefs.getBool('telemetryConsentSeen'), isTrue);
    expect(prefs.getBool('onboardingComplete'), isTrue);
  });
}
