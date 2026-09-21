import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart' as oaq;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../design/design_system.dart';
import '../models/listening_progress.dart';
import '../repositories/listening_progress_repository.dart';
import '../services/player_controller.dart';
import '../utils/content_mode.dart';

class ContinueListeningSection extends StatelessWidget {
  /// Carousel lane height — must match [_ContinueCard] height.
  static const double carouselHeight = 140;

  /// Card width in the horizontal carousel.
  static const double cardWidth = 220;

  final List<ListeningProgress> items;
  final PlayerController ctrl;
  final List<oaq.SongModel> librarySongs;
  final VoidCallback? onResume;
  final Future<void> Function(String seriesKey)? onDismiss;

  const ContinueListeningSection({
    super.key,
    required this.items,
    required this.ctrl,
    required this.librarySongs,
    this.onResume,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final accent = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PlayaSectionHeader(title: 'Continue Listening'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Swipe up or tap X to hide a series from this row.',
            style: TextStyle(
              color: PlayaColors.onSurfaceVariant.withValues(alpha: 0.85),
              fontSize: 11,
              height: 1.3,
            ),
          ),
        ),
        SizedBox(
          height: carouselHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: PlayaSpacing.sm * 2),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: PlayaSpacing.sm),
            itemBuilder: (context, index) {
              final item = items[index];
              final durationMs = ListeningProgressRepository.durationMsForProgress(
                item,
                librarySongs,
              );

              final card = _ContinueCard(
                progress: item,
                accent: accent,
                durationMs: durationMs,
                onTap: () async {
                  await ctrl.resumeListeningProgress(
                    item,
                    librarySongs,
                    autoPlay: true,
                  );
                  onResume?.call();
                },
                onDismiss: onDismiss == null
                    ? null
                    : () => onDismiss!(item.seriesKey),
              );

              if (onDismiss == null) return card;

              // Swipe up to dismiss — avoids fighting horizontal scroll.
              return SizedBox(
                width: cardWidth,
                height: carouselHeight,
                child: Dismissible(
                  key: ValueKey('continue-${item.seriesKey}'),
                  direction: DismissDirection.up,
                  onDismissed: (_) => onDismiss!(item.seriesKey),
                  background: Container(
                    alignment: Alignment.bottomCenter,
                    padding: const EdgeInsets.only(bottom: PlayaSpacing.sm),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(PlayaRadii.sm),
                    ),
                    child: const Icon(
                      PhosphorIconsRegular.trash,
                      color: Colors.redAccent,
                      size: 22,
                    ),
                  ),
                  child: card,
                ),
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
  final int? durationMs;
  final VoidCallback onTap;
  final Future<void> Function()? onDismiss;

  const _ContinueCard({
    required this.progress,
    required this.accent,
    required this.durationMs,
    required this.onTap,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final subtitle = progress.artist?.trim().isNotEmpty == true
        ? progress.artist!
        : (progress.contentMode == ContentMode.audiobook
            ? 'Audiobook'
            : 'Music');

    final progressFraction = _progressFraction(progress.positionMs, durationMs);

    final detailLine = progressFraction != null
        ? '$subtitle · ${(progressFraction * 100).round()}%'
        : subtitle;

    return SizedBox(
      width: ContinueListeningSection.cardWidth,
      height: ContinueListeningSection.carouselHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(PlayaRadii.md),
          child: GlassPanel(
            useStrongVariant: true,
            borderRadius: BorderRadius.circular(PlayaRadii.md),
            borderColor: accent.withValues(alpha: 0.35),
            child: Padding(
              padding: const EdgeInsets.all(PlayaSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 24,
                    child: Row(
                      children: [
                        PhosphorIcon(
                          PhosphorIconsFill.playCircle,
                          color: accent,
                          size: 22,
                        ),
                        const Spacer(),
                        if (onDismiss != null)
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: IconButton(
                              tooltip: 'Hide from Continue Listening',
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              icon: const Icon(
                                PhosphorIconsRegular.x,
                                size: 16,
                                color: PlayaColors.onSurfaceVariant,
                              ),
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                onDismiss!();
                              },
                            ),
                          ),
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
                  ),
                  if (progressFraction != null) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progressFraction,
                        minHeight: 3,
                        backgroundColor: PlayaColors.trackMuted,
                        color: accent.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          progress.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: PlayaTypography.sm,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          detailLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: PlayaColors.onSurfaceVariant,
                            fontSize: PlayaTypography.xs,
                            height: 1.2,
                          ),
                        ),
                      ],
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

double? _progressFraction(int positionMs, int? durationMs) {
  if (durationMs == null || durationMs <= 0) return null;
  return (positionMs / durationMs).clamp(0.0, 1.0);
}

String _formatResumeTime(int positionMs) {
  final d = Duration(milliseconds: positionMs);
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) return '$h:$m:$s';
  return '$m:$s';
}