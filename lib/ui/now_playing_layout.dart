import 'dart:math' as math;

import 'waveform_widget.dart';

/// Single source of truth for Now Playing hero + dock proportions.
///
/// Scale chain:
/// 1. [waveformHeight] - fixed slot on the 8pt grid (shrinks on short desktop).
/// 2. [dockHeight] - sums fixed control rows + waveform slot.
/// 3. [turntableSide] - min(width, height budget) * [turntableScale] (once).
/// 4. Ship length inside the painter - waveformHeight * modeShipFill.
///
/// Short viewports (~1280x720 Windows desktop) opt into a compact budget so
/// Library/Player chrome, filters, and the scrubber stop clipping. Phone-sized
/// portrait layouts keep the original proportions even when height < 780.
class NowPlayingLayoutMetrics {
  const NowPlayingLayoutMetrics({
    required this.isLandscape,
    required this.isAudiobook,
    required this.hasWaveform,
    this.viewportHeight,
    this.viewportWidth,
    this.musicToolsCollapsed = true,
  });

  final bool isLandscape;
  final bool isAudiobook;
  final bool hasWaveform;
  final double? viewportHeight;
  final double? viewportWidth;

  /// When true (music mode default after polish #9), dock only reserves a
  /// collapsed "Tools" header instead of a full secondary-chip wrap.
  final bool musicToolsCollapsed;

  /// Applied exactly once when sizing the turntable square.
  static const double turntableScale = 0.85;

  /// Portrait turntable raw side cap (before [turntableScale]).
  static const double turntableMaxPortraitShare = 0.50;

  /// Short-viewport cap used on ~720p desktop windows.
  static const double turntableMaxShortPortraitShare = 0.38;

  static const double waveformPortrait = 96;
  static const double waveformLandscape = 104;
  static const double waveformPortraitCompact = 80;
  static const double waveformLandscapeCompact = 72;

  /// Max upscale for the control dock when hero leaves extra vertical room.
  static const double dockMaxUpscale = 1.32;
  static const double dockMinScale = 0.82;

  /// Below this height we *may* treat the viewport as short desktop.
  static const double shortViewportHeight = 780;

  /// Wide enough to prefer a side rail over a bottom nav (desktop).
  static const double wideDesktopWidth = 1100;

  /// Min width to treat a short window as desktop (not phone portrait).
  static const double shortDesktopMinWidth = 900;

  /// Ship fill inside the waveform slot (must match [PreciseWaveformPainter]).
  static const double shipFillStandard = 0.7125;
  static const double shipFillCompact = 0.45;
  static const double shipFillCalm = 0.7125;

  /// Short *desktop* window (e.g. 1280x720). Phone portrait is often under
  /// [shortViewportHeight] too - do not steal its proportions.
  bool get isShortViewport {
    final h = viewportHeight;
    if (h == null || h >= shortViewportHeight) return false;
    final w = viewportWidth;
    if (w == null) return false;
    return w >= shortDesktopMinWidth;
  }

  bool get isWideDesktop {
    final w = viewportWidth;
    return w != null && w >= wideDesktopWidth;
  }

  /// Prefer scrolling the dock over crushing controls on short desktop.
  bool get preferScrollableDock => isShortViewport || isWideDesktop;

  double get waveformHeight {
    if (isShortViewport) {
      return isLandscape ? waveformLandscapeCompact : waveformPortraitCompact;
    }
    return isLandscape ? waveformLandscape : waveformPortrait;
  }

  WaveformDisplayMode get waveformMode {
    if (isAudiobook) return WaveformDisplayMode.calm;
    if (isShortViewport && isLandscape) return WaveformDisplayMode.compact;
    return WaveformDisplayMode.standard;
  }

  double get shipFill => switch (waveformMode) {
    WaveformDisplayMode.standard => shipFillStandard,
    WaveformDisplayMode.compact => shipFillCompact,
    WaveformDisplayMode.calm => shipFillCalm,
  };

  /// Expected ship length in logical pixels (for layout sanity checks).
  double get expectedShipLength => waveformHeight * shipFill;

  double get dockHeight => _dockReserve(
    isAudiobook: isAudiobook,
    hasWaveform: hasWaveform,
    waveformHeight: waveformHeight,
    isLandscape: isLandscape,
    musicToolsCollapsed: musicToolsCollapsed,
    compact: isShortViewport,
  );

  /// Scales dock content up (or slightly down) to absorb leftover viewport.
  double dockScaleFor(double availableHeight) {
    final intrinsic = dockHeight;
    if (intrinsic <= 0 || availableHeight <= 0) return 1.0;
    return (availableHeight / intrinsic).clamp(dockMinScale, dockMaxUpscale);
  }

  /// True when FittedBox scaling would crush controls - prefer scroll instead.
  bool shouldScrollDock(double availableHeight) {
    if (preferScrollableDock && availableHeight + 0.5 < dockHeight) {
      return true;
    }
    return dockScaleFor(availableHeight) <= dockMinScale + 0.001 &&
        availableHeight + 0.5 < dockHeight;
  }

  /// Square turntable side from panel bounds. [viewportHeight] is required in
  /// portrait to apply the hero height cap.
  double turntableSide({
    required double maxWidth,
    required double maxHeight,
    double? viewportHeight,
  }) {
    final width = math.max(0.0, maxWidth);
    final height = math.max(0.0, maxHeight);
    final vh = viewportHeight ?? this.viewportHeight ?? height;

    if (isLandscape) {
      final scale = isShortViewport ? turntableScale * 0.92 : turntableScale;
      return math.min(width, height) * scale;
    }

    final heroBudget = math.max(0.0, height - dockHeight);
    final share =
        isShortViewport
            ? turntableMaxShortPortraitShare
            : turntableMaxPortraitShare;
    final cap = vh * share;
    return math.min(width, math.min(heroBudget, cap)) * turntableScale;
  }

  static double _dockReserve({
    required bool isAudiobook,
    required bool hasWaveform,
    required double waveformHeight,
    required bool isLandscape,
    required bool musicToolsCollapsed,
    required bool compact,
  }) {
    var h = 0.0;
    if (hasWaveform) {
      h += waveformHeight + (compact ? 2 : 4);
    }
    h += compact ? 14 : 16; // elapsed / duration
    h += 4 + (compact ? 32 : 38); // section + metadata
    if (isAudiobook) {
      h += 4 + 22; // group + speed pills
    }
    h += 4 + (compact ? 42 : 46); // section + transport
    if (isAudiobook) {
      h += 4 + 32; // group + bookmark / sleep
      h += 22; // collapsed music-tools header
    } else if (musicToolsCollapsed) {
      // Primary shuffle/repeat row + collapsed Tools affordance.
      h += 4 + (isLandscape ? 36 : 40);
      h += 22;
    } else {
      h += 4 + (isLandscape ? 44 : 58); // group + secondary chips + reorder
    }
    return h + 4 + (isLandscape ? 4 : 0);
  }
}
