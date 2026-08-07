import 'dart:math';
import 'package:flutter/material.dart';

class DesignUtils {
  const DesignUtils._();

  /// Draws a fine micro-grain noise pattern.
  static void drawNoise(Canvas canvas, Size size, {double opacity = 0.05, int seed = 42}) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..blendMode = BlendMode.softLight;

    final random = Random(seed);
    final count = (size.width * size.height * 0.005).toInt();
    for (int i = 0; i < count; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final r = 0.3 + random.nextDouble() * 0.5;
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }
}

class NoisePainter extends CustomPainter {
  final double opacity;
  final int seed;
  const NoisePainter({this.opacity = 0.05, this.seed = 42});

  @override
  void paint(Canvas canvas, Size size) {
    DesignUtils.drawNoise(canvas, size, opacity: opacity, seed: seed);
  }

  @override
  bool shouldRepaint(covariant NoisePainter oldDelegate) => 
      oldDelegate.opacity != opacity || oldDelegate.seed != seed;
}
