import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class FrostedGlassShader extends StatefulWidget {
  final Widget child;
  final BorderRadius? borderRadius;

  const FrostedGlassShader({
    super.key,
    required this.child,
    this.borderRadius,
  });

  @override
  State<FrostedGlassShader> createState() => _FrostedGlassShaderState();
}

class _FrostedGlassShaderState extends State<FrostedGlassShader> with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  double _time = 0.0;
  ui.FragmentProgram? _program;

  @override
  void initState() {
    super.initState();
    _loadShader();
    _ticker = createTicker((elapsed) {
      setState(() {
        _time = elapsed.inMilliseconds / 1000.0;
      });
    });
    _ticker.start();
  }

  Future<void> _loadShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset('shaders/frosted_glass.frag');
      setState(() => _program = program);
    } catch (e) {
      print('Error loading shader: $e');
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_program == null) {
      // Fallback while loading or if failed
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1B1F26).withOpacity(0.9),
          borderRadius: widget.borderRadius,
        ),
        child: widget.child,
      );
    }

    return ClipRRect(
      borderRadius: widget.borderRadius ?? BorderRadius.zero,
      child: CustomPaint(
        painter: _ShaderPainter(_program!, _time),
        child: widget.child,
      ),
    );
  }
}

class _ShaderPainter extends CustomPainter {
  final ui.FragmentProgram program;
  final double time;

  _ShaderPainter(this.program, this.time);

  @override
  void paint(Canvas canvas, Size size) {
    final shader = program.fragmentShader();
    
    // Uniforms: uResolution (vec2), uTime (float)
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, time);

    final paint = Paint()..shader = shader;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _ShaderPainter oldDelegate) => 
      oldDelegate.time != time || oldDelegate.program != program;
}
