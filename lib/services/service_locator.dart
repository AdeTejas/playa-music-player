import 'player_controller.dart';
import 'settings_service.dart';
import 'database_service.dart';
import 'library_scan_service.dart';

/// Very lightweight service locator / registry.
///
/// Purpose: give tests a single place to override services (e.g. fake DB, fake player)
/// without changing every call site from `XxxService.instance` to something else.
///
/// Usage in production code stays the same for now (we still use the .instance singletons directly).
/// In the future we can migrate hot paths to `ServiceLocator.instance.playerController`.
///
/// For tests:
///   ServiceLocator.instance.playerControllerOverride = FakePlayerController();
class ServiceLocator {
  ServiceLocator._();
  static final ServiceLocator instance = ServiceLocator._();

  // === Overrides for testing ===
  PlayerController? _playerOverride;
  SettingsService? _settingsOverride;
  DatabaseService? _dbOverride;
  LibraryScanService? _scanOverride;

  PlayerController get playerController =>
      _playerOverride ?? PlayerController.ensure();

  SettingsService get settings =>
      _settingsOverride ?? SettingsService.instance;

  DatabaseService get database =>
      _dbOverride ?? DatabaseService.instance;

  LibraryScanService get libraryScan =>
      _scanOverride ?? LibraryScanService.instance;

  // Reset all overrides (call in test tearDown)
  void resetOverrides() {
    _playerOverride = null;
    _settingsOverride = null;
    _dbOverride = null;
    _scanOverride = null;
  }

  // Convenience setters
  set playerControllerOverride(PlayerController? v) => _playerOverride = v;
  set settingsOverride(SettingsService? v) => _settingsOverride = v;
  set databaseOverride(DatabaseService? v) => _dbOverride = v;
  set libraryScanOverride(LibraryScanService? v) => _scanOverride = v;
}
