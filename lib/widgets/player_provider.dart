import 'package:flutter/material.dart';
import '../services/player_controller.dart';

class PlayerProvider extends InheritedWidget {
  final PlayerController ctrl;
  const PlayerProvider({
    required this.ctrl,
    required super.child,
  });

  static PlayerController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlayerProvider>()!.ctrl;

  @override
  bool updateShouldNotify(covariant PlayerProvider oldWidget) =>
      ctrl != oldWidget.ctrl;
}
