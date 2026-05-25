import 'package:flutter/material.dart';
import '../tokens/colors.dart';

class PlayaColorsExtension extends ThemeExtension<PlayaColorsExtension> {
  final Color accent;
  final Color bg;
  final Color surface;
  final Color surfaceVariant;
  final Color card;
  final Color onBg;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color glass;
  final Color glassLight;
  final Color glassStrong;
  final Color glassSubtle;
  final Color border;
  final Color borderSubtle;
  final Color borderStrong;
  final Color success;
  final Color warning;
  final Color error;
  final Color info;
  final Color overlay;
  final Color scrim;

  const PlayaColorsExtension({
    this.accent = PlayaColors.accent,
    this.bg = PlayaColors.bg,
    this.surface = PlayaColors.surface,
    this.surfaceVariant = PlayaColors.surfaceVariant,
    this.card = PlayaColors.card,
    this.onBg = PlayaColors.onBg,
    this.onSurface = PlayaColors.onSurface,
    this.onSurfaceVariant = PlayaColors.onSurfaceVariant,
    this.glass = PlayaColors.glass,
    this.glassLight = PlayaColors.glassLight,
    this.glassStrong = PlayaColors.glassStrong,
    this.glassSubtle = PlayaColors.glassSubtle,
    this.border = PlayaColors.border,
    this.borderSubtle = PlayaColors.borderSubtle,
    this.borderStrong = PlayaColors.borderStrong,
    this.success = PlayaColors.success,
    this.warning = PlayaColors.warning,
    this.error = PlayaColors.error,
    this.info = PlayaColors.info,
    this.overlay = PlayaColors.overlay,
    this.scrim = PlayaColors.scrim,
  });

  @override
  PlayaColorsExtension copyWith({
    Color? accent,
    Color? bg,
    Color? surface,
    Color? surfaceVariant,
    Color? card,
    Color? onBg,
    Color? onSurface,
    Color? onSurfaceVariant,
    Color? glass,
    Color? glassLight,
    Color? glassStrong,
    Color? glassSubtle,
    Color? border,
    Color? borderSubtle,
    Color? borderStrong,
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
    Color? overlay,
    Color? scrim,
  }) {
    return PlayaColorsExtension(
      accent: accent ?? this.accent,
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      card: card ?? this.card,
      onBg: onBg ?? this.onBg,
      onSurface: onSurface ?? this.onSurface,
      onSurfaceVariant: onSurfaceVariant ?? this.onSurfaceVariant,
      glass: glass ?? this.glass,
      glassLight: glassLight ?? this.glassLight,
      glassStrong: glassStrong ?? this.glassStrong,
      glassSubtle: glassSubtle ?? this.glassSubtle,
      border: border ?? this.border,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderStrong: borderStrong ?? this.borderStrong,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      info: info ?? this.info,
      overlay: overlay ?? this.overlay,
      scrim: scrim ?? this.scrim,
    );
  }

  @override
  PlayaColorsExtension lerp(ThemeExtension<PlayaColorsExtension>? other, double t) {
    if (other is! PlayaColorsExtension) return this;

    return PlayaColorsExtension(
      accent: Color.lerp(accent, other.accent, t)!,
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      card: Color.lerp(card, other.card, t)!,
      onBg: Color.lerp(onBg, other.onBg, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      onSurfaceVariant: Color.lerp(onSurfaceVariant, other.onSurfaceVariant, t)!,
      glass: Color.lerp(glass, other.glass, t)!,
      glassLight: Color.lerp(glassLight, other.glassLight, t)!,
      glassStrong: Color.lerp(glassStrong, other.glassStrong, t)!,
      glassSubtle: Color.lerp(glassSubtle, other.glassSubtle, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      info: Color.lerp(info, other.info, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
    );
  }
}
