# Playa Features Progress

## ✅ Completed Features

### 1. Playlist Management (SQLite)
- **Data Model**: `Playlist` class with JSON serialization.
- **Repository**: `PlaylistRepository` using `DatabaseService` for persistence.
- **UI**:
  - `PlaylistsScreen`: List user playlists and smart playlists.
  - `PlaylistDetailScreen`: View and manage playlist songs.
  - `LibraryPage`: "Add to Playlist" context menu action.
  - Create/Delete playlists.
  - Add/Remove songs from playlists.

### 2. Smart Playlists
- **Heavy Rotation**: Most played tracks (implemented with `SongRepository` play counts).
- **Recently Added**: Sort by date added.
- **Forgotten Favorites**: High play count but not played in 30 days (implemented).

### 3. Lyrics
- **Service**: `LyricsService` fetching from LRCLIB.net.
- **UI**: `LyricsSheet` with synchronized scrolling (if time-synced) or plain text.

### 4. Performance
- **Turntable**: Sleep mode when hidden to save battery/CPU.

### 5. Equalizer
- **Service**: Android `MethodChannel` implementation.
- **UI**: `EqualizerScreen` with vertical sliders and presets.

### 6. CEO/CTO Performance Iteration (Sonic DNA + Neural Mix)
- Made full-library BPM/Key analysis **cancellable** with graceful exit (preserves partial results via signature caching).
- Smarter yielding for large libraries (>800 tracks).
- Added **Cancel button** in the Analysis progress dialog (settings).
- Directly improves battery life, UI responsiveness, and Neural Mix readiness.
- Resumable by design.

### 7. Sonic DNA Analysis Service
- `SonicDnaAnalysisService` (`lib/services/sonic_dna_analysis_service.dart`): cancellable, resumable, signature-cached full-library BPM/Key analysis.
  - Pass 1: embedded tags (all platforms); Android-only deep native analyzer for tracks without tags.
  - Resume: completed tracks store `mtime:size` in `song_metadata.dna_sig` and are skipped on re-run.
  - Yields to the event loop every 20/50 tracks to keep the UI responsive.
  - Notifies `ChangeNotifier` listeners with phase/progress/stats; `cancel()` is generation-guarded.
- **Settings tile** ("Sonic DNA Analysis") opens a live progress sheet (`GlassPanel`): progress bar, done/total, cached-skipped, found-with-BPM/key, run duration, Cancel button.
- Tests: `test/sonic_dna_analysis_test.dart` (tag persist + resume-skip + missing-file skip + empty no-op + cancel) — 5 tests.

### 8. Smart Analysis Scheduling (charging + idle)
- `SonicDnaScheduler` (`lib/services/sonic_dna_scheduler.dart`) auto-runs the full-library DNA analysis only while:
  - Onboarding complete, not currently scanning, library populated, no analysis running.
  - Device charging (`BatteryState.charging`/`full`) via `battery_plus`.
- Auto-runs are **cancelled gracefully** the moment the device is unplugged (resume via signature cache).
- 6h cooldown between auto-runs; wired into `main.dart` (non-blocking, `unawaited`).
- Tests: `test/sonic_dna_scheduler_test.dart` (not charging / runs when charging / onboarding gate / empty library / unplug-cancels) — 5 tests.

### 9. Waveforms — Accuracy, Efficiency, Realism
- **Accuracy (mobile)**: native RMS extraction is real; the 24MB cap was lifted to 120MB (covers all music incl. FLAC; huge audiobooks stay procedural) and the extract timeout raised to 8s.
- **Efficiency**: `WaveformWidget` ticker is now **parked when the Player tab is hidden** in the `IndexedStack` (`isVisible`, mirrors `TurntableDeck`) — no more 60fps repaints while on Library/Playlists tabs. Also parks repaints when the scene is fully static (paused, spring settled, no seek pulse).
- **Realism**: the procedural fallback is now music-shaped — intro ramp, alternating verse/chorus energy sections, percussive kicks, breathing gaps, outro fade — deterministic per track. Standard mode adds a faint **full-track ghost waveform** so the unplayed shape reads ahead of the ship.
- Tests: `test/waveform_envelope_test.dart` (determinism, per-path variation, bounds, intro/outro structure) — 6 tests.

### 10. Rocinante Ship (The Expanse-inspired)
- **`TorchShipPainter` rebuilt as a side-profile Rocinante** (Morrigan-class): long angular dagger hull (sharp bow, straight dorsal deck line, squared stern), raised **dorsal spine**, flat armor-panel plating (heat-shield tiles removed), gunmetal dorsal-lit gradient, red-orange `accentWarm` hull stripe + bow chevron, cool-accent window glows, hull-number block.
- **Twin Epstein drive cowl** at the stern replaces the single Raptor bell; engine heatbloom/glow now blue-white (`raptorCore`/`raptorSheath`).
- **`TorchPlumeEngine.rocinanteCluster`**: twin equal engines (`±0.48·bellHalfW`, `scale 0.55`); `paintEngineThroat`, `paintHorizontalPlume`, `paintHorizontalPlumeDiamonds`, `paintVerticalCorePlume` accept an optional `cluster` (default `raptorCluster`, backward compatible). Waveform + screensaver pass `rocinanteCluster` so the exhaust ribbon aligns with the twin bells.
- RCS pods re-laid-out for the side profile (bow/mid/stern dorsal+ventral, axial pitch/sustain jets) using the same `PlaybackMotion` physics.
- External painter API unchanged → `waveform_widget.dart` and `screensaver_torch_cruiser.dart` keep working.
- Tests: `test/torch_plume_engine_test.dart` adds `rocinanteCluster` twin-engine test.

### 11. Neural Mix Auto-Warm (after DNA scan)
- **`NeuralMixIndexService`** (`lib/services/neural_mix_index_service.dart`): pre-builds and caches the parsed BPM/key/artist rows that `smartShuffle` ranks against.
  - Listens to `SonicDnaAnalysisService` — when a scan completes (manual or scheduled) it rebuilds the index, so the first mix after a scan is instant (no `getAllMetadata()` + key parsing at mix time).
  - Invalidates the cache when the library changes (`LibraryScanService` done), and exposes `invalidate()` for explicit drops.
  - Keys are pre-parsed via `parseNeuralMixKey` (`lib/utils/neural_mix_key.dart`) — a shared parser used by both the warm index and the rank isolate, so keys are only parsed once per library.
- **`smartShuffle` / `_generateNeuralMixSources`** (`player_controller.dart`) now consume the warmed index via `_neuralMixSongRows()`; a cold build still works on demand and kicks off a background warm for next time. Row shape extended with `keyPitch`/`keyMinor`; rank function falls back to parsing when absent (backward compatible).
- Wired in `main.dart` alongside the scheduler.
- Tests: `test/neural_mix_index_service_test.dart` (key parser, warm with/without metadata, empty no-op, invalidate, analysis-done triggers warm) — 6 tests.

### 12. Rocinante Replica (Corvette-class, faithful silhouette)
- **`TorchShipPainter` rebuilt as a faithful Rocinante**: pointed drooping bow, layered parallel flanks with deck seams, flat belly, drive-cone stern (`0.24·L` hull). Raised **forward command deck** with sloped windshield + cool window glow, **swept-back dorsal fin + keel fin**, and a layered deck-spine ridge. Markings (stripe, small bow chevron, windows, hull number), RCS pod layout, plating seams, and nav lights re-laid-out for the new silhouette.
- **Single Epstein drive cone**: the Roci's real propulsion is one main drive, not a cluster — `TorchPlumeEngine.rociDriveCluster` (`0, 1.0`) replaces the cluster. The drive block hugs the bell (`1.22·bellHalfW`) with a **flared bell mouth** (narrow throat forward), reactor-deck seam bands, and the throat glow + heatbloom scaled to the single big bell.
- Waveform + screensaver pass `rociDriveCluster` so the exhaust ribbon, Mach diamonds, and engine throat align to the single cone (`epsteinCluster` / `rocinanteCluster` retained as alternative layouts).
- Tests: `test/torch_plume_engine_test.dart` adds `rociDriveCluster` single-bell test. Full suite green (107/107), `flutter analyze` clean.
- **Drive-cone ↔ exhaust alignment (Roci pass 2, first cut)**: `engineFaceOffset` corrected `0.45·L` → `0.50·L` to match the Roci bell mouth (`cowlBottom − 0.01·L`), so the ribbon throat, plume origin, and throat glow all emerge exactly at the flared bell mouth instead of inside the drive housing (~0.06·L forward). Screensaver now uses the shared `engineMetrics().engineFaceOffset` instead of a hardcoded `0.45`. Verified via pixel measurement at standard / compact / calm scales. Remaining pass-2 tuning (bow droop, command-deck height, dorsal-fin sweep) needs on-device eyeballing.
- **Exhaust-blend regression tests**: `waveformTinted` plume smoke test (paints without error), accent-coherence assertion (tinted plume body keeps the accent hue vs the cool untinted sheath), and a warm-accent `PreciseWaveformPainter` render test. Suite 110/110, `flutter analyze` clean.
- **Exhaust ↔ waveform blend** (`paintHorizontalPlume` + `waveform_widget.dart`): the plume now uses the **same exhaust palette as the waveform ribbon** (`waveformTinted` — white-hot at the nozzle, accent aft) and is drawn **over the ribbon** instead of as a separate cool glow behind it, so the torch reads as one continuous stream. Tinted plume draws ~45% stronger to wrap the ribbon (boosted `effectiveAmp`), the ribbon's white→accent head was tightened (`exhaustWaveformGradientStops` → `[0, 0.08, 0.26, 1.0]`), and the tinted plume is **bigger** — wider halo (×1.35), thicker core (×1.40), and ~18% longer. Non-waveform callers (ship painter, screensaver) unchanged. Tests 107/107, `flutter analyze` clean.
- **Real WAV envelopes on desktop/web (pure Dart)**: `WaveformEnvelopeService` now parses RIFF/WAVE directly — no plugins, works on Dart 3.7 — giving **real RMS envelopes for uncompressed WAV** (PCM 8/16/24/32-bit + IEEE float, mono/stereo) on all platforms via the desktop/web branch of `loadEnvelope`, streamed with a 120MB cap; non-WAV (MP3/FLAC/etc.) still falls back to the procedural envelope until the Dart ≥3.10.8 upgrade lands. Tests: `test/waveform_wav_envelope_test.dart` (16-bit PCM loud-then-silent, float32, stereo 24-bit, non-WAV fallback) — 4 tests. Suite 114/114, `flutter analyze` clean.
- **Mobile native-extract fix (on-device debug)**: device logs showed long audiobook chapters always landed on the **procedural** envelope — either killed by the fixed 8s decode timeout (e.g. a 104-min MP3) or blocked by the 120MB cap (e.g. a 540MB chapter), so the calm scrubber never reflected the actual speech. `maxNativeExtractBytes` raised to **400MB**, and the timeout now **scales with file size** (`WaveformEnvelopeService.extractTimeoutFor`, 8s floor → 90s ceiling; ~15s for a 125MB chapter, ~28s for 400MB). Result is disk-cached per file, so it's a one-time on-device decode. Tests added for cap + timeout scaling — suite 133/133, `flutter analyze` clean.
- **Waveform functional audit + 2 critical fixes**: (1) the widget wrapped `loadEnvelope` in a **10s `.timeout`** that killed the size-scaled extraction and then discarded the finished result — large books could never escape the preview shape; replaced with a 120s pure-safety `WaveformWidget.loadSafetyTimeout` (regression test asserts it never undercuts the service's 90s max). (2) **track-switch race**: `_isExtracting` is a single flag and `_loadWaveform` read `widget.path` at completion time, so a stale envelope could be painted onto a newly selected track; now captures `requestedPath` at start and drops + reloads on mismatch. Suite 134/134, `flutter analyze` clean. Known limitation: `content://` (SAF/MediaStore) paths stay procedural by design.
- **Custom fast Android extractor (fast channel)**: `audio_waveforms`'s native extractor is ~14x realtime (plugin docs: 58-min/18MB ≈ 4 min) so real envelopes for 1–3h audiobook chapters are structurally impossible through it. Shipped a purpose-built `FastWaveformExtractor` (Kotlin, background thread, MediaExtractor+MediaCodec, byte-array accumulate for 8/16/32-bit PCM) registered on `com.paxpiece.playa/fast_waveform`; Dart routes both filesystem **and** `content://` paths to it on Android (iOS keeps the plugin's file-path-only path). Budget model: Dart sends a flat 900s `fastExtractCap` as a pure safety net; Kotlin self-budgets from the container's `durationUs` (`duration/8 + 45s`, clamped 60s–maxMillis) with a deadline-driven decode loop and single-flight cancellation (`cancelCurrent`), returning `null` on timeout/cancel → Dart falls back procedural. `WaveformWidget.loadSafetyTimeout` raised 120s→900s to match. Tests updated (cap ≥ duration-budgeted decode, widget timeout ≥ cap); targeted suite green.
- **Visual merge (legacy waveform build)**: reconciled the current TorchPlumeEngine painter against the older hand-rolled `PreciseWaveformPainter` (git `402a407`). Every legacy element — amplitude-gradient ribbon, plasma glow, throat pinch, Mach diamonds, nozzle flare, Roci ship — is already covered and evolved; the one missing layer was the white **heat-haze turbulence** shimmer over the played ribbon. Added `TorchPlumeEngine.paintWaveformTurbulence` (`TileMode.repeated` white gradient, `BlendMode.overlay`), wired into `PreciseWaveformPainter` between glow and stroke, gated by the previously-dead `TorchEffectBudget.drawTurbulence` flag (music = on, audiobook/calm = off). Tests: music tier enables / audiobook disables / paints without error. Suite 138/138, `flutter analyze` clean.

### 13. Audio Effects — Android native (Virtualizer + BassBoost + PresetReverb)
- **No-licensing path from `DOLBY_ATMOS_INTEGRATION_PLAN.md`** ("minimal effort alternative"): extends the existing equalizer MethodChannel in `MainActivity.kt` with `android.media.audiofx.Virtualizer` (headphone spatialization), `BassBoost`, and `PresetReverb` (room simulation). All three init alongside the equalizer on the same audio session, default **disabled**; wrapped in per-effect try/catch so unsupported devices degrade to no-ops. Strength reads use `getRoundedStrength()` (Virtualizer has no `getStrength()`); reverb presets are index-aligned with the Android `PRESET_*` constants (None…Plate).
- **`EqualizerService`** (`lib/services/equalizer_service.dart`): 15 new Android-guarded methods with graceful MissingPlugin/PlatformException fallbacks (same style as the equalizer API).
- **UI** (`equalizer_screen.dart`): new collapsible **Audio Effects** card under the EQ sliders — headphone-spatialization toggle + strength slider (0–1000), bass-boost toggle + strength slider, and room-reverb toggle + preset chips. Effects are hidden/disabled where the device reports no support.
- Verified: `flutter analyze` clean, suite 115/115, and `:app:compileDebugKotlin` compiles (Kotlin caught a real API mismatch — `Virtualizer.getStrength()` does not exist). Tests: `test/equalizer_service_test.dart` (non-Android no-op fallbacks) — 4 tests.
- **Roci pass-2 tuning knobs**: `TorchShipPainter` now exposes `bowDroop`, `commandDeckHeight`, `dorsalFinSweep` (defaults = current look, backward compatible) + a scratch render harness (`test/roci_tuning_render_test.dart`) that writes a 9-frame PNG matrix to the temp dir for eyeballing — awaiting the CTO's picks.
- **Effect persistence**: effect state now survives restarts/session changes. `SettingsService` gained `virtualizerEnabled/Strength`, `bassBoostEnabled/Strength`, `presetReverbEnabled/Preset` (+ setters, load, reset); `EqualizerService.restoreEffectsFromSettings()` re-applies them after every fresh native session (wired in `player_controller.dart` on init + session change), and the `EqualizerScreen` handlers persist every change. Tests: settings persistence + restore no-op — suite 121/121, `flutter analyze` clean.
- **README hero screenshot**: `test/hero_screenshot_render_test.dart` composes deep space + turntable + torch-drive ship scrubber via the real painters and writes `assets/screenshots/now_playing_hero.png` (1600×900, also copied to the temp dir for eyeballing); referenced from `README.md` `## Screenshots`.

### 14. Deep-space static HDR realism grade
- **Scope**: static grade only (no playing/paused auto-exposure, no beat-sync, no progress parallax, no screensaver wiring). The whole grade is gated by the existing `hdrBoost` + the new **`hdrIntensity`** knob (0–1.5, default 1.0; Now Playing 1.0, Library 0.75 in `main.dart`).
- **What changed in `lib/ui/deep_space_background.dart`**:
  - `_QualityBudget` carries `hdrIntensity` (clamped); `DeepSpaceBackground` accepts `hdrIntensity` + optional **`seed`** for deterministic layouts, with re-init on change.
  - **Two-scale star bloom**: the far-layer cache gets a baked soft halo pass; per-frame stars bloom from a lower threshold (0.66 vs 0.78), and bright stars get a tight core + wide halo.
  - **`_drawSoftSpikes` fixed** to a symmetric 4-ray diffraction cross (was only right+down) plus faint 45° diagonal rays under HDR.
  - **Nebula hot cores**: tight white point over each bright center + a local-contrast annulus punch.
  - **Filmic grade**: the HDR pass now adds a corner black-shoulder (multiply) and bakes a **banding dither** into the nebula cache so smooth gradients don't posterize on 8-bit panels.
- **Tests**: `test/deep_space_hdr_test.dart` asserts HDR-on has measurably more bright pixels and darker corners than HDR-off (same seed); frame budget unchanged. Suite 122/122, `flutter analyze` clean.
- **Eyeball**: harness now also writes real-widget renders to `temp\opencode\deep_space_hdr_off.png` / `deep_space_hdr_on.png`.

### 15. Privacy-first telemetry (crash reporting + retention analytics)
- **Consent-gated by design**: `TelemetryService` (`lib/services/telemetry_service.dart`) is a single facade over **Sentry** (crash/error) + **PostHog** (product/retention). Nothing initializes and nothing leaves the device until the user explicitly opts in on the onboarding **Privacy page** or the **Settings → Privacy & Analytics** toggle. Off by default.
- **Identity**: a stable, anonymous **per-install UUID** (never a device identifier) is minted once and shared as PostHog `install_id` super-property + Sentry tag/user for cross-tool correlation. No accounts, no emails.
- **Privacy posture**: PostHog runs with session replay/surveys/feature flags/push tracking/error tracking **disabled**, `personProfiles = never`, a `beforeSend` sanitizer that strips content-metadata keys and absolute file paths (unit-tested), and `sendDefaultPii = false` on Sentry with performance tracing off (`tracesSampleRate = 0`).
- **SDK keys are build-time only** via `--dart-define` (`PLAYA_SENTRY_DSN`, `PLAYA_POSTHOG_KEY`, `PLAYA_POSTHOG_HOST`) — never committed. Telemetry is also suppressed in debug builds unless `PLAYA_TELEMETRY_DEBUG=true`.
- **Key wiring**: `scripts\run_with_telemetry.ps1` forwards keys from the gitignored `.env.local` (blank template at repo root) into `flutter run`/`build`/`drive` via `--dart-define-from-file`. Fill in `PLAYA_SENTRY_DSN` / `PLAYA_POSTHOG_KEY` / `PLAYA_POSTHOG_HOST`, then e.g. `scripts\run_with_telemetry.ps1 -Mode release -Device <id>`. Blank keys stay inert.
- **Event surface** (retention-ready): `app_open` + `app_foreground`/`app_background` (with `session_seconds`) via `TelemetryLifecycleObserver`, native `$app_installed`/`$app_updated` lifecycle events, and a coarse privacy-safe `track_play_started` (content_type + duration only — no titles/artists/paths) from `player_controller`. Existing on-device local error logging (`AnalyticsService`) now also mirrors to Sentry behind consent.
- **Tests**: `test/telemetry_service_test.dart` (consent gate inertness, sanitizer strips sensitive keys/paths, install-id stability) + onboarding consent-flow coverage — suite 151/151, `flutter analyze` clean, Windows + Android debug builds green.

## 🎯 Next Steps
1. **Real desktop waveform extraction** (Windows/Linux): WAV now works in pure Dart; MP3/FLAC/etc. still blocked on Dart 3.7 — `audio_decoder` needs Dart ≥3.10.8. Path: Flutter upgrade to 3.44+ then `audio_decoder` (OS-native, no ffmpeg bundle), or a native Media Foundation extractor.
2. **Testing**: Verify on real device + large libraries.
3. **Roci pass 2**: after on-device review — tune bow droop, command-deck height, dorsal-fin sweep (knobs + render matrix ready; awaiting picks), and drive-cone ↔ exhaust ribbon alignment at compact/calm scales.
4. **Audio effects**: on-device A/B on a real handset (headphone spatialization + bass boost + reverb) — persistence is in; eyeball the new hero screenshot. (Rendered at `assets\screenshots\now_playing_hero.png` and the temp opencode dir.)
5. **HDR grade**: eyeball `temp\opencode\deep_space_hdr_off.png` vs `deep_space_hdr_on.png`; tune `hdrIntensity` targets (1.0 Now Playing / 0.75 Library) if the bloom or corner shadow reads too hot or too dark.
6. **Telemetry live**: create the Sentry project + PostHog project, fill the keys into the gitignored `.env.local` (see #15), and install on a real device via `scripts\run_with_telemetry.ps1`. Then start reading retention cohorts + crash-free sessions and decide: add a soft re-prompt for consent-decliners, or ship as-is.

## 📝 Notes
- `PlaylistRepository` uses `uuid` for unique IDs.
- `LibraryPage` now fully integrates with the playlist system.
