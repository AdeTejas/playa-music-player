import 'package:flutter/material.dart';
import '../tokens/colors.dart';

/// ThemeExtension that gives easy access to Playa semantic colors.
///
/// Usage:
///   final colors = Theme.of(context).extension<PlayaColorsExtension>()!;
///   colors.glass
///   colors.accent
class PlayaColorsExtension extends ThemeExtension<PlayaColorsExtension> {
  final Color accent;
  final Color glass;
  final Color glassStrong;
  final Color glassSubtle;
  final Color borderSubtle;
  final Color onSurface;
  final Color onSurfaceVariant;

  const PlayaColorsExtension({
    this.accent = PlayaColors.accent,
    this.glass = PlayaColors.glass,
    this.glassStrong = PlayaColors.glassStrong,
    this.glassSubtle = PlayaColors.glassSubtle,
    this.borderSubtle = PlayaColors.borderSubtle,
    this.onSurface = PlayaColors.onSurface,
    this.onSurfaceVariant = PlayaColors.onSurfaceVariant,
  });

  @override
  PlayaColorsExtension copyWith({
    Color? accent,
    Color? glass,
    Color? glassStrong,
    Color? glassSubtle,
    Color? borderSubtle,
    Color? onSurface,
    Color? onSurfaceVariant,
  }) {
    return PlayaColorsExtension(
      accent: accent ?? this.accent,
      glass: glass ?? this.glass,
      glassStrong: glassStrong ?? this.glassStrong,
      glassSubtle: glassSubtle ?? this.glassSubtle,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      onSurface: onSurface ?? this.onSurface,
      onSurfaceVariant: onSurfaceVariant ?? this.onSurfaceVariant,
    );
  }

  @override
  PlayaColorsExtension lerp(ThemeExtension<PlayaColorsExtension>? other, double t) {
    if (other is! PlayaColorsExtension) return this;

    return PlayaColorsExtension(
      accent: Color.lerp(accent, other.accent, t)!,
      glass: Color.lerp(glass, other.glass, t)!,
      glassStrong: Color.lerp(glassStrong, other.glassStrong, t)!,
      glassSubtle: Color.lerp(glassSubtle, other.glassSubtle, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      onSurface: Color.lerp(onSurface, other.onSurface, t)!,
      onSurfaceVariant: Color.lerp(onSurfaceVariant, other.onSurfaceVariant, t)!,
    );
  }
}
