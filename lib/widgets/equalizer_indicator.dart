import 'dart:math' as math;
import 'package:flutter/material.dart';

class EqualizerIndicator extends StatefulWidget {
  final Color color;
  final double size;

  const EqualizerIndicator({
    super.key,
    required this.color,
    this.size = 14,
  });

  @override
  State<EqualizerIndicator> createState() => _EqualizerIndicatorState();
}

class _EqualizerIndicatorState extends State<EqualizerIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (index) => _Bar(
          controller: _controller,
          index: index,
          color: widget.color,
          maxHeight: widget.size,
        )),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final AnimationController controller;
  final int index;
  final Color color;
  final double maxHeight;

  const _Bar({
    required this.controller,
    required this.index,
    required this.color,
    required this.maxHeight,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        // Create a pseudo-random animation for each bar
        final t = controller.value;
        final offset = index * 0.33;
        final value = 0.3 + 0.7 * math.sin((t + offset) * 2 * math.pi).abs();
        
        return Container(
          width: 2.5,
          height: value * maxHeight,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1),
          ),
        );
      },
    );
  }
}
