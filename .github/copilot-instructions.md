# Playa — Copilot / AI Agent Instructions

Minimal, actionable context for immediate productivity in this Flutter music player codebase.

## Quick Summary
- **Flutter local-music player** targeting Windows and Android
- **Modular Architecture**: Services handle logic, screens for UI, models for data; main.dart for app setup and navigation shell
- **Playback**: `just_audio` + `just_audio_background` with custom physics-based turntable animations
- **Data**: Local library via `OnAudioQuery`; metadata/playlists persisted with `sqflite` database
- **Theme**: Dark glossy aesthetic with wood/walnut accents

## Architecture & Key Files

### Core Structure (`lib/main.dart`)
- **`PlayaApp`**: MaterialApp with dark theme, Exo2 font, dynamic accent color from settings
- **`_Shell`**: Navigation wrapper with `IndexedStack` for Library/Player tabs, glassmorphic bottom nav bar
- Background layers: Deep space stars/nebula when enabled (battery saver disables)

### Services (`lib/services/`)
- **`PlayerController`**: Singleton managing `AudioPlayer` instance, queue operations (`replaceQueue()`, `insertNext()`), bookmarks, sleep timer, session persistence
- **`SettingsService`**: `ChangeNotifier` singleton for app settings (battery saver, waveforms, screen wake, audio focus) via `SharedPreferences`
- **`DatabaseService`**: Sqflite-based persistence for song metadata (ratings, lyrics, play counts) and playlists
- **`EqualizerService`**: Android-only `MethodChannel` for native equalizer API (wrap calls in `try/catch` for Windows)
- **`LyricsService`**: Fetches synced lyrics from LRCLIB.net

### Screens (`lib/screens/`)
- **`LibraryPage`**: Song list with sorting, playlist management, context menus
- **`PlayerScreen`**: Turntable widget, waveforms, controls, lyrics sheet
- **`PlaylistsScreen`**, **`PlaylistDetailScreen`**: Playlist CRUD
- **`EqualizerScreen`**: Vertical sliders for Android equalizer
- **`SettingsScreen`**: App preferences UI

### Models (`lib/models/`)
- **`Song`**: From `OnAudioQuery`, extended with metadata
- **`Playlist`**: User/smart playlists with JSON serialization
- **`SongMetadata`**: Ratings, lyrics, play stats (Isar schema)
- **`DbSong`**, **`DbPlaylist`**: Isar entities (generated)

### UI Components (`lib/ui/`, `lib/widgets/`)
- **`TurntableWidget`**: Custom painter with physics (inertia, pitch), static specular highlights
- **`WaveformWidget`**: Audio visualization with "Epstein Drive" cursor effect
- **`DeepSpaceBackground`**: Animated stars/comets shader
- **`LyricsSheet`**: Synced scrolling lyrics display

### Repositories (`lib/repositories/`)
- **`SongRepository`**: Wraps `DatabaseService` for metadata operations
- **`PlaylistRepository`**: Playlist CRUD (currently SharedPreferences-based, planned Isar migration)

## Theme & Design System

### Colors (defined in `main.dart`)
```dart
const _bg = Color(0xFF06070A)         // Background
const _surface = Color(0xFF14161B)    // Cards/sheets
const _card = Color(0xFF1B1F26)       // List items
const _on = Color(0xFFE8DCCA)         // Primary text (light wood/beige)
const _on2 = Color(0xFFA68B6C)        // Secondary text (muted wood)
final _appAccent = Color(SettingsService.instance.accentColor) // Dynamic
```

### Typography
- Font: `GoogleFonts.exo2` applied to entire `TextTheme`
- AppBar: 20px bold, centered

### Material Design
- **Dark mode only**
- Glassmorphic nav bar: `BackdropFilter` with blur + border
- Card elevation: 0 (flat design with subtle alpha transparency)

## State Management Patterns

### Accessing Player State
```dart
final ctrl = PlayerController.ensure(); // Singleton accessor
// Access: ctrl.player (AudioPlayer), ctrl.currentMediaItem, ctrl.hasQueue
```

### Queue Mutations
```dart
await ctrl.replaceQueue([song1, song2]); // Replace entire queue
await ctrl.insertNext(song);             // Insert after current
await ctrl.playAt(index);                // Jump to index and play
```

### Bookmarks & Notes
```dart
ctrl.addBookmark(note: "Intro"); // Adds current position with optional note
ctrl.updateBookmarkNote(index, "My Note"); // Updates note
// Access: ctrl.bookmarks[i]['note'] (List<Map>)
```

### Listening to Track Changes
```dart
StreamBuilder<SequenceState?>(
  stream: player.sequenceState,
  builder: (context, snapshot) {
    final currentIndex = player.currentIndex ?? 0;
    // React to queue changes
  },
)
```

### Settings Reactivity
```dart
AnimatedBuilder(
  animation: SettingsService.instance,
  builder: (context, _) {
    final showWaveforms = SettingsService.instance.showWaveforms;
    // Rebuild on settings change
  },
)
```

## Cross-Platform Considerations

### Equalizer (Android-only)
```dart
if (Platform.isAndroid) {
  try {
    await EqualizerService.initializeEqualizer(sessionId);
  } on MissingPluginException {
    // Handle gracefully - Windows doesn't have this
  }
}
```

### Audio Query URIs
```dart
// In PlayerController._buildSource()
var uriString = song.uri;
if (uriString == null || uriString.isEmpty) {
  uriString = Platform.isAndroid
      ? "content://media/external/audio/media/${song.id}"
      : 'file://${song.data}';
}
```

### Permissions
Request before using `OnAudioQuery`:
```dart
await Permission.audio.request();
await Permission.storage.request();
await Permission.notification.request();
```

## Developer Workflows

### Running the App
```powershell
flutter run -d windows            # Desktop
flutter run -d <device-id>        # Android device
flutter devices                   # List available devices
```

### Debug Flags (via `--dart-define`)
```powershell
flutter run --dart-define=DEV_EQ_DEBUG=true    # Auto-open equalizer debug screen
flutter run --dart-define=DEV_TT_GUIDES=true   # Show turntable paint guides
```

### Build & Test
```powershell
flutter build windows --release
flutter build apk --release
flutter test
```

### Code Generation (if DB schemas change)
```powershell
# No code generation needed for sqflite
```

## Integration Points & Gotchas

### JustAudioBackground Initialization
**Critical**: Must be called before `runApp()` in `main()`:
```dart
await JustAudioBackground.init(
  androidNotificationChannelId: 'com.playa.channel.audio',
  androidNotificationChannelName: 'Playa Playback',
  androidNotificationOngoing: true,
);
```

### Audio Session Handling
`PlayerController._initAudioSession()` configures audio interruptions:
- Respects `SettingsService.instance.audioFocusMode` ('pause', 'duck', 'none')
- On duck: reduces volume to 0.3, restores to 1.0

### State Persistence
Player state saved to `SharedPreferences` in `PlayerController`:
- `lastPlayedUri`: Restore track on app restart
- `bookmarks_<songId>`: Per-song chapter markers with notes (JSON encoded)

### Library Scanning
```dart
final songs = await OnAudioQuery().querySongs(
  sortType: oaq.SongSortType.DATE_ADDED,
  orderType: oaq.OrderType.DESC_OR_GREATER,
  uriType: oaq.UriType.EXTERNAL,
);
```

## Modifying the Codebase

### Adding UI Features
1. Check `lib/ui/tokens.dart` for spacing/sizing constants (`kSp = 8.0`, `kRadius = 14.0`)
2. Use `_appAccent` or `SettingsService.instance.accentColor` for highlights
3. Maintain glassmorphic aesthetic (backdrop blur, subtle borders)

### Extending Player Logic
- Most logic in `PlayerController` class
- For new queue operations, follow `replaceQueue`/`insertNext` patterns
- Use `_buildSource()` helper for consistent `UriAudioSource` creation

### Platform-Specific Features
- Always guard with `Platform.isAndroid` / `Platform.isWindows`
- For Android native code, extend `MainActivity.kt` MethodChannel handler
- Test on both platforms before committing

### Database Operations
Use `DatabaseService` for metadata/playlists:
```dart
await DatabaseService.instance.updateRating(songId, rating);
final metadata = await DatabaseService.instance.getSongMetadata(songId);
```
