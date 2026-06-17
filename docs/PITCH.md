# Playa — product overview

This page is for anyone evaluating Playa as a product, acquisition, or white-label base — investors, partners, or buyers who want the story without spelunking the whole codebase.

For install and build instructions, see the [main README](../README.md).

---

## One-liner

**Playa is a privacy-first local music and audiobook player for Android and Windows**, with long-form listening tools (bookmarks, series resume, speed, sleep timer) and a distinctive hard sci-fi player UI powered by Flutter.

---

## The problem it solves

Most local players are either **plain utilities** (fine for MP3s, weak for audiobooks) or **streaming apps** (accounts, cloud lock-in). Playa targets people who **own their files** and want:

- Reliable **multi-chapter and series resume**  
- **Bookmarks** and speed control for long-form audio  
- A **music experience** that goes beyond shuffle — BPM/key awareness, lyrics, equalizer  
- A player that **feels premium** without subscription baggage  

---

## Who it is for

| Audience | What they get |
|----------|----------------|
| Audiobook and podcast listeners | Bookmarks, continue listening, chapter-friendly skip, speed presets |
| Music collectors | Local library, playlists, Neural Mix, ReplayGain, lyrics |
| Design-conscious users | Turntable + torch-ship scrubber, deep-space visuals |
| Privacy-minded users | 100% on-device library and progress |

---

## What makes it different

### 1. Signature visual IP
Custom turntable, torch-ship progress bar, plasma plume physics, RCS thruster detail, and sacred-geometry speaker art. This is not a Material theme reskin — the painters are reusable (`TorchShipPainter`, waveform engine, deep space layers).

### 2. Dual-mode intelligence
Playa detects **music vs audiobook** and adapts the Now Playing layout: calm waveform and speed tools for long-form; full motion and mixing tools for music.

### 3. Sonic DNA and Neural Mix
Reads BPM and key from tags (ID3, FLAC, Vorbis). Neural Mix builds harmonically aware queues with energy modes (Up, Down, Neutral).

### 4. Long-form resume (hardened)
Listening progress per series/album, continue-listening UI, canonical path keys for bookmarks, and soak-tested multi-chapter resume logic.

### 5. Local-first architecture
Sqflite + preferences on device. No mandatory backend. Good fit for privacy positioning and offline-first markets.

### 6. Cross-platform codebase
Single Flutter app: **Android** (release versioning in place) and **Windows** desktop. Shared player, library, and UI logic.

### 7. Performance-aware polish
Battery saver, low-performance mode, adaptive deep-space frame budget, cached nebula layers, and layout metrics that keep Now Playing on-screen without scroll.

---

## Feature inventory (buyer checklist)

### Core playback
- Background playback and media session integration  
- Queue, shuffle, repeat  
- Gapless playback; optional crossfade  
- Audio focus (pause / duck / none)  
- Configurable seek skip (5–60 s)  

### Audiobook and long-form
- Bookmarks with notes  
- Continue listening  
- Multi-chapter / series resume  
- Playback speed  
- Sleep timer with fade  
- Library browse filter (All / Music / Audiobooks)  

### Library and playlists
- Local library scan (Android + Windows paths)  
- Manual playlists  
- Smart playlists (play history, ratings)  
- Favorites  
- Scan cache for faster library reopen  

### Audio enhancements
- Android equalizer  
- ReplayGain + smart volume limiter  
- Synced lyrics (LRCLIB)  
- Waveforms (procedural fallback + native extract)  
- Sonic DNA (BPM / key)  

### UI and brand
- Now Playing: turntable hero + scaled control dock  
- Torch ship waveform  
- Deep space HDR backgrounds  
- Screensaver mode  
- Multiple themes and accent customization  
- Accessibility labels on key controls  

### Engineering signals
- Modular service layer  
- Automated test suite (bookmarks, resume, layout, motion, torch engine)  
- Diagnostics screen  
- CI workflow  
- MIT license  

---

## Privacy and compliance angle

- **No cloud library** — metadata and progress stay on the device  
- **No account required** for core use  
- Straightforward story for GDPR-conscious users and markets that care about local-only apps  

Review [PLAY_STORE_RELEASE.md](PLAY_STORE_RELEASE.md) for Android permissions and Data Safety before store submission.

---

## Technical snapshot

| Item | Detail |
|------|--------|
| Framework | Flutter 3.7+ / Dart 3.7+ |
| Audio | just_audio, background playback, platform equalizer (Android) |
| Storage | Sqflite, SharedPreferences |
| Version | 1.0.0+1 (`pubspec.yaml`) |
| Repo | [AdeTejas/playa-music-player](https://github.com/AdeTejas/playa-music-player) |

---

## Honest scope notes

Being upfront builds trust in diligence:

- **iOS** is not a stated target today (Android + Windows are).  
- **Equalizer** is Android-native; Windows path differs.  
- **Neural Mix** is a on-device delight feature, not a cloud recommendation service.  
- Store listing assets and social preview image are still worth adding before a public launch push.  

---

## Acquisition / partnership angles

| Buyer type | Why Playa might fit |
|------------|-------------------|
| Audiobook or media app | Long-form UX and resume already built |
| OEM / device bundle | Branded offline player with distinctive UI |
| App portfolio | v1.0.0, dual platform, niche aesthetic + real features |
| White-label / OSS fork | Reusable painters, design system, Flutter architecture |

---

## Contact

Product questions: [paxpiece@gmail.com](mailto:paxpiece@gmail.com)