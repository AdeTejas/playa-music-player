Dolby Atmos / Advanced Audio Processing - Integration Plan

Overview

This document summarizes options, constraints, and recommended next steps to add advanced audio processing (Dolby Atmos-like spatialization, advanced virtualization, or end-to-end Atmos encoding) to the Playa app.

Goals (choose one or more):
- Headphone spatialization / virtualization ("Atmos for headphones").
- Multi-channel Atmos rendering / encoding (authoring or transcoding to Atmos containers).
- Runtime DSP: enhanced EQ, virtualization, reverb, bass management, dynamic range control.

Constraints

- Dolby Atmos is a licensed technology. True Dolby Atmos encoding and some Dolby-rendering SDKs are proprietary and require licensing from Dolby.
- Device support varies widely: many phones provide vendor spatializers (Samsung, Sony, etc.) accessible via system settings rather than app-level APIs.
- Real-time advanced processing (spatialization, HQ virtualization) is CPU and latency-sensitive; native C/C++ SDKs are usually required for performant results.

Options

1) Use Android built-in AudioEffects (free, limited)
- Pros: No licensing, simple native APIs (`Equalizer`, `Virtualizer`, `BassBoost`, `PresetReverb`).
- Cons: Not Atmos; vendor behavior varies and effects are limited.
- Implementation: Native plugin (we already started) that attaches `Equalizer`, `Virtualizer`, `BassBoost` to the audio session.

2) Third-party native SDK (commercial, high-quality)
- Examples: Superpowered, Dirac, SRS/TwinVQ (vendor), Fraunhofer.
- Pros: High-quality audio processing, low-latency native runtimes, some provide spatialization.
- Cons: Licensing fees, native integration (C/C++), cross-platform differences.
- Implementation effort: ~2–6 weeks prototype (native plugin + Flutter binding), additional time for license and tuning.

3) Dolby solutions (proprietary, licensing required)
- Dolby provides SDKs and cloud services (Dolby.io). On-device Dolby Atmos rendering/authoring is typically commercial and varies by product.
- Two common approaches:
  - Dolby.io cloud / processing APIs — send audio files for processing (encoding/virtualization) and download processed assets.
  - Dolby mobile SDKs (if available) for headphone virtualization or decoding; may require OEM partnerships.
- Pros: Brand-name quality and compatibility with Atmos ecosystems.
- Cons: Licensing, possible pay-per-use cloud cost, integration complexity.

4) Hybrid approach
- Use Android built-in effects as a fallback and integrate a third-party/native SDK for premium devices or paid users.
- Enables progressive enhancement and reduces licensing exposure for basic features.

Recommended approach (practical path)

Phase 0 — Define features and success criteria (1–2 days)
- Decide what "Atmos" means for your app (headphone virtualization vs. full Atmos authoring).
- Define target platforms/devices and prioritized features (e.g., headphone virtualization for premium users).

Phase 1 — Prototype with native library + Flutter plugin (2–3 weeks)
- Pick a native SDK: Superpowered is a good starting point (commercial but developer-friendly, supports spatialization, low-latency mobile audio). Evaluate others if necessary.
- Build a small native plugin that:
  - Accepts PCM frames (or processes at the audio output) and applies the selected effect.
  - Attaches to `just_audio`'s audio session on Android.
- Validate CPU/latency, battery, perceived audio quality.

Phase 2 — Add UI + presets + device fallbacks (1–2 weeks)
- Create UI to enable/disable advanced processing and choose presets.
- Add auto-fallback to system AudioEffects if premium SDK not available.

Phase 3 — Licensing & production (time varies)
- Negotiate licensing with chosen SDK vendor (Superpowered, Dolby, etc.).
- Implement distribution & binary handling for native library licensing terms.

Minimal effort alternative (no licensing)
- Use Android `Virtualizer` + `Equalizer` + `PresetReverb` to offer improved headphone virtualization and tone shaping. This is already feasible with the plugin scaffold we have.

Risks & Mitigations
- Licensing delays: start vendor conversations early and prototype with evaluation SDKs.
- Performance: measure CPU on target devices; provide settings to reduce processing quality if necessary.
- Inconsistent behavior across devices: provide per-device diagnostics and fallback path.

Deliverables I can produce next
- A short comparison matrix (Superpowered vs. Dolby.io vs. others) with rough cost/effort estimates.
- A prototype plan and proof-of-concept plugin skeleton (native + Flutter binding) that processes audio in real time.
- Implementation tasks & estimated timeline for the option you pick.

Select next step: "Compare SDKs", "Prototype with Superpowered", "Use native AudioEffects fallback", or "Produce full licensing plan".
