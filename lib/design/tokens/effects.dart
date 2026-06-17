import 'package:flutter/material.dart';
import 'colors.dart';
import 'radii.dart';

/// Playa Design System - Visual Effects
class PlayaEffects {
  const PlayaEffects._();

  // ==================== GLASS VARIANTS (always transparent) ====================
  static BoxDecoration glass({
    BorderRadius? borderRadius,
    Color? color,
    double borderWidth = 1.0,
  }) {
    return BoxDecoration(
      color: color ?? PlayaColors.glass,
      borderRadius: borderRadius ?? BorderRadius.circular(PlayaRadii.md),
      border: Border.all(
        color: PlayaColors.borderSubtle,
        width: borderWidth,
      ),
    );
  }

  static BoxDecoration glassStrong({
    BorderRadius? borderRadius,
    Color? color,
  }) {
    return BoxDecoration(
      color: color ?? PlayaColors.glassStrong,
      borderRadius: borderRadius ?? BorderRadius.circular(PlayaRadii.lg),
      border: Border.all(color: PlayaColors.border, width: 1.0),
    );
  }

  static BoxDecoration glassDeep({
    BorderRadius? borderRadius,
    Color? color,
  }) {
    return BoxDecoration(
      color: color ?? PlayaColors.glassDeep,
      borderRadius: borderRadius ?? BorderRadius.circular(PlayaRadii.lg),
      border: Border.all(color: PlayaColors.border, width: 1.0),
    );
  }

  static BoxDecoration glassSubtle({
    BorderRadius? borderRadius,
  }) {
    return BoxDecoration(
      color: PlayaColors.glassSubtle,
      borderRadius: borderRadius ?? BorderRadius.circular(PlayaRadii.sm),
      border: Border.all(color: PlayaColors.borderSubtle, width: 0.75),
    );
  }

  /// Transparent inset field (search bars inside glass panels).
  static BoxDecoration insetField({
    BorderRadius? borderRadius,
  }) {
    return BoxDecoration(
      color: PlayaColors.glassLight,
      borderRadius: borderRadius ?? BorderRadius.circular(PlayaRadii.pill),
      border: Border.all(color: PlayaColors.borderSubtle, width: 0.75),
    );
  }

  /// Layered matte surface with warm/cool depth — premium panel texture.
  static BoxDecoration matteSurface({
    BorderRadius? borderRadius,
    bool elevated = false,
  }) {
    return BoxDecoration(
      borderRadius: borderRadius ?? BorderRadius.circular(PlayaRadii.md),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: elevated
            ? [
                PlayaColors.card,
                PlayaColors.matteWarm,
                PlayaColors.matteGraphite,
              ]
            : [
                Color.lerp(PlayaColors.surfaceVariant, PlayaColors.matteCool, 0.35)!,
                PlayaColors.surface,
                PlayaColors.matteGraphite,
              ],
        stops: const [0.0, 0.52, 1.0],
      ),
      border: Border.all(color: PlayaColors.borderSubtle, width: 0.75),
    );
  }

  // ==================== SHADOWS ====================
  static List<BoxShadow> get shadowSm => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.38),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
        BoxShadow(
          color: PlayaColors.matteWarm.withValues(alpha: 0.06),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];

  static List<BoxShadow> get shadowMd => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.48),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: PlayaColors.matteWarm.withValues(alpha: 0.08),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get shadowLg => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.58),
          blurRadius: 28,
          offset: const Offset(0, 10),
        ),
        BoxShadow(
          color: PlayaColors.matteWarm.withValues(alpha: 0.10),
          blurRadius: 14,
          offset: const Offset(0, 4),
        ),
      ];
}