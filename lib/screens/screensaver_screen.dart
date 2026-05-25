// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

import '../ui/deep_space_background.dart';
import '../ui/tokens.dart';

class ScreensaverScreen extends StatelessWidget {
  const ScreensaverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PlayaColors.bg,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Navigator.of(context).maybePop();
        },
        child: Stack(
          children: [
            const Positioned.fill(
              child: DeepSpaceBackground(
                subtle: false,
                mode: DeepSpaceMode.background,
              ),
            ),
            const Positioned.fill(
              child: DeepSpaceBackground(
                subtle: false,
                mode: DeepSpaceMode.overlay,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: SafeArea(
                top: false,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      'Tap anywhere to exit',
                      style: TextStyle(
                        color: kColorOn.withOpacity(0.88),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
