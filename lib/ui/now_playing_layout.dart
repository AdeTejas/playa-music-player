import 'dart:math' as math;

import 'waveform_widget.dart';

/// Single source of truth for Now Playing hero + dock proportions.
///
/// Scale chain:
/// 1. [waveformHeight] — fixed slot on the 8pt grid.
/// 2. [dockHeight] — sums fixed control rows + waveform slot.
/// 3. [turntableSide] — `min(width, height budget) * [turntableScale]` (scale applied once).
/// 4. Ship length inside the painter — `waveformHeight * modeShipFill` (see [waveformMode]).
class NowPlayingLayoutMetrics {
  const NowPlayingLayoutMetrics({
    required this.isLandscape,
    required this.isAudiobook,
    required this.hasWaveform,
  });

  final bool isLandscape;
  final bool isAudiobook;
  final bool hasWaveform;

  /// Applied exactly once when sizing the turntable square.
  static const double turntableScale = 0.85;

  /// Portrait turntable raw side cap (before [turntableScale]).
  static const double turntableMaxPortraitShare = 0.50;

  static const double waveformPortrait = 96;
  static const double waveformLandscape = 104;

  /// Max upscale for the control dock when hero leaves extra vertical room.
  static const double dockMaxUpscale = 1.32;
  static const double dockMinScale = 0.82;

  /// Ship fill inside the waveform slot (must match [PreciseWaveformPainter]).
  static const double shipFillStandard = 0.80;
  static const double shipFillCompact = 0.52;
  static const double shipFillCalm = 0.62;

  double get waveformHeight =>
      isLandscape ? waveformLandscape : waveformPortrait;

  WaveformDisplayMode get waveformMode {
    if (isAudiobook) return WaveformDisplayMode.calm;
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
      );

  /// Scales dock content up (or slightly down) to absorb leftover viewport.
  double dockScaleFor(double availableHeight) {
    final intrinsic = dockHeight;
    if (intrinsic <= 0 || availableHeight <= 0) return 1.0;
    return (availableHeight / intrinsic).clamp(dockMinScale, dockMaxUpscale);
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

    if (isLandscape) {
      return math.min(width, height) * turntableScale;
    }

    final heroBudget = math.max(0.0, height - dockHeight);
    final cap = (viewportHeight ?? height) * turntableMaxPortraitShare;
    return math.min(width, math.min(heroBudget, cap)) * turntableScale;
  }

  static double _dockReserve({
    required bool isAudiobook,
    required bool hasWaveform,
    required double waveformHeight,
    required bool isLandscape,
  }) {
    var h = 0.0;
    if (hasWaveform) {
      h += waveformHeight + 4; // waveform + tight gap
    }
    h += 16; // elapsed / duration
    h += 4 + 38; // section + metadata
    if (isAudiobook) {
      h += 4 + 22; // group + speed pills
    }
    h += 4 + 46; // section + transport
    if (isAudiobook) {
      h += 4 + 32; // group + bookmark / sleep
      h += 22; // collapsed music-tools header
    } else {
      h += 4 + (isLandscape ? 44 : 58); // group + secondary chips + reorder
    }
    return h + 4 + (isLandscape ? 4 : 0);
  }
}