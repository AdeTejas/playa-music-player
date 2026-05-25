import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../ui/turntable_painters.dart';

Color _neutralizeTurntableAccent(Color accent) {
  final hsl = HSLColor.fromColor(accent);
  return hsl
      .withSaturation((hsl.saturation * 0.28).clamp(0.0, 1.0))
      .withLightness((hsl.lightness * 0.74 + 0.16).clamp(0.0, 1.0))
      .toColor();
}

class StaticTurntable extends StatelessWidget {
  final ui.Image? labelImage;
  final bool isPlaying;

  const StaticTurntable({super.key, this.labelImage, this.isPlaying = false});

  @override
  Widget build(BuildContext context) {
    final accentColor = _neutralizeTurntableAccent(
      Theme.of(context).colorScheme.primary,
    );
    return Container(
      width: 200,
      height: 200,
      color: Colors.transparent,
      child: Stack(
        children: [
          CustomPaint(
            size: const Size(200, 200),
            painter: TurntableBasePainter(
              strobeEnabled: true,
              strobeColor: Colors.green,
              accentColor: accentColor,
            ),
          ),
          CustomPaint(
            size: const Size(200, 200),
            painter: TurntableSpinnerPainter(
              progress: 0.3, // Static position
              discAngle: 0.0,
              velocity: isPlaying ? 1.0 : 0.0,
              strobeColor: Colors.green,
              labelImage: labelImage,
              strobeEnabled: true,
              is33RPM: true,
              isPlaying: isPlaying,
              accentColor: accentColor,
            ),
          ),
        ],
      ),
    );
  }
}
