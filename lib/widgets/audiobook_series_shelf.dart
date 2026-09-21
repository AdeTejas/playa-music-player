import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart' as oaq;
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../design/design_system.dart';
import '../utils/audiobook_series.dart';
import '../utils/audio_display_labels.dart';
import 'player_provider.dart';

/// Horizontal shelf of multi-chapter audiobook series (best-effort grouping).
class AudiobookSeriesShelf extends StatelessWidget {
  final List<oaq.SongModel> librarySongs;

  const AudiobookSeriesShelf({super.key, required this.librarySongs});

  @override
  Widget build(BuildContext context) {
    final groups = groupAudiobookSeries(librarySongs);
    if (groups.isEmpty) return const SizedBox.shrink();

    final accent = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PlayaSectionHeader(title: 'Audiobook Series'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Grouped by album/folder. Embedded CUE/chapter atoms are not parsed yet.',
            style: TextStyle(
              color: PlayaColors.onSurfaceVariant.withValues(alpha: 0.85),
              fontSize: 11,
              height: 1.3,
            ),
          ),
        ),
        SizedBox(
          height: 118,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: PlayaSpacing.sm * 2),
            itemCount: groups.length,
            separatorBuilder: (_, __) => const SizedBox(width: PlayaSpacing.sm),
            itemBuilder: (context, index) {
              final group = groups[index];
              return SizedBox(
                width: 200,
                child: GlassPanel(
                  useStrongVariant: true,
                  borderRadius: BorderRadius.circular(PlayaRadii.kRadius),
                  borderColor: PlayaColors.border,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(PlayaRadii.kRadius),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      final songs = [
                        for (final c in group.chapters) c.song,
                      ];
                      PlayerProvider.of(context).replaceQueue(
                        songs,
                        initialIndex: 0,
                        queueContextType: 'audiobookSeries',
                        queueContextId: group.seriesKey,
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                PhosphorIconsBold.books,
                                size: 18,
                                color: accent,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  group.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: PlayaColors.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            AudioDisplayLabels.displayArtistOrFallback(
                              artist: group.artist,
                              fallback: 'Narrator unknown',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: PlayaColors.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${group.chapterCount} chapters',
                            style: TextStyle(
                              fontSize: 11,
                              color: accent.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
