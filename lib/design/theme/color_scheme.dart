import 'package:flutter/material.dart';
import '../tokens/colors.dart';

ColorScheme playaColorScheme(Color primary) {
  // Matte premium: desaturated companions derived from the accent hue.
  final primaryHsl = HSLColor.fromColor(primary);

  final secondaryHue = (primaryHsl.hue + 28) % 360;
  final secondary = HSLColor.fromAHSL(
    1.0, secondaryHue, primaryHsl.saturation * 0.38, primaryHsl.lightness * 0.78,
  ).toColor();

  final tertiaryHue = (primaryHsl.hue + 58) % 360;
  final tertiary = HSLColor.fromAHSL(
    1.0, tertiaryHue, primaryHsl.saturation * 0.28, primaryHsl.lightness * 0.68,
  ).toColor();

  final surfaceTint = primary.withValues(alpha: 0.04);

  return ColorScheme.dark(
    primary: primary,
    onPrimary: PlayaColors.bg,
    primaryContainer: primary.withValues(alpha: 0.2),
    onPrimaryContainer: primary,
    secondary: secondary,
    onSecondary: PlayaColors.bg,
    secondaryContainer: secondary.withValues(alpha: 0.2),
    onSecondaryContainer: secondary,
    tertiary: tertiary,
    onTertiary: PlayaColors.bg,
    tertiaryContainer: tertiary.withValues(alpha: 0.2),
    onTertiaryContainer: tertiary,
    error: PlayaColors.error,
    onError: PlayaColors.bg,
    errorContainer: PlayaColors.error.withValues(alpha: 0.2),
    onErrorContainer: PlayaColors.error,
    surface: PlayaColors.surface,
    onSurface: PlayaColors.onSurface,
    surfaceContainerHighest: PlayaColors.surfaceVariant,
    onSurfaceVariant: PlayaColors.onSurfaceVariant,
    outline: PlayaColors.border,
    outlineVariant: PlayaColors.borderSubtle,
    shadow: PlayaColors.scrim,
    surfaceTint: surfaceTint,
    inverseSurface: PlayaColors.onSurface,
    onInverseSurface: PlayaColors.surface,
    inversePrimary: primary.withValues(alpha: 0.8),
  );
}
