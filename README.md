# Playa

Playa is a local audio player for **music and long-form listening** — audiobooks, podcasts, and multi-chapter files. It runs on **Android and Windows**, keeps your library on your device, and wraps playback in a hard sci-fi player: turntable hero, deep-space backgrounds, and a torch-drive ship scrubber you will not find in a stock player.

Built with Flutter. No account required. No cloud library.

**Repository:** [github.com/AdeTejas/playa-music-player](https://github.com/AdeTejas/playa-music-player)

---

## Who it is for

- **Audiobook listeners** — bookmarks, speed control, sleep timer, resume across chapters and series  
- **Music collectors** — playlists, shuffle/repeat, lyrics, equalizer, BPM/key-aware mixing  
- **Anyone tired of generic players** — a UI that feels designed, not templated  

---

## Highlights

### Playback
- Background playback with system media controls  
- Queue management, shuffle, and repeat  
- Gapless playback and optional crossfade  
- Configurable skip intervals (5–60 seconds)  

### Audiobooks and long-form
- **Bookmarks** with notes and jump-to-position  
- **Continue listening** — pick up series and chapters where you left off  
- Playback speed presets  
- Sleep timer with fade-out  
- Library filter: All · Music · Audiobooks  

### Library
- Local scan (Android MediaStore; Windows folder scan)  
- Manual and smart playlists  
- Favorites, ratings, and play-history hooks  
- Cached library bootstrap for faster reopen  

### Audio tools
- **Neural Mix** — harmonically matched queues from Sonic DNA (BPM, key, energy)  
- **ReplayGain** and smart volume limiting  
- **Equalizer** (Android native bands and presets)  
- **Synced lyrics** (LRCLIB)  
- **Waveforms** with procedural preview and envelope extraction  

### The look (signature UI)
- **Torch ship waveform** — animated scrubber with plasma plume and RCS detail  
- **Turntable Now Playing** — vinyl deck with sci-fi detailing  
- **Deep space backgrounds** — nebula and starfield with battery-aware rendering  
- **High-tech speaker** — Flower-of-Life resonator on the deck  
- Themes: Classic, Neon, Album-art accent; customizable colors  

### Privacy
Everything stays on your device — library, bookmarks, playlists, and listening progress. No server-side library sync.

**Telemetry is opt-in.** Playa never sends anything until you explicitly allow it (onboarding → Settings). If enabled, only anonymous crash reports and usage stats are shared (Sentry + PostHog) — never your library, titles, listening history, or personal data. It's off by default and you can change it anytime in **Settings → Privacy & Analytics**.

---

## Platforms

| Platform | Status |
|----------|--------|
| Android | Supported (Play Store–ready versioning in `pubspec.yaml`) |
| Windows | Supported |
| iOS | Not a current target |

---

## Screenshots

Now Playing — the turntable hero, torch-drive ship scrubber, and deep-space background:

![Now Playing](assets/screenshots/now_playing_hero.png)

---

## Getting started

### Prerequisites
- Flutter SDK 3.7.0+  
- Dart SDK  
- **Windows:** Visual Studio Build Tools  
- **Android:** Android SDK and a device or emulator  

### Clone and run

```bash
git clone https://github.com/AdeTejas/playa-music-player.git
cd playa-music-player
flutter pub get
```

```bash
# Windows
flutter run -d windows

# Android
flutter run -d <device-id>
```

### Release builds

```bash
# Android App Bundle
flutter build appbundle --release

# Windows
flutter build windows --release
```

Play Store checklist: [docs/PLAY_STORE_RELEASE.md](docs/PLAY_STORE_RELEASE.md)

---

## Usage (quick)

**Audiobooks**
1. Grant storage access and scan your library  
2. Tap bookmark during playback to save a moment  
3. Open the bookmarks list to jump back  
4. Set a sleep timer for bedtime listening  

**Music**
- Build playlists from the library  
- Rate tracks for smart playlists  
- Try Neural Mix from Now Playing for a harmonic queue  
- Open lyrics or the screensaver from the player chips  

---

## Documentation

| Doc | What it covers |
|-----|----------------|
| [docs/PITCH.md](docs/PITCH.md) | Product story, differentiators, buyer-oriented overview |
| [docs/PLAY_STORE_RELEASE.md](docs/PLAY_STORE_RELEASE.md) | Android release and signing checklist |
| [lib/design/README.md](lib/design/README.md) | Design system tokens and components |

---

## Architecture (short)

- **Services** — `PlayerController`, `SettingsService`, `DatabaseService`, `LibraryScanService`, `TelemetryService` (privacy-gated Sentry + PostHog)  
- **Persistence** — Sqflite for metadata, playlists, bookmarks, listening progress; SharedPreferences for settings  
- **UI** — Modular screens; custom painters (`TorchShipPainter`, turntable, waveforms, deep space)  
- **State** — `PlayerProvider` for playback; `ChangeNotifier` for settings  
- **Tests** — Bookmarks, resume soak, layout metrics, motion, torch engine, geometry, telemetry consent gate  

---

## Contributing

1. Fork the repository  
2. Create a feature branch (`git checkout -b feature/my-change`)  
3. Commit and push  
4. Open a pull request  

Run tests before submitting:

```bash
flutter test
flutter analyze lib/
```

---

## License

MIT — see [LICENSE](LICENSE).

---

## Contact

Questions or support: [paxpiece@gmail.com](mailto:paxpiece@gmail.com)