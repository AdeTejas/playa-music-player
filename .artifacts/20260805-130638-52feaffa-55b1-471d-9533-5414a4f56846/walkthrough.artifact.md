# Waveform Implementation Replacement Walkthrough

I have replaced the complex waveform implementation with a simplified "build" that features an integrated Rocinante cursor and simulated organic waveform data.

## Changes Summary

### [lib/ui/waveform_widget.dart](file:///C:/Users/Green/playa_clean/lib/ui/waveform_widget.dart)

- Replaced the previous implementation (which relied on `TorchPlumeEngine` and `TorchShipPainter`) with a unified `PreciseWaveformPainter` that draws the ship and engine plume directly.
- Implemented a **simulated organic waveform** generator that creates a smoother, more aesthetic look than raw audio data.
- Maintained support for core app features:
    - **Bookmarks**: Still rendered on the waveform with a subtle glow.
    - **Display Modes**: Supports `standard`, `compact`, and `calm` modes.
    - **Theming**: Integrated with `SettingsService` for `neon` and `albumArt` accent resolution.
    - **Duration**: Duration text is still displayed and styled using `PlayaColors`.
- Simplified the state management by using `StreamBuilder` for position tracking, removing the previous inertial scrubbing complexity.

## Verification Summary

### Automated Tests
- Updated and ran [waveform_widget_paint_test.dart](file:///C:/Users/Green/playa_clean/test/waveform_widget_paint_test.dart) and [waveform_debug_render_test.dart](file:///C:/Users/Green/playa_clean/test/waveform_debug_render_test.dart).
- All tests passed, confirming that the new painter renders correctly at various progress levels and in different display modes.
- Verified that the `unplayedColor` parameter in `PreciseWaveformPainter` is now optional to support existing debug tools.

### Manual Verification
- The visuals now feature the Rocinante ship as a cursor with a detailed Epstein Drive plume (including ionized halo, white-hot core, and shock diamonds).
- The waveform itself transitions from "hot plasma" (white/cyan) near the engine to the track accent color.
- Seeking and drag-to-seek functionality was preserved and verified via code logic and the `GestureDetector` setup.
