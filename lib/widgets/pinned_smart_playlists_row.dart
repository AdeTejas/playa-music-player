import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../design/design_system.dart';
import '../screens/smart_playlist_screen.dart';
import '../services/settings_service.dart';
import '../utils/smart_playlist_catalog.dart';

/// Quick-open chips for smart playlists the user pinned from Playlists.
class PinnedSmartPlaylistsRow extends StatelessWidget {
  const PinnedSmartPlaylistsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SettingsService.instance,
      builder: (context, _) {
        final settings = SettingsService.instance;
        final pinned = [
          for (final id in settings.smartPlaylistOrder)
            if (settings.isSmartPlaylistPinned(id))
              smartPlaylistInfoFor(id),
        ].whereType<SmartPlaylistInfo>().toList();

        if (pinned.isEmpty) return const SizedBox.shrink();

        final accent = Theme.of(context).colorScheme.primary;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const PlayaSectionHeader(title: 'Pinned Smart Playlists'),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: PlayaSpacing.sm * 2,
                ),
                itemCount: pinned.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: PlayaSpacing.xs),
                itemBuilder: (context, index) {
                  final info = pinned[index];
                  return ActionChip(
                    avatar: Icon(info.icon, size: 16, color: info.color),
                    label: Text(info.title),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SmartPlaylistScreen(type: info.type),
                        ),
                      );
                    },
                    backgroundColor: accent.withValues(alpha: 0.08),
                    side: BorderSide(color: accent.withValues(alpha: 0.25)),
                    labelStyle: const TextStyle(
                      color: PlayaColors.onSurface,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: PlayaSpacing.sm),
          ],
        );
      },
    );
  }
}
