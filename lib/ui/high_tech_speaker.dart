import 'dart:math';
import 'package:flutter/material.dart';
import 'package:playa_clean/main.dart'; // For colors

class HighTechSpeaker extends StatefulWidget {
  final bool isPlaying;
  final double? bpm;
  final double volume;

  const HighTechSpeaker({
    super.key, 
    required this.isPlaying,
    this.bpm,
    this.volume = 1.0,
  });

  @override
  State<HighTechSpeaker> createState() => _HighTechSpeakerState();
}

class _HighTechSpeakerState extends State<HighTechSpeaker> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _updateControllerDuration();
  }

  @override
  void didUpdateWidget(HighTechSpeaker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.bpm != oldWidget.bpm) {
      _updateControllerDuration();
    }
  }

  void _updateControllerDuration() {
    // Default to 120 BPM (500ms per beat) if null
    final bpm = widget.bpm ?? 120.0;
    // Clamp to reasonable values (e.g. 60-200)
    final effectiveBpm = bpm.clamp(60.0, 200.0);
    final durationMs = (60000 / effectiveBpm).round();
    
    if (mounted) {
      // If controller exists, recreate it or just update duration if possible?
      // AnimationController duration can be updated but requires reset to take effect cleanly usually.
      // Simpler to just dispose and recreate or just update duration property.
      // Actually, we can just set duration.
    }
    
    // Initial creation
    // We use a shorter duration for the "thump" animation cycle
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: durationMs),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // If not playing, settle to a "breathing" idle state
        // If playing, thump more vigorously
        // Add some randomness/noise to make it feel more "audio-reactive"
        final noise = sin(DateTime.now().millisecondsSinceEpoch * 0.01) * 0.1;
        
        final double value = widget.isPlaying 
            ? (_controller.value + noise).clamp(0.0, 1.0)
            : (_controller.value * 0.2 + 0.4); // Subtle breath when paused

        return CustomPaint(
          size: const Size(double.infinity, 120),
          painter: _SpeakerPainter(
            animationValue: value,
            isPlaying: widget.isPlaying,
            volume: widget.volume,
          ),
        );
      },
    );
  }
}

class _SpeakerPainter extends CustomPainter {
  final double animationValue;
  final bool isPlaying;
  final double volume;

  _SpeakerPainter({
    required this.animationValue, 
    required this.isPlaying,
    required this.volume,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Max radius fits within height, with some padding
    final maxRadius = (min(size.width, size.height) / 2) * 0.9;
    final scale = maxRadius / 60.0; // Reference radius 60.0
    
    // Dynamic excursion (speaker cone movement)
    final excursion = (isPlaying ? (animationValue * 8.0) : (animationValue * 2.0)) * scale * volume;

    // 1. Outer Housing (Static Ring)
    final housingPaint = Paint()
      ..color = const Color(0xFF2A2E35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0 * scale;
    
    canvas.drawCircle(center, maxRadius, housingPaint);

    // 2. Tech Accents (Glowing Ticks)
    // Changed to Amber/Gold to match wood
    final accentColor = const Color(0xFFFFB300); // Amber 600
    
    final tickPaint = Paint()
      ..color = accentColor.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * scale
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 12; i++) {
      final angle = (i * 30) * (pi / 180);
      final p1 = Offset(
        center.dx + (maxRadius + 2 * scale) * cos(angle),
        center.dy + (maxRadius + 2 * scale) * sin(angle),
      );
      final p2 = Offset(
        center.dx + (maxRadius + 8 * scale) * cos(angle),
        center.dy + (maxRadius + 8 * scale) * sin(angle),
      );
      canvas.drawLine(p1, p2, tickPaint);
    }

    // 3. Surround (Rubber edge)
    final surroundPaint = Paint()
      ..color = const Color(0xFF111111)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0 * scale;
    
    // The surround expands slightly with the beat
    canvas.drawCircle(center, maxRadius - (6 * scale) + (excursion * 0.2), surroundPaint);

    // 4. Cone (The main moving part)
    // Gradient for depth - Warm tint
    final coneGradient = RadialGradient(
      colors: [
        const Color(0xFF2D2418), // Dark brown/bronze
        const Color(0xFF0A0A0A),
      ],
      stops: const [0.0, 1.0],
    );

    final coneRadius = maxRadius - (12 * scale);
    final conePaint = Paint()
      ..shader = coneGradient.createShader(
        Rect.fromCircle(center: center, radius: coneRadius),
      );

    // Draw cone with excursion
    canvas.drawCircle(center, coneRadius - (excursion * 0.5), conePaint);

    // 5. Dust Cap (Center dome) - Moves the most
    final dustCapRadius = coneRadius * 0.35;
    final dustCapPaint = Paint()
      ..color = const Color(0xFF1A1510) // Very dark brown
      ..style = PaintingStyle.fill
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.0 * scale); // Soft look

    // Draw dust cap
    canvas.drawCircle(center, dustCapRadius + excursion, dustCapPaint);

    // 6. High Tech Glow Ring (Center)
    final glowOpacity = (0.4 + (animationValue * 0.4)) * (isPlaying ? volume : 0.5);
    final glowPaint = Paint()
      ..color = (isPlaying ? accentColor : const Color(0xFF5D4037)).withOpacity(glowOpacity.clamp(0.0, 1.0))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0 * scale
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4.0 * scale);

    canvas.drawCircle(center, dustCapRadius + excursion, glowPaint);
    
    // Sharp ring inside the glow
    final sharpRingPaint = Paint()
      ..color = (isPlaying ? accentColor : const Color(0xFF8D6E63)).withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * scale;
      
    canvas.drawCircle(center, dustCapRadius + excursion, sharpRingPaint);

    // 7. Hexagon Grid Overlay (Tech texture on cone)
    // Only draw if radius is big enough
    if (coneRadius > 20 * scale) {
      _drawHexGrid(canvas, center, coneRadius - (excursion * 0.5), isPlaying, scale);
    }
  }

  void _drawHexGrid(Canvas canvas, Offset center, double radius, bool isPlaying, double scale) {
    final hexPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 * scale;

    // Simple grid simulation
    final step = 15.0 * scale;
    for (double x = -radius; x <= radius; x += step) {
      // Vertical lines clipped to circle
      final h = sqrt(radius * radius - x * x);
      canvas.drawLine(
        Offset(center.dx + x, center.dy - h),
        Offset(center.dx + x, center.dy + h),
        hexPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpeakerPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue || 
           oldDelegate.isPlaying != isPlaying ||
           oldDelegate.volume != volume;
  }
}
