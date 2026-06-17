import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../services/settings_service.dart';
import '../tokens/effects.dart';
import '../tokens/radii.dart';

/// Playa Design System - GlassPanel
///
/// Panels are **transparent glass** by default so the deep-space background
/// shows through. When [SettingsService.effectiveFrostedGlassBlur] is enabled,
/// a backdrop blur is applied for a frosted look.
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
  final bool useDeepVariant;
  final double? backdropBlurSigma;
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
    this.useDeepVariant = false,
    this.backdropBlurSigma,
    this.useShader = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SettingsService.instance,
      builder: (context, _) {
        final frosted = SettingsService.instance.effectiveFrostedGlassBlur;
        final BorderRadius radius =
            borderRadius ?? BorderRadius.circular(PlayaRadii.md);
        final Color? tint = color ?? backgroundColor;

        BoxDecoration decoration;

        if (useDeepVariant) {
          decoration = PlayaEffects.glassDeep(
            borderRadius: radius,
            color: tint,
          );
        } else if (useStrongVariant) {
          decoration = PlayaEffects.glassStrong(
            borderRadius: radius,
            color: tint,
          );
        } else if (useSubtleVariant) {
          decoration = PlayaEffects.glassSubtle(borderRadius: radius);
        } else {
          decoration = PlayaEffects.glass(
            borderRadius: radius,
            color: tint,
            borderWidth: borderWidth ?? 1.0,
          );
        }

        if (borderColor != null) {
          decoration = decoration.copyWith(
            border: Border.all(color: borderColor!, width: borderWidth ?? 1.0),
          );
        }

        if (boxShadow != null) {
          decoration = decoration.copyWith(boxShadow: boxShadow);
        }

        Widget panel = Container(
          padding: padding,
          decoration: decoration,
          child: child,
        );

        panel = ClipRRect(
          borderRadius: radius,
          child: frosted
              ? BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: backdropBlurSigma ?? 12.0,
                    sigmaY: backdropBlurSigma ?? 12.0,
                  ),
                  child: panel,
                )
              : panel,
        );

        return panel;
      },
    );
  }
}