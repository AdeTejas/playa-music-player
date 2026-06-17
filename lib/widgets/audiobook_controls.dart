import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../design/design_system.dart';
import '../services/player_controller.dart';
import '../services/settings_service.dart';
import '../utils/ui_utils.dart';
import 'bookmarks_sheet.dart';

/// Speed presets shared across audiobook controls.
const List<double> kAudiobookSpeedPresets = [1.0, 1.25, 1.5, 1.75, 2.0];

String formatAudiobookSpeed(double preset) {
  if (preset == 1.0) return '1×';
  final text = preset.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
  return '$text×';
}

/// Full-width speed selector — sits directly under the playback time row.
class AudiobookSpeedRow extends StatelessWidget {
  final PlayerController ctrl;
  final bool compact;

  const AudiobookSpeedRow({
    super.key,
    required this.ctrl,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return StreamBuilder<double>(
      stream: ctrl.player.speedStream,
      initialData: ctrl.player.speed,
      builder: (context, snap) {
        final speed = snap.data ?? 1.0;
        return Row(
          children: [
            for (var i = 0; i < kAudiobookSpeedPresets.length; i++) ...[
              if (i > 0) const SizedBox(width: PlayaSpacing.xxs),
              Expanded(
                child: _SpeedPill(
                  label: formatAudiobookSpeed(kAudiobookSpeedPresets[i]),
                  selected:
                      (speed - kAudiobookSpeedPresets[i]).abs() < 0.04,
                  accent: accent,
                  compact: compact,
                  onTap: ctrl.isReady
                      ? () async {
                          await ctrl.setPlaybackSpeed(
                            kAudiobookSpeedPresets[i],
                          );
                          HapticFeedback.selectionClick();
                        }
                      : null,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Bookmark + sleep actions below transport controls.
class AudiobookActionRow extends StatelessWidget {
  final PlayerController ctrl;
  final bool compact;

  const AudiobookActionRow({
    super.key,
    required this.ctrl,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      final accent = Theme.of(context).colorScheme.primary;
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _CompactAudiobookIcon(
            icon: PhosphorIconsBold.bookmarkSimple,
            tooltip: 'Bookmark',
            accent: accent,
            onTap: () => _addBookmark(context, ctrl),
            onLongPress: () => _showBookmarks(context, ctrl),
          ),
          const SizedBox(width: PlayaSpacing.md),
          _CompactAudiobookIcon(
            icon: PhosphorIconsBold.timer,
            tooltip: 'Sleep timer',
            accent: accent,
            onTap: () => showSleepTimerSheet(context, ctrl),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _AudiobookAction(
          icon: PhosphorIconsBold.bookmarkSimple,
          label: 'Bookmark',
          onTap: () => _addBookmark(context, ctrl),
          onLongPress: () => _showBookmarks(context, ctrl),
        ),
        const SizedBox(width: PlayaSpacing.lg),
        _AudiobookAction(
          icon: PhosphorIconsBold.timer,
          label: 'Sleep',
          onTap: () => showSleepTimerSheet(context, ctrl),
        ),
      ],
    );
  }
}

class _CompactAudiobookIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _CompactAudiobookIcon({
    required this.icon,
    required this.tooltip,
    required this.accent,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      onPressed: onTap,
      onLongPress: onLongPress,
      icon: PhosphorIcon(icon, color: accent, size: 20),
    );
  }
}

/// Primary controls for audiobook-weighted hybrid mode.
class AudiobookQuickBar extends StatelessWidget {
  final PlayerController ctrl;

  const AudiobookQuickBar({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AudiobookSpeedRow(ctrl: ctrl),
        const SizedBox(height: PlayaSpacing.kSp * 0.75),
        AudiobookActionRow(ctrl: ctrl),
      ],
    );
  }
}

void _addBookmark(BuildContext context, PlayerController ctrl) {
  if (!ctrl.isReady) {
    showToast(context, 'Nothing playing');
    return;
  }

  final controller = TextEditingController();
  showDialog<void>(
    context: context,
    builder: (ctx) {
      final a = Theme.of(ctx).colorScheme.primary;
      return AlertDialog(
        backgroundColor: PlayaColors.surface,
        title: const Text('Add Bookmark'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Note (optional)...',
            hintStyle: const TextStyle(color: Colors.white38),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: PlayaColors.onSurfaceVariant),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: a),
            ),
          ),
          style: const TextStyle(color: PlayaColors.onSurface),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: PlayaColors.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: () async {
              final ok = await ctrl.addBookmark(note: controller.text);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              showToast(
                context,
                ok ? 'Bookmark saved' : 'Could not save bookmark',
              );
              if (ok) HapticFeedback.selectionClick();
            },
            child: Text('Save', style: TextStyle(color: a)),
          ),
        ],
      );
    },
  );
}

void _showBookmarks(BuildContext context, PlayerController ctrl) async {
  if (!ctrl.isReady) return;
  await ctrl.reloadBookmarks();
  if (!context.mounted) return;
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => BookmarksSheet(ctrl: ctrl),
  );
}

class _SpeedPill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final bool compact;
  final VoidCallback? onTap;

  const _SpeedPill({
    required this.label,
    required this.selected,
    required this.accent,
    this.compact = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: PlayaSpacing.xxs,
            vertical: compact ? 3 : 5,
          ),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.85)
                : PlayaColors.surface.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? accent : Colors.white12,
              width: 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              height: 1,
              color: selected ? Colors.white : PlayaColors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _AudiobookAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _AudiobookAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 6,
            vertical: PlayaSpacing.kSp * 0.5,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(icon, color: accent, size: 20),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: PlayaColors.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Collapsed music/DJ tools — available in hybrid mode without crowding audiobook UX.
class MusicToolsExpansion extends StatefulWidget {
  final PlayerController ctrl;
  final Widget child;

  const MusicToolsExpansion({
    super.key,
    required this.ctrl,
    required this.child,
  });

  @override
  State<MusicToolsExpansion> createState() => _MusicToolsExpansionState();
}

class _MusicToolsExpansionState extends State<MusicToolsExpansion> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: PlayaSpacing.xxs),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  PhosphorIcon(
                    PhosphorIconsRegular.musicNotes,
                    size: 16,
                    color: PlayaColors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _expanded ? 'Hide tools' : 'Music tools',
                    style: const TextStyle(
                      color: PlayaColors.onSurfaceVariant,
                      fontSize: PlayaTypography.sm,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: PlayaColors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: PlayaSpacing.kSp * 0.5),
          widget.child,
        ],
      ],
    );
  }
}

void showSleepTimerSheet(BuildContext context, PlayerController ctrl) {
  showModalBottomSheet(
    context: context,
    builder: (ctx) {
      int fadeSeconds = SettingsService.instance.sleepFadeSeconds;
      return StatefulBuilder(
        builder: (ctx, setState) {
          final fade = Duration(seconds: fadeSeconds);
          return Container(
            padding: const EdgeInsets.all(PlayaSpacing.kSp * 2),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Sleep Timer',
                    style: TextStyle(
                      fontSize: PlayaTypography.lg,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: PlayaSpacing.kSp),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Fade out',
                          style: TextStyle(
                            color: PlayaColors.onSurfaceVariant,
                            fontSize: PlayaTypography.sm,
                          ),
                        ),
                      ),
                      DropdownButton<int>(
                        value: fadeSeconds,
                        dropdownColor: PlayaColors.surface,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Off')),
                          DropdownMenuItem(value: 5, child: Text('5s')),
                          DropdownMenuItem(value: 10, child: Text('10s')),
                          DropdownMenuItem(value: 20, child: Text('20s')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => fadeSeconds = v);
                          SettingsService.instance.setSleepFadeSeconds(v);
                        },
                      ),
                      const SizedBox(width: PlayaSpacing.kSp),
                      TextButton(
                        onPressed: fadeSeconds == 0
                            ? null
                            : () async {
                                await ctrl.previewFadeToSilence(fade);
                              },
                        child: const Text('Preview'),
                      ),
                    ],
                  ),
                  const SizedBox(height: PlayaSpacing.kSp),
                  ListTile(
                    leading: const Icon(PhosphorIconsRegular.timer),
                    title: const Text('15 Minutes'),
                    onTap: () {
                      ctrl.setSleepTimer(15, fadeOut: fade);
                      Navigator.pop(ctx);
                      showToast(context, 'Sleep timer: 15 minutes');
                    },
                  ),
                  ListTile(
                    leading: const Icon(PhosphorIconsRegular.timer),
                    title: const Text('30 Minutes'),
                    onTap: () {
                      ctrl.setSleepTimer(30, fadeOut: fade);
                      Navigator.pop(ctx);
                      showToast(context, 'Sleep timer: 30 minutes');
                    },
                  ),
                  ListTile(
                    leading: const Icon(PhosphorIconsRegular.timer),
                    title: const Text('60 Minutes'),
                    onTap: () {
                      ctrl.setSleepTimer(60, fadeOut: fade);
                      Navigator.pop(ctx);
                      showToast(context, 'Sleep timer: 60 minutes');
                    },
                  ),
                  const Divider(color: Colors.white10),
                  ListTile(
                    leading: const Icon(PhosphorIconsRegular.musicNotes),
                    title: const Text('End of Track'),
                    onTap: () {
                      ctrl.setSleepTimerEndOfTrack(fadeOut: fade);
                      Navigator.pop(ctx);
                      showToast(context, 'Sleep timer: end of track');
                    },
                  ),
                  ListTile(
                    leading: const Icon(PhosphorIconsRegular.disc),
                    title: const Text('End of Album'),
                    onTap: () {
                      ctrl.setSleepTimerEndOfAlbum(fadeOut: fade);
                      Navigator.pop(ctx);
                      showToast(context, 'Sleep timer: end of album');
                    },
                  ),
                  ListTile(
                    leading: const Icon(PhosphorIconsRegular.playlist),
                    title: const Text('End of Playlist'),
                    onTap: () {
                      ctrl.setSleepTimerEndOfPlaylist(fadeOut: fade);
                      Navigator.pop(ctx);
                      showToast(context, 'Sleep timer: end of playlist');
                    },
                  ),
                  ListTile(
                    leading: const Icon(PhosphorIconsRegular.queue),
                    title: const Text('End of Queue'),
                    onTap: () {
                      ctrl.setSleepTimerEndOfQueue(fadeOut: fade);
                      Navigator.pop(ctx);
                      showToast(context, 'Sleep timer: end of queue');
                    },
                  ),
                  ListTile(
                    leading: const Icon(PhosphorIconsRegular.xCircle),
                    title: const Text('Turn Off Timer'),
                    onTap: () {
                      ctrl.cancelSleepTimer();
                      Navigator.pop(ctx);
                      showToast(context, 'Sleep timer off');
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}