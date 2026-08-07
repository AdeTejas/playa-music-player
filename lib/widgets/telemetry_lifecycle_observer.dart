// lib/widgets/telemetry_lifecycle_observer.dart
// Tracks app lifecycle for session analytics (app_open, foreground/background).
// All events are privacy-gated by TelemetryService consent.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../services/telemetry_service.dart';

class TelemetryLifecycleObserver extends StatefulWidget {
  const TelemetryLifecycleObserver({super.key, required this.child});

  final Widget child;

  @override
  State<TelemetryLifecycleObserver> createState() =>
      _TelemetryLifecycleObserverState();
}

class _TelemetryLifecycleObserverState extends State<TelemetryLifecycleObserver>
    with WidgetsBindingObserver {
  DateTime? _foregroundSince;
  bool _sentAppOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onAppOpen());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onAppOpen() {
    if (_sentAppOpen) return;
    _sentAppOpen = true;
    _foregroundSince = DateTime.now();
    unawaited(
      TelemetryService.instance.track(
        'app_open',
        properties: {
          'platform': defaultTargetPlatform.name,
          'install_id': TelemetryService.instance.installId,
          'app_version': TelemetryService.instance.appVersion,
        },
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _foregroundSince = DateTime.now();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
        final start = _foregroundSince;
        _foregroundSince = null;
        if (start != null) {
          final seconds = DateTime.now()
              .difference(start)
              .inSeconds
              .clamp(0, 60 * 60 * 12);
          unawaited(
            TelemetryService.instance.track(
              'app_background',
              properties: {'session_seconds': seconds},
            ),
          );
        }
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
