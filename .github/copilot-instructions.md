# Playa — AI Agent Instructions

Flutter local-audio player (Windows + Android). Start with `lib/main.dart` for app bootstrap, theme tokens, and platform init.

## Big Picture
- UI lives in `lib/screens/` (tabs + pages); heavy logic stays in singletons under `lib/services/`.
- Playback is centered on `PlayerController` (`lib/services/player_controller.dart`) wrapping `just_audio` + queue/state restore.
- Persistence is split:
  - `SharedPreferences` for settings + “last session” (`SettingsService`, `PlayerController._saveState()`)
  - SQLite (`sqflite`) for song metadata + playlists (`DatabaseService` in `lib/services/database_service.dart`)

## Key Conventions (follow these)
- Service access is singleton-style: `PlayerController.ensure()` and `SettingsService.instance`.
- Settings-driven UI rebuild uses `AnimatedBuilder(animation: SettingsService.instance, ...)` (see `lib/main.dart`).
- Desktop SQLite needs FFI init; keep this in `main()` before opening DB (`sqfliteFfiInit()` + `databaseFactoryFfi`).

## Platform Differences / Integration Points
- Android library scan uses `on_audio_query` (`lib/services/android_audio_query.dart`) and needs runtime permissions (`PermissionsService`).
- Windows library scan is manual (`lib/services/windows_audio_query.dart`).
- Android external “open with” intents are handled by `IntentHandler` (`lib/services/intent_handler.dart`) and forwarded to `PlayerController.playExternalFile()` (see `lib/main.dart`).
- Android-only EQ uses `EqualizerService` + audio session id from `just_audio` (wired in `PlayerController`).

## Developer Workflows (PowerShell)
```powershell
flutter pub get
flutter run -d windows
flutter test
```

## Useful Debug Flags
- `--dart-define=DEV_TT_GUIDES=true` enables turntable paint guides (`kDevPaintTurntableGuides` in `lib/main.dart`).
- `--dart-define=AUTO_PLAYBACK_TEST=true` runs an automated playback scenario (`_runAutoPlaybackTest` in `lib/main.dart`).

## Where To Look First
- App/theme/bootstrap: `lib/main.dart` (theme tokens, `JustAudioBackground.init`, intent wiring)
- Playback + queue + state restore: `lib/services/player_controller.dart`
- Persistence schema: `lib/services/database_service.dart`
- Settings + perf/battery toggles: `lib/services/settings_service.dart`
- UI widgets: `lib/widgets/` and `lib/ui/` (tokens/shaders/background)
