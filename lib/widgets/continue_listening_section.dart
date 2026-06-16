import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models/listening_progress.dart';
import '../services/player_controller.dart';
import '../ui/tokens.dart';

class ContinueListeningSection extends StatelessWidget {
  final List<ListeningProgress> items;
  final PlayerController ctrl;
  final List<dynamic> librarySongs;
  final VoidCallback? onResume;

  const ContinueListeningSection({
    super.key,
    required this.items,
    required this.ctrl,
    required this.librarySongs,
    this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final accent = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            PlayaSpacing.sm * 2,
            PlayaSpacing.sm,
            PlayaSpacing.sm * 2,
            PlayaSpacing.sm,
          ),
          child: Row(
            children: [
              PhosphorIcon(
                PhosphorIconsFill.bookOpen,
                color: accent,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text(
                'Continue Listening',
                style: TextStyle(
                  fontSize: PlayaTypography.md,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: PlayaSpacing.sm * 2),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: PlayaSpacing.sm),
            itemBuilder: (context, index) {
              final item = items[index];
              return _ContinueCard(
                progress: item,
                accent: accent,
                onTap: () async {
                  await ctrl.resumeListeningProgress(
                    item,
                    librarySongs.cast(),
                    autoPlay: true,
                  );
                  onResume?.call();
                },
              );
            },
          ),
        ),
        const SizedBox(height: PlayaSpacing.sm),
      ],
    );
  }
}

class _ContinueCard extends StatelessWidget {
  final ListeningProgress progress;
  final Color accent;
  final VoidCallback onTap;

  const _ContinueCard({
    required this.progress,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = progress.artist?.trim().isNotEmpty == true
        ? progress.artist!
        : _formatResumeTime(progress.positionMs);

    return SizedBox(
      width: 220,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(PlayaRadii.md),
          child: GlassPanel(
            borderRadius: BorderRadius.circular(PlayaRadii.md),
            borderColor: accent.withValues(alpha: 0.25),
            backgroundColor: kColorGlassBlackTint,
            child: Padding(
              padding: const EdgeInsets.all(PlayaSpacing.sm * 1.5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      PhosphorIcon(
                        PhosphorIconsFill.playCircle,
                        color: accent,
                        size: 28,
                      ),
                      const Spacer(),
                      Text(
                        _formatResumeTime(progress.positionMs),
                        style: TextStyle(
                          color: accent,
                          fontSize: PlayaTypography.xs,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    progress.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: PlayaTypography.sm,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PlayaColors.onSurfaceVariant,
                      fontSize: PlayaTypography.xs,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _formatResumeTime(int positionMs) {
  final d = Duration(milliseconds: positionMs);
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) return '$h:$m:$s';
  return '$m:$s';
}