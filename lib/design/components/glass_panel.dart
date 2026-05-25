import 'package:flutter/material.dart';

import '../tokens/effects.dart';
import '../tokens/radii.dart';

/// Playa Design System - GlassPanel
///
/// The foundational surface component for the entire app.
/// This version includes compatibility fields for the legacy UI migration.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final double? borderWidth;
  final Color? borderColor;
  final Color? color;
  final Color? backgroundColor; // Alias for color
  final List<BoxShadow>? boxShadow;
  final bool useStrongVariant;
  final bool useSubtleVariant;
  final double? backdropBlurSigma; // Legacy compatibility
  final bool useShader; // Legacy compatibility

  const GlassPanel({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.borderWidth,
    this.borderColor,
    this.color,
    this.backgroundColor,
    this.boxShadow,
    this.useStrongVariant = false,
    this.useSubtleVariant = false,
    this.backdropBlurSigma,
    this.useShader = false,
  });

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius =
        borderRadius ?? BorderRadius.circular(PlayaRadii.md);

    final Color? effectiveColor = color ?? backgroundColor;

    BoxDecoration decoration;

    if (useStrongVariant) {
      decoration = PlayaEffects.glassStrong(borderRadius: radius);
    } else if (useSubtleVariant) {
      decoration = PlayaEffects.glassSubtle(borderRadius: radius);
    } else {
      decoration = PlayaEffects.glass(
        borderRadius: radius,
        color: effectiveColor,
        borderWidth: borderWidth ?? 1.0,
      );
    }

    // Apply custom border color if provided
    if (borderColor != null) {
      decoration = decoration.copyWith(
        border: Border.all(color: borderColor!, width: borderWidth ?? 1.0),
      );
    }

    if (boxShadow != null) {
      decoration = decoration.copyWith(boxShadow: boxShadow);
    }

    return Container(
      padding: padding,
      decoration: decoration,
      child: child,
    );
  }
}
