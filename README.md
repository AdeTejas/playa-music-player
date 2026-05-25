# Playa - Audio Book Player

A sleek, dark-themed music and audio book player built with Flutter, featuring an immersive hard sci-fi aesthetic and a unique animated torch ship waveform progress bar. Designed for deep listening with advanced bookmarking and library tools.

## ✨ Features

### Core Playback
- **Cross-Platform:** Windows and Android support
- **Background Playback:** Continues playing when app is minimized
- **Queue Management:** Add, remove, and reorder tracks
- **Shuffle & Repeat:** Full control over playback modes

### Audio Book Focused
- **Bookmarks:** Save and manage timestamps for interesting parts of audio books
- **Chapters:** Navigate through book sections
- **Sleep Timer:** Auto-pause after set duration

### Library Management
- **Local Library:** Scan and organize your music/audio book collection
- **Playlists:** Create, edit, and manage custom playlists
- **Smart Playlists:** Auto-generated based on play history (Most Played, Recently Added, etc.)
- **Ratings:** Rate your favorite tracks/books

### Audio Enhancements
- **Neural Mix:** Generate intelligent, harmonically matched playlists based on Sonic DNA (BPM, Key) and Energy modes (Up, Down, Neutral).
- **Smart Volume:** Automatic loudness normalization and peak limiting using ReplayGain tags to ensure consistent volume and prevent clipping.
- **Equalizer:** Android-native equalizer controls (bands, presets).
- **Lyrics Sync:** Display synced lyrics (LRCLIB integration).
- **Waveforms:** Visual audio representation.
- **Sonic DNA:** Analyze BPM and key for tracks to power harmonic mixing.
- **Signature Visual:** The torch ship progress indicator (detailed hard sci-fi vessel with reactive plasma drive effects) is the app's signature element and available as a standalone reusable painter.

### Immersive Hard Sci-Fi UI
- **Torch Ship Waveform:** Custom animated progress bar featuring a detailed torch-drive corvette with plasma effects, engine plume, and dynamic markings
- **Reusable Component:** The `TorchShipPainter` is self-contained and ready to drop into other Flutter projects (open-source friendly)
- **Turntable UI:** Custom animated turntable with sci-fi detailing
- **Deep Space Backgrounds:** Subtle drifting nebulae and starfields
- **Battery Optimization:** Respects battery saver settings
- **Accessibility:** Screen reader support for key controls

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (3.7.0+)
- Dart SDK
- For Windows: Visual Studio Build Tools
- For Android: Android SDK, device/emulator

### Installation
1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/playa.git
   cd playa
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run on your platform:
   ```bash
   # Windows
   flutter run -d windows

   # Android
   flutter run -d <device-id>
   ```

### Build Release
```bash
# Android AAB
flutter build appbundle --release

# Windows
flutter build windows --release
```

## 📱 Usage

### For Audio Books
1. **Import Library:** Grant storage permissions to scan your audio files
2. **Bookmark Moments:** Tap the bookmark icon during playback to save timestamps
3. **Navigate Chapters:** Use the bookmarks list to jump to saved sections
4. **Sleep Timer:** Set auto-pause for bedtime listening

### Playlists & Ratings
- Create playlists from your library
- Rate tracks to build smart playlists
- Access "Heavy Rotation" for most played content

## 🛠️ Architecture

- **Services:** Singleton pattern for PlayerController, SettingsService, DatabaseService
- **Persistence:** Sqflite database for metadata, playlists, and bookmarks
- **UI:** Modular screens with custom widgets (TurntableWidget, WaveformWidget, TorchShipPainter)
- **State Management:** InheritedWidget for player state, ChangeNotifier for settings

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📞 Contact

For questions or support: [paxpiece@gmail.com]

---

**Note:** This app stores all data locally on your device. No data is transmitted to external servers.
