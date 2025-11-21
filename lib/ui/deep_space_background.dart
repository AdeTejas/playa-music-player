import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

enum DeepSpaceMode { background, overlay }

class DeepSpaceBackground extends StatefulWidget {
  final bool subtle;
  final DeepSpaceMode mode;
  
  const DeepSpaceBackground({
    super.key, 
    this.subtle = false,
    this.mode = DeepSpaceMode.background,
  });

  @override
  State<DeepSpaceBackground> createState() => _DeepSpaceBackgroundState();
}

class _DeepSpaceBackgroundState extends State<DeepSpaceBackground> with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  final List<_Star> _stars = [];
  final List<_ShootingStar> _shootingStars = [];
  final Random _rnd = Random();
  Size? _lastSize;

  // Nebula clouds
  final List<Offset> _nebulaCenters = [];
  final List<Color> _nebulaColors = [];
  
  Duration _lastElapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    
    if (widget.mode == DeepSpaceMode.background) {
      // Init nebula clouds
      for (int i = 0; i < 3; i++) {
        _nebulaCenters.add(Offset(_rnd.nextDouble(), _rnd.nextDouble()));
        _nebulaColors.add(
          HSVColor.fromAHSV(0.15, 200.0 + _rnd.nextDouble() * 100, 0.6, 0.4).toColor()
        );
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(DeepSpaceBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.subtle != oldWidget.subtle && _lastSize != null) {
      if (widget.mode == DeepSpaceMode.background) {
        _initStars(_lastSize!);
      }
    }
  }

  void _initStars(Size size) {
    _stars.clear();
    final count = widget.subtle ? 50 : 300; // Increased star count
    for (int i = 0; i < count; i++) {
      // Star Color Temperature
      Color color;
      final r = _rnd.nextDouble();
      if (r > 0.9) {
        color = const Color(0xFFB3E5FC); // Blue-ish
      } else if (r > 0.7) {
        color = const Color(0xFFFFF9C4); // Yellow-ish
      } else if (r > 0.6) {
        color = const Color(0xFFFFCCBC); // Red-ish
      } else {
        color = Colors.white;
      }

      // Parallax depth (0.0 = far, 1.0 = near)
      final depth = _rnd.nextDouble();
      
      _stars.add(_Star(
        x: _rnd.nextDouble(),
        y: _rnd.nextDouble(),
        size: (0.5 + _rnd.nextDouble() * 2.0) * (widget.subtle ? 0.8 : 1.0) * (0.5 + depth * 0.5),
        brightness: 0.3 + _rnd.nextDouble() * 0.7,
        twinkleSpeed: 0.5 + _rnd.nextDouble() * 3.0,
        twinklePhase: _rnd.nextDouble() * 2 * pi,
        color: color,
        driftSpeed: (0.005 + _rnd.nextDouble() * 0.015) * (0.5 + depth), // Near stars move faster
      ));
    }
    _lastSize = size;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (_lastSize != size) {
          if (widget.mode == DeepSpaceMode.background) {
            _initStars(size);
          }
          _lastSize = size;
        }
        
        return Container(
          color: widget.mode == DeepSpaceMode.background ? const Color(0xFF06070A) : Colors.transparent,
          child: CustomPaint(
            painter: _StarFieldPainter(
              stars: _stars,
              shootingStars: _shootingStars,
              subtle: widget.subtle,
              nebulaCenters: _nebulaCenters,
              nebulaColors: _nebulaColors,
              mode: widget.mode,
            ),
          ),
        );
      },
    );
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;
    final dt = (elapsed - _lastElapsed).inMilliseconds / 1000.0;
    _lastElapsed = elapsed;
    
    if (widget.mode == DeepSpaceMode.background) {
      // Update Stars (Twinkle + Drift)
      for (final star in _stars) {
        star.update(dt);
      }
    }

    if (widget.mode == DeepSpaceMode.overlay) {
      // Manage Shooting Stars
      // Chance to spawn: 1 in 2000 ticks (very rare)
      if (!widget.subtle && _rnd.nextInt(2000) == 0) {
        _spawnShootingStar();
      }

      // Update Shooting Stars
      _shootingStars.removeWhere((s) => s.isFinished);
      for (final s in _shootingStars) {
        s.update();
      }
    }
    
    if (mounted) setState(() {});
  }

  void _spawnShootingStar() {
    final w = _lastSize?.width ?? 1000;
    final h = _lastSize?.height ?? 1000;
    
    // Dynamic Spawn Logic
    double startX, startY;
    double angle;
    
    final side = _rnd.nextInt(4); // 0: Top, 1: Right, 2: Bottom, 3: Left
    
    switch (side) {
      case 0: // Top
        startX = _rnd.nextDouble() * w;
        startY = -50;
        angle = (45 + _rnd.nextDouble() * 90) * pi / 180.0; // Downwards
        break;
      case 1: // Right
        startX = w + 50;
        startY = _rnd.nextDouble() * h;
        angle = (135 + _rnd.nextDouble() * 90) * pi / 180.0; // Leftwards
        break;
      case 2: // Bottom
        startX = _rnd.nextDouble() * w;
        startY = h + 50;
        angle = (225 + _rnd.nextDouble() * 90) * pi / 180.0; // Upwards
        break;
      case 3: // Left
      default:
        startX = -50;
        startY = _rnd.nextDouble() * h;
        angle = (-45 + _rnd.nextDouble() * 90) * pi / 180.0; // Rightwards
        break;
    }

    // Speed: Slower (100-250 range instead of 300-700)
    final speed = (100.0 + _rnd.nextDouble() * 150.0);

    // Random Color (More realistic meteor colors)
    final colors = [
      const Color(0xFFB3E5FC), // Light Blue (Ice/Magnesium)
      const Color(0xFFE1F5FE), // White-Blue
      const Color(0xFFFFF9C4), // Pale Yellow (Dust/Sodium)
      const Color(0xFFFFCCBC), // Pale Orange
      const Color(0xFFB2DFDB), // Teal (Iron)
      Colors.white,
    ];
    final color = colors[_rnd.nextInt(colors.length)];

    _shootingStars.add(_ShootingStar(
      x: startX / w,
      y: startY / h,
      angle: angle,
      speed: speed / w, // Normalize speed to screen width
      color: color,
    ));
  }
}

class _Star {
  double x, y; // 0.0 to 1.0
  double size;
  double brightness;
  double twinkleSpeed;
  double twinklePhase;
  Color color;
  double driftSpeed;

  _Star({
    required this.x,
    required this.y,
    required this.size,
    required this.brightness,
    required this.twinkleSpeed,
    required this.twinklePhase,
    required this.color,
    required this.driftSpeed,
  });

  double get currentOpacity {
    final t = DateTime.now().millisecondsSinceEpoch * 0.001 * twinkleSpeed + twinklePhase;
    // Compound sine wave for "chaotic" atmospheric twinkling
    final wave = sin(t) + sin(t * 2.7) * 0.5;
    return (brightness + wave * 0.2).clamp(0.1, 1.0);
  }

  void update(double dt) {
    // Parallax drift (slowly move left)
    x -= driftSpeed * dt;
    if (x < 0) x += 1.0;
  }
}

class _ShootingStar {
  double x, y;
  double angle;
  double speed;
  double progress = 0.0;
  bool isFinished = false;
  Color color;

  _ShootingStar({
    required this.x,
    required this.y,
    required this.angle,
    required this.speed,
    required this.color,
  });

  void update() {
    progress += 0.005; // Much slower lifecycle
    if (progress >= 1.0) isFinished = true;
    
    // Move along angle
    x += cos(angle) * speed * 0.016;
    y += sin(angle) * speed * 0.016; // Assuming ~60fps dt
  }
}

class _StarFieldPainter extends CustomPainter {
  final List<_Star> stars;
  final List<_ShootingStar> shootingStars;
  final bool subtle;
  final List<Offset> nebulaCenters;
  final List<Color> nebulaColors;
  final DeepSpaceMode mode;

  _StarFieldPainter({
    required this.stars,
    required this.shootingStars,
    required this.subtle,
    required this.nebulaCenters,
    required this.nebulaColors,
    required this.mode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint();

    if (mode == DeepSpaceMode.background) {
      // 1. Draw Nebula Clouds (Background)
      if (!subtle) {
        // Deep Space Base
        canvas.drawColor(const Color(0xFF040508), BlendMode.src);

        for (int i = 0; i < nebulaCenters.length; i++) {
          final center = Offset(nebulaCenters[i].dx * w, nebulaCenters[i].dy * h);
          final radius = w * 0.9; // Larger, softer clouds
          
          // Multi-layered nebula for depth
          final shader = ui.Gradient.radial(
            center,
            radius,
            [
              nebulaColors[i].withValues(alpha: 0.12), 
              nebulaColors[i].withValues(alpha: 0.05),
              Colors.transparent
            ],
            [0.0, 0.5, 1.0],
          );
          paint.shader = shader;
          paint.blendMode = BlendMode.screen; 
          canvas.drawCircle(center, radius, paint);
        }
        paint.blendMode = BlendMode.srcOver; 
        paint.shader = null;
      }

      // 2. Draw Stars
      for (final star in stars) {
        paint.color = star.color.withValues(alpha: star.currentOpacity * (subtle ? 0.3 : 0.8));
        canvas.drawCircle(Offset(star.x * w, star.y * h), star.size, paint);
      }
    }

    if (mode == DeepSpaceMode.overlay) {
      // 3. Draw Shooting Stars / Comets
      if (subtle) return; 

      for (final s in shootingStars) {
        final start = Offset(s.x * w, s.y * h);
        // Tail length grows and shrinks with life
        final tailLen = (w * 0.4) * sin(s.progress * pi); 
        final end = start - Offset(cos(s.angle) * tailLen, sin(s.angle) * tailLen);
        
        final alpha = sin(s.progress * pi); // Fade in then out
        
        // 1. The Tail (Gaseous Trail) - Soft wide stroke
        final tailPaint = Paint()
          ..shader = ui.Gradient.linear(
            start,
            end,
            [
              s.color.withValues(alpha: alpha * 0.3),
              s.color.withValues(alpha: alpha * 0.05),
              Colors.transparent
            ],
            [0.0, 0.5, 1.0],
          )
          ..strokeWidth = 3.0
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
          
        canvas.drawLine(start, end, tailPaint);
        
        // 2. The Core Trail (Hotter, thinner)
        tailPaint.shader = ui.Gradient.linear(
            start,
            end,
            [
              Colors.white.withValues(alpha: alpha * 0.9),
              s.color.withValues(alpha: alpha * 0.4),
              Colors.transparent
            ],
            [0.0, 0.2, 1.0],
        );
        tailPaint.strokeWidth = 1.0;
        canvas.drawLine(start, end, tailPaint);

        // 3. The Head (Coma)
        // Outer Glow
        paint.color = s.color.withValues(alpha: alpha * 0.25);
        paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
        canvas.drawCircle(start, 8.0, paint);
        
        // Inner Glow
        paint.color = s.color.withValues(alpha: alpha * 0.6);
        paint.maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
        canvas.drawCircle(start, 4.0, paint);
        paint.maskFilter = null;

        // Solid Core
        paint.color = Colors.white.withValues(alpha: alpha);
        canvas.drawCircle(start, 1.5, paint);
        
        // 4. Sparkles / Debris (Simple simulation)
        // Use stable random based on star instance to keep debris relative
        final r = Random(s.hashCode); 
        for(int i=0; i<5; i++) {
           // Debris trails behind
           final dist = r.nextDouble() * tailLen * 0.2; // Close to head
           final offset = (r.nextDouble() - 0.5) * 6.0; // Spread width
           
           // Calculate position behind head
           final debrisPos = start - Offset(cos(s.angle) * dist, sin(s.angle) * dist) 
                           + Offset(cos(s.angle + pi/2) * offset, sin(s.angle + pi/2) * offset);
           
           paint.color = s.color.withValues(alpha: alpha * 0.4 * r.nextDouble());
           canvas.drawCircle(debrisPos, 0.5 + r.nextDouble(), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StarFieldPainter oldDelegate) => true;
}
