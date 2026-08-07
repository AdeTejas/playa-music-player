// lib/services/telemetry_service.dart
// Privacy-first crash reporting + retention analytics.
//
// Everything here is gated behind an explicit opt-in consent stored in
// SettingsService. Until the user grants consent, no SDK is initialized and
// nothing leaves the device. SDK keys are supplied at build time via
// --dart-define and are never committed to the repository.
//
//   PLAYA_SENTRY_DSN      Sentry DSN (empty = Sentry inert)
//   PLAYA_POSTHOG_KEY     PostHog project token (empty = PostHog inert)
//   PLAYA_POSTHOG_HOST    PostHog ingestion host (defaults to US cloud)
//   PLAYA_TELEMETRY_DEBUG Set true to enable telemetry in debug builds
//
// Telemetry is also suppressed in debug builds unless PLAYA_TELEMETRY_DEBUG
// is set, so developer sessions never pollute production data.

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'settings_service.dart';

/// Build-time telemetry configuration.
class TelemetryConfig {
  const TelemetryConfig._();

  static const String sentryDsn = String.fromEnvironment('PLAYA_SENTRY_DSN');
  static const String posthogKey = String.fromEnvironment('PLAYA_POSTHOG_KEY');
  static const String posthogHost = String.fromEnvironment(
    'PLAYA_POSTHOG_HOST',
    defaultValue: 'https://us.i.posthog.com',
  );
  static const bool debugOverride = bool.fromEnvironment(
    'PLAYA_TELEMETRY_DEBUG',
  );

  static bool get hasAnyKeys => sentryDsn.isNotEmpty || posthogKey.isNotEmpty;

  /// Release-only unless explicitly overridden for local testing.
  static bool get enabledBuild => kReleaseMode || debugOverride;
}

class TelemetryService {
  TelemetryService._();

  static final TelemetryService instance = TelemetryService._();

  static const String _installIdKey = 'telemetry_install_id';

  // Deny-list of property names that must never leave the device. We never
  // attach these today; this is a safety net for future callers.
  static const Set<String> _sensitivePropertyKeys = {
    'title',
    'track_title',
    'song_title',
    'artist',
    'album',
    'genre',
    'path',
    'file_path',
    'uri',
    'url',
    'query',
    'note',
    'bookmark',
  };

  bool _consent = false;
  bool _configured = false;
  bool _sdkStarted = false;
  bool _installIdReady = false;
  String _installId = '';
  String _appVersion = 'unknown';

  /// Whether the current build is allowed to send telemetry at all.
  bool get enabledBuild => TelemetryConfig.enabledBuild;

  /// Whether the user has explicitly opted in.
  bool get consentGranted => _consent;

  /// Whether the SDKs are actually initialized.
  bool get isConfigured => _configured;

  /// Stable, anonymous, per-install identifier (never a device identifier).
  String get installId => _installId;

  /// App version in `1.0.0+1` form, populated once configured.
  String get appVersion => _appVersion;

  /// True once the anonymous install id has been loaded or minted.
  bool get isInstallIdReady => _installIdReady;

  /// Must be called once at startup, after SettingsService has loaded consent.
  Future<void> init() async {
    await _loadInstallId();
    _consent = SettingsService.instance.telemetryConsent;
    if (_consent && enabledBuild && TelemetryConfig.hasAnyKeys) {
      await _configure();
    }
  }

  /// Records explicit opt-in and starts the SDKs (release builds only).
  Future<void> grantConsent() async {
    if (_consent) return;
    _consent = true;
    await SettingsService.instance.setTelemetryConsent(true);

    if (!TelemetryConfig.hasAnyKeys || !enabledBuild) return;
    if (_configured) return;

    if (_sdkStarted) {
      // Re-enable after a revoke; never re-run setup() on the same singleton.
      try {
        await Posthog().enable();
      } catch (_) {}
      try {
        await _configureSentry();
      } catch (_) {}
      _configured = true;
    } else {
      await _configure();
    }
  }

  /// Records opt-out and shuts the SDKs down so nothing is captured or sent.
  Future<void> revokeConsent() async {
    if (!_consent) return;
    _consent = false;
    await SettingsService.instance.setTelemetryConsent(false);

    if (!_sdkStarted) return;
    try {
      await Posthog().disable();
    } catch (_) {}
    try {
      await Sentry.close();
    } catch (_) {}
    _configured = false;
  }

  /// Fire an analytics event. No-op unless consent + config are active.
  Future<void> track(String name, {Map<String, Object>? properties}) async {
    if (!_configured || !_consent) return;
    try {
      await Posthog().capture(eventName: name, properties: properties);
    } catch (_) {}
  }

  /// Report a caught exception to Sentry. No-op unless consent + config.
  Future<void> captureException(
    Object exception,
    StackTrace stackTrace, {
    Map<String, Object?> context = const {},
  }) async {
    if (!_configured || !_consent) return;
    try {
      await Sentry.captureException(
        exception,
        stackTrace: stackTrace,
        withScope: (scope) {
          for (final e in context.entries) {
            scope.setTag(e.key, '${e.value}');
          }
        },
      );
    } catch (_) {}
  }

  /// Report an unhandled Flutter framework error.
  Future<void> captureFlutterError(FlutterErrorDetails details) async {
    if (!_configured || !_consent) return;
    try {
      await Sentry.captureException(
        details.exception,
        stackTrace: details.stack,
        withScope: (scope) {
          if (details.library != null && details.library!.isNotEmpty) {
            scope.setTag('flutter.library', details.library!);
          }
          final context = details.context?.toDescription();
          if (context != null && context.isNotEmpty) {
            scope.setTag('flutter.context', context);
          }
        },
      );
    } catch (_) {}
  }

  /// Report an unhandled platform / runtime error.
  Future<void> capturePlatformError(Object error, StackTrace stackTrace) async {
    if (!_configured || !_consent) return;
    try {
      await Sentry.captureException(error, stackTrace: stackTrace);
    } catch (_) {}
  }

  Future<void> _loadInstallId() async {
    if (_installIdReady) return;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_installIdKey);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(_installIdKey, id);
    }
    _installId = id;
    _installIdReady = true;
  }

  Future<void> _configure() async {
    _configured = true;
    _sdkStarted = true;
    final info = await PackageInfo.fromPlatform();
    _appVersion = '${info.version}+${info.buildNumber}';

    if (TelemetryConfig.posthogKey.isNotEmpty) {
      try {
        await _configurePostHog();
      } catch (_) {}
    }
    if (TelemetryConfig.sentryDsn.isNotEmpty) {
      try {
        await _configureSentry();
      } catch (_) {}
    }
  }

  Future<void> _configurePostHog() async {
    final config = PostHogConfig(TelemetryConfig.posthogKey);
    config.host = TelemetryConfig.posthogHost;

    // Privacy posture: anonymous only. No session replay, no surveys, no
    // feature flags, no push tracking, no person profiles, no error tracking
    // (Sentry owns errors).
    config.sessionReplay = false;
    config.surveys = false;
    config.sendFeatureFlagEvents = false;
    config.preloadFeatureFlags = false;
    config.capturePushNotificationSubscriptions = false;
    config.capturePushNotificationOpened = false;
    config.personProfiles = PostHogPersonProfiles.never;
    config.errorTrackingConfig.captureFlutterErrors = false;
    config.errorTrackingConfig.capturePlatformDispatcherErrors = false;
    config.errorTrackingConfig.captureIsolateErrors = false;
    config.errorTrackingConfig.captureNativeExceptions = false;

    // Lifecycle presence events ($app_installed/$app_updated/$app_foreground)
    // power DAU/WAU retention cohorts on mobile.
    config.captureApplicationLifecycleEvents = true;

    // Flush promptly so sessions/background events are not lost.
    config.flushAt = 5;
    config.flushInterval = const Duration(seconds: 10);

    // Safety net: strip anything that resembles local content metadata.
    config.beforeSend = [sanitizeEventForSend];

    await Posthog().setup(config);
    if (_installId.isNotEmpty) {
      await Posthog().register('install_id', _installId);
    }
  }

  Future<void> _configureSentry() async {
    await SentryFlutter.init((options) {
      options.dsn = TelemetryConfig.sentryDsn;
      options.environment = kReleaseMode ? 'production' : 'development';
      options.release = 'playa@$_appVersion';
      // Crash + error reporting only; no performance tracing.
      options.tracesSampleRate = 0.0;
      options.sendDefaultPii = false;
      options.attachStacktrace = true;
      options.beforeSend = (event, hint) {
        event.user = SentryUser(id: _installId.isEmpty ? null : _installId);
        event.tags = {...?event.tags, 'install_id': _installId};
        return event;
      };
    });
  }

  /// Drops sensitive property keys and absolute file paths before upload.
  ///
  /// Public so the privacy contract is unit-testable.
  static PostHogEvent? sanitizeEventForSend(PostHogEvent event) {
    final props = event.properties;
    if (props == null) return event;

    final sanitized = <String, Object>{};
    props.forEach((key, value) {
      if (_sensitivePropertyKeys.contains(key.toLowerCase())) return;
      if (value is String && _looksLikeLocalPath(value)) return;
      sanitized[key] = value;
    });
    event.properties = sanitized;
    return event;
  }

  static bool _looksLikeLocalPath(String value) {
    final v = value.trim();
    if (v.isEmpty) return false;
    final isWindowsPath = RegExp(r'^[A-Za-z]:[\\/]').hasMatch(v);
    final isPosixPath = RegExp(r'^(/|~/|\.{1,2}/)').hasMatch(v);
    return isWindowsPath || isPosixPath;
  }
}
