// lib/services/sonic_dna_scheduler.dart
import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart' as oaq;

import 'library_scan_service.dart';
import 'service_locator.dart';
import 'settings_service.dart';
import 'sonic_dna_analysis_service.dart';

/// Runs the full-library Sonic DNA analysis automatically while the device is
/// charging and the app is idle (onboarding complete, not scanning, library
/// populated). Auto-runs stop gracefully if the device is unplugged.
class SonicDnaScheduler {
  SonicDnaScheduler._();
  static final SonicDnaScheduler instance = SonicDnaScheduler._();

  /// Back-off between auto runs. Re-runs resume via the signature cache, so
  /// this only prevents pointless re-reads when nothing changed.
  static const Duration cooldown = Duration(hours: 6);

  /// Test hook: when set, overrides the real battery state so unit tests do
  /// not need the platform plugin.
  @visibleForTesting
  BatteryState? debugBatteryState;

  /// Test hooks: bypass the real library/analysis pipeline in unit tests.
  @visibleForTesting
  List<oaq.SongModel> Function()? songsOverride;
  @visibleForTesting
  Future<void> Function(List<oaq.SongModel> songs)? runAnalysisOverride;

  bool _started = false;
  bool _checking = false;
  bool _autoRunInProgress = false;
  DateTime? _lastAutoRunAt;
  BatteryState _lastKnownState = BatteryState.unknown;
  StreamSubscription<BatteryState>? _batterySub;

  bool get autoRunInProgress => _autoRunInProgress;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    LibraryScanService.instance.addListener(_onLibraryChanged);
    if (debugBatteryState == null) {
      try {
        _lastKnownState = await Battery().batteryState;
        _batterySub = Battery().onBatteryStateChanged.listen(handleBatteryState);
      } catch (e) {
        if (kDebugMode) debugPrint('SonicDnaScheduler: battery_plus unavailable: $e');
      }
    }
    await _checkAndRun();
  }

  void dispose() {
    _started = false;
    LibraryScanService.instance.removeListener(_onLibraryChanged);
    _batterySub?.cancel();
    _batterySub = null;
  }

  /// Resets singleton state between unit tests.
  @visibleForTesting
  void resetForTest() {
    dispose();
    _lastAutoRunAt = null;
    _autoRunInProgress = false;
    _checking = false;
    _lastKnownState = BatteryState.unknown;
  }

  /// Handles battery state changes: kicks off an auto-run when charging
  /// begins, and cancels an in-progress auto-run when the device is unplugged.
  /// Public so tests can drive it without the platform plugin.
  void handleBatteryState(BatteryState state) {
    _lastKnownState = state;
    if (state == BatteryState.charging || state == BatteryState.full) {
      unawaited(_checkAndRun());
    } else if (state == BatteryState.discharging) {
      if (_autoRunInProgress) {
        _autoRunInProgress = false;
        SonicDnaAnalysisService.instance.cancel();
      }
    }
  }

  void _onLibraryChanged() {
    if (!LibraryScanService.instance.isScanning) {
      unawaited(_checkAndRun());
    }
  }

  Future<void> _checkAndRun() async {
    if (_checking) return;
    _checking = true;
    try {
      if (!_started) return;
      if (!SettingsService.instance.onboardingComplete) return;
      if (LibraryScanService.instance.isScanning) return;
      final svc = SonicDnaAnalysisService.instance;
      if (svc.isRunning) return;
      if (_lastAutoRunAt != null &&
          DateTime.now().difference(_lastAutoRunAt!) < cooldown) {
        return;
      }

      final state = debugBatteryState ?? _lastKnownState;
      if (state != BatteryState.charging && state != BatteryState.full) return;

      final songs =
          songsOverride?.call() ??
          ServiceLocator.instance.playerController.librarySongs;
      if (songs.isEmpty) {
        return;
      }

      _lastAutoRunAt = DateTime.now();
      _autoRunInProgress = true;
      if (runAnalysisOverride != null) {
        await runAnalysisOverride!(songs);
      } else {
        await svc.startAnalysis(songs: songs);
      }
      _autoRunInProgress = false;
    } finally {
      _checking = false;
    }
  }
}
