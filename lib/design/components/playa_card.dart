import 'package:flutter/material.dart';

import '../tokens/effects.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import 'glass_panel.dart';
import 'rich_matte_texture.dart';

/// Playa Design System - PlayaCard
///
/// A higher-level card component built on top of GlassPanel.
/// Use this for most content surfaces instead of raw GlassPanel or Container.
class PlayaCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final double elevation; // 0 = flat, 1 = subtle shadow, 2 = stronger
  final bool useStrongVariant;
  final bool useMatteVariant;
  final VoidCallback? onTap;
  final Color? color;

  const PlayaCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius,
    this.elevation = 1,
    this.useStrongVariant = false,
    this.useMatteVariant = false,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius =
        borderRadius ?? BorderRadius.circular(PlayaRadii.lg);

    List<BoxShadow>? shadows;
    if (elevation >= 2) {
      shadows = PlayaEffects.shadowMd;
    } else if (elevation >= 1) {
      shadows = PlayaEffects.shadowSm;
    }

    Widget content;
    if (useMatteVariant) {
      content = RichMatteTexture(
        borderRadius: radius,
        elevated: elevation > 0,
        baseColor: color,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(PlayaSpacing.md),
          child: child,
        ),
      );
    } else {
      content = GlassPanel(
        padding: padding ?? const EdgeInsets.all(PlayaSpacing.md),
        borderRadius: radius,
        color: color,
        useStrongVariant: useStrongVariant,
        boxShadow: shadows,
        child: child,
      );
    }

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: content,
      );
    }

    return content;
  }
}
