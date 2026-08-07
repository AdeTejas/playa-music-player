import 'dart:math';
import 'package:flutter/material.dart';
import '../tokens/colors.dart';
import '../tokens/radii.dart';

/// Playa Design System - RichMatteTexture
///
/// A high-tech component that adds visual "weight" and richness to surfaces.
/// Includes microscopic grain (noise) and multi-directional satin lighting.
class RichMatteTexture extends StatelessWidget {
  final Widget? child;
  final BorderRadius? borderRadius;
  final bool elevated;
  final double noiseOpacity;
  final Color? baseColor;

  const RichMatteTexture({
    super.key,
    this.child,
    this.borderRadius,
    this.elevated = false,
    this.noiseOpacity = 0.04,
    this.baseColor,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.circular(PlayaRadii.md);

    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        color: baseColor ?? (elevated ? PlayaColors.card : PlayaColors.surface),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            // 1. Base Gradient Depth
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(Colors.white, Colors.transparent, 0.96)!,
                      Colors.transparent,
                      Color.lerp(Colors.black, Colors.transparent, 0.92)!,
                    ],
                  ),
                ),
              ),
            ),

            // 2. Micro-Grain (Stone/Metal Texture)
            Positioned.fill(
              child: CustomPaint(
                painter: _MatteGrainPainter(opacity: noiseOpacity),
              ),
            ),

            // 3. Satin Highlight (Top Edge)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.white.withValues(alpha: elevated ? 0.08 : 0.05),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            if (child != null) child!,
          ],
        ),
      ),
    );
  }
}

class _MatteGrainPainter extends CustomPainter {
  final double opacity;
  _MatteGrainPainter({required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..blendMode = BlendMode.softLight;

    final random = Random(42);
    // Draw micro-specks to simulate material density
    for (int i = 0; i < (size.width * size.height * 0.01).toInt(); i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final r = 0.4 + random.nextDouble() * 0.6;
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MatteGrainPainter oldDelegate) => false;
}
