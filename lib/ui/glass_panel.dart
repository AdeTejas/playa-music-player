import 'package:flutter/material.dart';

import 'tokens.dart';

class GlassPanel extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final bool useShader;
  final double backdropBlurSigma;
  final double borderWidth;
  final Color borderColor;
  final Color backgroundColor;
  final List<BoxShadow>? boxShadow;

  const GlassPanel({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(kRadius)),
    this.padding = EdgeInsets.zero,
    // No frosted blur anywhere (global style).
    this.useShader = false,
    this.backdropBlurSigma = 0,
    this.borderWidth = 1.0,
    this.borderColor = const Color(0x1AFFFFFF),
    // Dark glass tint (no blur) default.
    this.backgroundColor = kColorGlassBlackTint,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    // Note: useShader/backdropBlurSigma are intentionally ignored.
    return ClipRRect(
      borderRadius: borderRadius,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: borderRadius,
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: boxShadow,
        ),
        child: child,
      ),
    );
  }
}
