import 'package:flutter/material.dart';
import 'tokens.dart';

class FrostedGlassShader extends StatefulWidget {
  final Widget child;
  final BorderRadius? borderRadius;

  const FrostedGlassShader({super.key, required this.child, this.borderRadius});

  @override
  State<FrostedGlassShader> createState() => _FrostedGlassShaderState();
}

class _FrostedGlassShaderState extends State<FrostedGlassShader> {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kColorGlassBlackTint,
        borderRadius: widget.borderRadius,
      ),
      child: widget.child,
    );
  }
}
