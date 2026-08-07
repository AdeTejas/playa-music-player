import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:playa_clean/screens/onboarding_screen.dart';
import 'package:playa_clean/services/settings_service.dart';
import 'package:playa_clean/utils/content_mode.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();
  });

  Future<void> pumpOnboarding(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: OnboardingScreen()));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> settlePage(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> walkToFocus(WidgetTester tester) async {
    await tester.tap(find.text('Get Started'));
    await settlePage(tester);
    await tester.tap(find.text('Continue'));
    await settlePage(tester);
  }

  testWidgets('shows welcome page first', (tester) async {
    await pumpOnboarding(tester);

    expect(find.text('Playa'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
  });

  testWidgets('flows through access, focus, and telemetry pages', (
    tester,
  ) async {
    await pumpOnboarding(tester);

    await tester.tap(find.text('Get Started'));
    await settlePage(tester);
    expect(find.text('Access your music'), findsOneWidget);

    // Non-Android hosts need no permission, so the primary action is Continue.
    expect(find.text('Continue'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await settlePage(tester);
    expect(find.text('What are you into?'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await settlePage(tester);
    expect(find.text('Help improve Playa'), findsOneWidget);
    expect(find.text('Start Listening'), findsOneWidget);
  });

  testWidgets('focus choice persists the browse filter', (tester) async {
    await pumpOnboarding(tester);

    await walkToFocus(tester);

    await tester.tap(find.text('Audiobooks'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      SettingsService.instance.libraryBrowseFilter,
      LibraryBrowseFilter.audiobook,
    );
  });

  testWidgets('start listening marks onboarding complete', (tester) async {
    await pumpOnboarding(tester);

    await walkToFocus(tester);
    await tester.tap(find.text('Continue'));
    await settlePage(tester);

    await tester.tap(find.text('Start Listening'));
    await settlePage(tester);
    expect(SettingsService.instance.onboardingComplete, isTrue);
    expect(SettingsService.instance.telemetryConsentSeen, isTrue);
  });

  testWidgets('telemetry consent defaults to off (keep local)', (tester) async {
    await SettingsService.instance.setTelemetryConsent(false);
    await pumpOnboarding(tester);

    await walkToFocus(tester);
    await tester.tap(find.text('Continue'));
    await settlePage(tester);

    expect(SettingsService.instance.telemetryConsent, isFalse);
    expect(find.text('Keep everything local'), findsOneWidget);
  });

  testWidgets('choosing share enables anonymous telemetry', (tester) async {
    await SettingsService.instance.setTelemetryConsent(false);
    await pumpOnboarding(tester);

    await walkToFocus(tester);
    await tester.tap(find.text('Continue'));
    await settlePage(tester);

    await tester.tap(find.text('Share anonymous data'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(SettingsService.instance.telemetryConsent, isTrue);

    await tester.tap(find.text('Start Listening'));
    await settlePage(tester);
    expect(SettingsService.instance.onboardingComplete, isTrue);
  });
}
