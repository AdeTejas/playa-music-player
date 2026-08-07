import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:playa_clean/services/settings_service.dart';
import 'package:playa_clean/services/telemetry_service.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();
  });

  group('TelemetryService privacy gate', () {
    test('telemetry consent defaults to off', () {
      expect(SettingsService.instance.telemetryConsent, isFalse);
      expect(TelemetryService.instance.consentGranted, isFalse);
    });

    test('is inert when no keys are configured (test builds)', () async {
      await SettingsService.instance.setTelemetryConsent(false);

      final svc = TelemetryService.instance;
      await svc.grantConsent();

      // Consent is recorded, but without build keys the SDKs never start.
      expect(SettingsService.instance.telemetryConsent, isTrue);
      expect(svc.isConfigured, isFalse);

      await svc.revokeConsent();
      expect(SettingsService.instance.telemetryConsent, isFalse);
    });

    test('track and capture are safe no-ops before configuration', () async {
      final svc = TelemetryService.instance;
      await expectLater(
        svc.track('app_open', properties: {'platform': 'android'}),
        completes,
      );
      await expectLater(
        svc.captureException(StateError('boom'), StackTrace.current),
        completes,
      );
    });

    test('anonymous install id is minted once and stays stable', () async {
      await TelemetryService.instance.init();
      final first = TelemetryService.instance.installId;

      await TelemetryService.instance.init();
      final second = TelemetryService.instance.installId;

      expect(first, isNotEmpty);
      expect(second, equals(first));
      expect(TelemetryService.instance.isInstallIdReady, isTrue);
    });
  });

  group('TelemetryService.sanitizeEventForSend', () {
    test('strips sensitive content-metadata keys', () {
      final event = PostHogEvent(
        event: 'track_play_started',
        properties: {
          'content_type': 'music',
          'duration_seconds': 240,
          'artist': 'Some Band',
          'path': '/sdcard/Music/song.mp3',
        },
      );

      final result = TelemetryService.sanitizeEventForSend(event);

      expect(result, isNotNull);
      expect(result!.properties, isNotNull);
      expect(result.properties!['content_type'], 'music');
      expect(result.properties!['duration_seconds'], 240);
      expect(result.properties!.containsKey('artist'), isFalse);
      expect(result.properties!.containsKey('path'), isFalse);
    });

    test('drops windows and posix absolute paths from string values', () {
      PostHogEvent? sanitize(String value) {
        final event = PostHogEvent(event: 'test', properties: {'value': value});
        return TelemetryService.sanitizeEventForSend(event);
      }

      expect(sanitize(r'C:\Users\Green\Music\track.mp3')!.properties, isEmpty);
      expect(sanitize('D:/Music/track.flac')!.properties, isEmpty);
      expect(sanitize('/sdcard/Music/track.mp3')!.properties, isEmpty);
      expect(sanitize('~/Music/track.mp3')!.properties, isEmpty);
      expect(
        sanitize('a plain song name')!.properties!['value'],
        'a plain song name',
      );
    });

    test('leaves benign events untouched', () {
      final event = PostHogEvent(
        event: 'app_open',
        properties: {'platform': 'windows', 'session_seconds': 42},
      );

      final result = TelemetryService.sanitizeEventForSend(event);

      expect(result, isNotNull);
      expect(result!.properties!['platform'], 'windows');
      expect(result.properties!['session_seconds'], 42);
    });
  });
}
