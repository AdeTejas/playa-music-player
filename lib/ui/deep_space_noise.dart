import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Lightweight value-noise + FBM helpers for procedural nebula fields.
class DeepSpaceNoise {
  DeepSpaceNoise._();

  static double hash21(double x, double y) {
    final v = sin(x * 127.1 + y * 311.7) * 43758.5453123;
    return v - v.floorToDouble();
  }

  static double lerp(double a, double b, double t) => a + (b - a) * t;
  static double smooth(double t) => t * t * (3 - 2 * t);

  static double valueNoise2d(double x, double y) {
    final x0 = x.floorToDouble();
    final y0 = y.floorToDouble();
    final x1 = x0 + 1;
    final y1 = y0 + 1;
    final sx = smooth(x - x0);
    final sy = smooth(y - y0);

    final n00 = hash21(x0, y0);
    final n10 = hash21(x1, y0);
    final n01 = hash21(x0, y1);
    final n11 = hash21(x1, y1);

    final ix0 = lerp(n00, n10, sx);
    final ix1 = lerp(n01, n11, sx);
    return lerp(ix0, ix1, sy);
  }

  static double fbm(
    double x,
    double y, {
    int octaves = 4,
    double lacunarity = 2.0,
    double gain = 0.5,
  }) {
    var sum = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i = 0; i < octaves; i++) {
      sum += valueNoise2d(x * freq, y * freq) * amp;
      freq *= lacunarity;
      amp *= gain;
    }
    return sum.clamp(0.0, 1.0);
  }

  static double ridgeNoise(double x, double y, {int octaves = 3}) {
    var sum = 0.0;
    var amp = 0.55;
    var freq = 1.0;
    for (var i = 0; i < octaves; i++) {
      final n = valueNoise2d(x * freq, y * freq);
      sum += (1.0 - (n * 2 - 1).abs()) * amp;
      freq *= 2.1;
      amp *= 0.5;
    }
    return sum.clamp(0.0, 1.0);
  }

  /// Paints a tiled noise nebula field using sparse radial stamps.
  static void paintNebulaField({
    required Canvas canvas,
    required Size size,
    required double timeSeconds,
    required Color tint,
    required double alphaMul,
    required int gridCols,
    required int gridRows,
    required double panX,
    required double panY,
  }) {
    final cellW = size.width / gridCols;
    final cellH = size.height / gridRows;
    final paint = Paint()..blendMode = BlendMode.screen;

    for (var gy = 0; gy < gridRows; gy++) {
      for (var gx = 0; gx < gridCols; gx++) {
        final u = (gx + panX) / gridCols;
        final v = (gy + panY) / gridRows;
        final density = fbm(
          u * 2.8 + timeSeconds * 0.012,
          v * 2.8 + timeSeconds * 0.010,
          octaves: 4,
        );
        final filament = ridgeNoise(
          u * 5.5 - timeSeconds * 0.008,
          v * 5.5 + timeSeconds * 0.006,
          octaves: 3,
        );
        final lane = fbm(u * 7.0 + 12.3, v * 7.0 + 4.7, octaves: 2);
        final mix = (density * 0.72 + filament * 0.38).clamp(0.0, 1.0);
        if (mix < 0.48) continue;

        final cx = gx * cellW + cellW * 0.5;
        final cy = gy * cellH + cellH * 0.5;
        final wobbleX = sin(timeSeconds * 0.07 + gx * 0.31) * cellW * 0.18;
        final wobbleY = cos(timeSeconds * 0.06 + gy * 0.27) * cellH * 0.18;
        final center = Offset(cx + wobbleX, cy + wobbleY);
        final radius = max(cellW, cellH) * (0.55 + mix * 0.95);

        paint.shader = ui.Gradient.radial(
          center,
          radius,
          [
            tint.withValues(alpha: (0.05 + mix * 0.08) * alphaMul),
            tint.withValues(alpha: (0.015 + mix * 0.03) * alphaMul),
            Colors.transparent,
          ],
          const [0.0, 0.58, 1.0],
        );
        canvas.drawCircle(center, radius, paint);

        if (lane > 0.62) {
          paint
            ..shader = ui.Gradient.radial(
              center,
              radius * 0.85,
              [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.08 * alphaMul * (lane - 0.55)),
              ],
              const [0.0, 1.0],
            )
            ..blendMode = BlendMode.multiply;
          canvas.drawCircle(center, radius * 0.85, paint);
          paint.blendMode = BlendMode.screen;
        }
      }
    }
    paint.shader = null;
    paint.blendMode = BlendMode.srcOver;
  }
}