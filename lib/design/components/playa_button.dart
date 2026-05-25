import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

/// Playa Design System - PlayaButton
///
/// Primary action button with the app's high-tech glass aesthetic.
class PlayaButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final IconData? icon;
  final bool isLoading;
  final double? width;

  const PlayaButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isPrimary = true,
    this.icon,
    this.isLoading = false,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor =
        isPrimary ? PlayaColors.accent : PlayaColors.glassStrong;
    final textColor = isPrimary ? Colors.black : PlayaColors.onSurface;

    return SizedBox(
      width: width,
      child: FilledButton(
        onPressed: isLoading ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: textColor,
          padding: const EdgeInsets.symmetric(
            horizontal: PlayaSpacing.lg,
            vertical: PlayaSpacing.sm + 4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PlayaRadii.pill),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              if (icon != null) ...[
                Icon(icon, size: 18),
                const SizedBox(width: PlayaSpacing.sm),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: PlayaTypography.md,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
