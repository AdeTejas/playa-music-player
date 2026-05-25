import 'package:flutter/material.dart';

import '../tokens/colors.dart';
import '../tokens/radii.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

/// Playa Design System - PlayaSettingsTile
///
/// A polished, consistent list tile used across Settings and other lists.
/// Designed to work well inside GlassPanel surfaces.
class PlayaSettingsTile extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDivider;
  final EdgeInsetsGeometry? contentPadding;

  const PlayaSettingsTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showDivider = true,
    this.contentPadding,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PlayaRadii.md),
      child: Padding(
        padding: contentPadding ??
            const EdgeInsets.symmetric(
              horizontal: PlayaSpacing.md,
              vertical: PlayaSpacing.sm,
            ),
        child: Column(
          children: [
            Row(
              children: [
                if (leading != null) ...[
                  IconTheme(
                    data: IconThemeData(
                      color: PlayaColors.onSurfaceVariant,
                      size: 22,
                    ),
                    child: leading!,
                  ),
                  const SizedBox(width: PlayaSpacing.md),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: PlayaTypography.md,
                          color: PlayaColors.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: PlayaTypography.xs,
                              color: PlayaColors.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: PlayaSpacing.sm),
                  trailing!,
                ],
              ],
            ),
            if (showDivider)
              Padding(
                padding: const EdgeInsets.only(top: PlayaSpacing.sm),
                child: Divider(
                  height: 1,
                  color: PlayaColors.borderSubtle,
                  thickness: 0.5,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
