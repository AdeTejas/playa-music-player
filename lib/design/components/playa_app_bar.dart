import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../tokens/spacing.dart';
import 'glass_panel.dart';
import '../tokens/radii.dart';

class PlayaAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final VoidCallback? onBack;

  const PlayaAppBar({
    super.key,
    required this.title,
    this.actions,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: PlayaSpacing.xs,
          vertical: PlayaSpacing.xs,
        ),
        child: GlassPanel(
          borderRadius: BorderRadius.circular(PlayaRadii.md),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SizedBox(
            height: 56,
            child: NavigationToolbar(
              leading: IconButton(
                icon: const Icon(PhosphorIconsBold.caretLeft),
                onPressed: onBack ?? () => Navigator.maybePop(context),
              ),
              middle: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              trailing: actions != null
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: actions!,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(80);
}
