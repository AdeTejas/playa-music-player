import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playa_clean/services/settings_service.dart';
import 'package:playa_clean/utils/accent_hue.dart';

void main() {
  test('color presets have distinct hues', () {
    AccentHue.assertDistinctPresets(SettingsService.colorPresets);
    final hues = SettingsService.colorPresets.values
        .map((v) => AccentHue.of(Color(v)))
        .toList();
    for (int i = 0; i < hues.length; i++) {
      for (int j = i + 1; j < hues.length; j++) {
        expect(
          AccentHue.distance(hues[i], hues[j]),
          greaterThanOrEqualTo(AccentHue.minSeparation),
        );
      }
    }
  });

  test('ensureDistinct nudges hue away from neighbors', () {
    final neighbor = const Color(0xFFDC2626);
    final close = HSLColor.fromAHSL(1.0, 5, 0.8, 0.5).toColor();
    final distinct = AccentHue.ensureDistinct(close, avoid: [neighbor]);
    expect(
      AccentHue.isDistinctFrom(distinct, neighbor),
      isTrue,
    );
  });
}