import 'package:flutter/material.dart';
import 'colors.dart';
import 'radii.dart';

/// Playa Design System - Visual Effects
class PlayaEffects {
  const PlayaEffects._();

  // ==================== GLASS VARIANTS ====================
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
  }) {
    return BoxDecoration(
      color: PlayaColors.glassStrong,
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

  // ==================== SHADOWS ====================
  static List<BoxShadow> get shadowSm => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.2),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get shadowMd => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.25),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get shadowLg => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.3),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];
}
