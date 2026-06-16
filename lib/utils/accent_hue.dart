import 'dart:math';

import 'package:flutter/material.dart';

/// Hue spacing helpers — keeps accent presets and album-art picks visually distinct.
class AccentHue {
  AccentHue._();

  /// Minimum degrees between accent hues on the color wheel.
  static const double minSeparation = 22.0;

  static double of(Color color) => HSLColor.fromColor(color).hue;

  static double distance(double a, double b) {
    final d = (a - b).abs() % 360;
    return d > 180 ? 360 - d : d;
  }

  static bool isDistinctFrom(Color candidate, Color other) {
    return distance(of(candidate), of(other)) >= minSeparation;
  }

  static bool isDistinctFromAll(Color candidate, Iterable<Color> others) {
    for (final other in others) {
      if (!isDistinctFrom(candidate, other)) return false;
    }
    return true;
  }

  /// Nudge hue until [candidate] is at least [minSeparation] from every [avoid] color.
  static Color ensureDistinct(
    Color candidate, {
    required Iterable<Color> avoid,
    double minSeparation = minSeparation,
  }) {
    if (avoid.isEmpty) return candidate;

    var hsl = HSLColor.fromColor(candidate);
    var hue = hsl.hue;

    for (int attempt = 0; attempt < 18; attempt++) {
      final test = hsl.withHue(hue).toColor();
      final ok = avoid.every(
        (c) => distance(hue, of(c)) >= minSeparation,
      );
      if (ok) return test;
      hue = (hue + minSeparation) % 360;
    }

    return hsl.withHue(hue).toColor();
  }

  /// Deterministic per-track fallback when cover color is not ready yet.
  static Color fallbackForItem(
    String key,
    Color baseAccent, {
    Iterable<Color> avoid = const [],
  }) {
    final rnd = Random(key.hashCode);
    var hue = rnd.nextDouble() * 360;
    final blocked = [baseAccent, ...avoid];

    for (int attempt = 0; attempt < 18; attempt++) {
      final color = HSLColor.fromAHSL(
        1.0,
        hue,
        0.68 + rnd.nextDouble() * 0.18,
        0.46 + rnd.nextDouble() * 0.12,
      ).toColor();
      if (blocked.every((c) => distance(hue, of(c)) >= minSeparation)) {
        return color;
      }
      hue = (hue + minSeparation) % 360;
    }

    return ensureDistinct(
      HSLColor.fromAHSL(1.0, hue, 0.72, 0.52).toColor(),
      avoid: blocked,
    );
  }

  /// Validates a preset map — every entry must differ in hue by [minSeparation].
  static void assertDistinctPresets(Map<String, int> presets) {
    final colors = presets.values.map((v) => Color(v)).toList();
    for (int i = 0; i < colors.length; i++) {
      for (int j = i + 1; j < colors.length; j++) {
        final d = distance(of(colors[i]), of(colors[j]));
        assert(
          d >= minSeparation,
          'Preset hues too close (${d.toStringAsFixed(1)}°): '
          '${colors[i]} vs ${colors[j]}',
        );
      }
    }
  }
}