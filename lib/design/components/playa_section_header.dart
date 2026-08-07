import 'package:flutter/material.dart';
import '../tokens/colors.dart';
import '../tokens/spacing.dart';

class PlayaSectionHeader extends StatelessWidget {
  final String title;
  final bool showDivider;

  const PlayaSectionHeader({
    super.key,
    required this.title,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final cleanTitle = title.toUpperCase().replaceAll(' ', '_');
    return Padding(
      padding: const EdgeInsets.only(
        top: PlayaSpacing.md,
        bottom: PlayaSpacing.sm,
        left: PlayaSpacing.xs,
      ),
      child: Row(
        children: [
          Text(
            '[SYS//$cleanTitle]',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              letterSpacing: 1.2,
              color: PlayaColors.onSurfaceVariant,
            ),
          ),
          if (showDivider) ...[
            const SizedBox(width: 8),
            const Expanded(
              child: Divider(
                color: PlayaColors.borderSubtle,
                thickness: 0.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
