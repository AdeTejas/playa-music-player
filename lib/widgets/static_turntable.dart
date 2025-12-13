import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../ui/turntable_painters.dart';

class StaticTurntable extends StatelessWidget {
  final ui.Image? labelImage;
  final bool isPlaying;

  const StaticTurntable({super.key, this.labelImage, this.isPlaying = false});

  @override
  Widget build(BuildContext context) {
    final accentColor = Theme.of(context).colorScheme.primary;
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
