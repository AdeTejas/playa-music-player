import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/player_controller.dart';
import '../services/settings_service.dart';
import '../services/database_service.dart';
import '../models/song_metadata.dart';
import '../ui/tokens.dart';
import '../ui/glass_panel.dart';
import '../ui/turntable_widget.dart';
import '../ui/waveform_widget.dart';
import '../ui/lyrics_sheet.dart';
import '../utils/ui_utils.dart';
import '../widgets/player_provider.dart';

class PlayerScreen extends StatefulWidget {
  final bool isVisible;
  const PlayerScreen({this.isVisible = true, super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  @override
  void initState() {
    super.initState();
    _updateWakelock();
    SettingsService.instance.addListener(_updateWakelock);
  }

  @override
  void dispose() {
    SettingsService.instance.removeListener(_updateWakelock);
    WakelockPlus.disable();
    super.dispose();
  }

  void _updateWakelock() {
    if (SettingsService.instance.keepScreenOn) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = PlayerProvider.of(context);
    final p = ctrl.player;

    final topInset = MediaQuery.paddingOf(context).top;

    return Stack(
      children: [
        SafeArea(
          top: false,
          bottom: false,
          child: AnimatedBuilder(
            animation: SettingsService.instance,
            builder: (context, _) {
              return StreamBuilder<SequenceState?>(
                stream: p.sequenceStateStream,
                builder: (context, _) {
                  final tag = ctrl.currentMediaItem;
                  return StreamBuilder<PlayerState>(
                    stream: p.playerStateStream,
                    builder: (context, _) {
                      return OrientationBuilder(
                        builder: (context, orientation) {
                          if (orientation == Orientation.landscape) {
                            // Landscape Layout
                            return Row(
                              children: [
                                // Left: Turntable
                                Expanded(
                                  flex: 5,
                                  child: Center(
                                    child: AspectRatio(
                                      aspectRatio: 1.0,
                                      child: RepaintBoundary(
                                        child: TurntableDeck(
                                          ctrl: ctrl,
                                          item: tag,
                                          isVisible: widget.isVisible,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                // Right: Controls
                                Expanded(
                                  flex: 4,
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.all(kSp),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        // Track Info
                                        Text(
                                          tag?.title ?? '—',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          tag?.artist ?? 'Unknown',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: kColorOn2,
                                            fontSize: 16,
                                          ),
                                        ),
                                        if (tag != null)
                                          _SonicDnaBadge(songId: tag.id),
                                        const SizedBox(height: kSp * 2),

                                        // Waveform
                                        SizedBox(
                                          height: 80,
                                          child:
                                              (SettingsService
                                                          .instance
                                                          .showWaveforms &&
                                                      tag != null &&
                                                      tag.extras?['path'] !=
                                                          null)
                                                  ? WaveformWidget(
                                                    path:
                                                        tag.extras!['path']
                                                            as String,
                                                    player: p,
                                                    playedColor: Color(
                                                      SettingsService
                                                          .instance
                                                          .accentColor,
                                                    ),
                                                  )
                                                  : const SizedBox(),
                                        ),
                                        const SizedBox(height: kSp * 2),

                                        // Transport
                                        _TransportBar(ctrl: ctrl),
                                        const SizedBox(height: kSp),
                                        _SecondaryControls(ctrl: ctrl),
                                        const SizedBox(height: kSp),
                                        // Favorite Button
                                        ValueListenableBuilder<List<String>>(
                                          valueListenable:
                                              ctrl.favoritesNotifier,
                                          builder: (context, favorites, _) {
                                            final isFav =
                                                tag != null &&
                                                favorites.contains(tag.id);
                                            return IconButton(
                                              onPressed:
                                                  tag == null
                                                      ? null
                                                      : () =>
                                                          ctrl.toggleFavorite(
                                                            tag.id,
                                                          ),
                                              icon: Icon(
                                                isFav
                                                    ? PhosphorIconsFill.heart
                                                    : PhosphorIconsRegular
                                                        .heart,
                                                color:
                                                    isFav
                                                        ? Colors.redAccent
                                                        : kColorOn2,
                                                size: 28,
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          } else {
                            // Portrait Layout
                            return LayoutBuilder(
                              builder: (context, constraints) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: kSp * 1.5,
                                  ),
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      const SizedBox(height: kSp),
                                      Expanded(
                                        child: Center(
                                          child: AspectRatio(
                                            aspectRatio: 1.0,
                                            child: RepaintBoundary(
                                              child: TurntableDeck(
                                                ctrl: ctrl,
                                                item: tag,
                                                isVisible: widget.isVisible,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: kSp),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const SizedBox(width: 48), // Balance
                                          Expanded(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  tag?.title ?? '—',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.w700,
                                                    letterSpacing: -0.5,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  tag?.artist ?? 'Unknown',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    color: kColorOn2,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                if (tag != null)
                                                  _SonicDnaBadge(
                                                    songId: tag.id,
                                                  ),
                                              ],
                                            ),
                                          ),
                                          ValueListenableBuilder<List<String>>(
                                            valueListenable:
                                                ctrl.favoritesNotifier,
                                            builder: (context, favorites, _) {
                                              final isFav =
                                                  tag != null &&
                                                  favorites.contains(tag.id);
                                              return SizedBox(
                                                width: 48,
                                                child: IconButton(
                                                  onPressed:
                                                      tag == null
                                                          ? null
                                                          : () => ctrl
                                                              .toggleFavorite(
                                                                tag.id,
                                                              ),
                                                  icon: Icon(
                                                    isFav
                                                        ? PhosphorIconsFill
                                                            .heart
                                                        : PhosphorIconsRegular
                                                            .heart,
                                                    color:
                                                        isFav
                                                            ? Colors.redAccent
                                                            : kColorOn2,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: kSp),
                                      SizedBox(
                                        height: 60,
                                        child:
                                            (SettingsService
                                                        .instance
                                                        .showWaveforms &&
                                                    tag != null &&
                                                    tag.extras?['path'] != null)
                                                ? WaveformWidget(
                                                  path:
                                                      tag.extras!['path']
                                                          as String,
                                                  player: p,
                                                  playedColor: Color(
                                                    SettingsService
                                                        .instance
                                                        .accentColor,
                                                  ),
                                                )
                                                : const SizedBox(),
                                      ),
                                      const SizedBox(height: kSp),
                                      _TransportBar(ctrl: ctrl),
                                      const SizedBox(height: kSp),
                                      _SecondaryControls(ctrl: ctrl),
                                      const SizedBox(height: kSp),
                                    ],
                                  ),
                                );
                              },
                            );
                          }
                        },
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: IgnorePointer(
            child: Container(
              height: topInset + kSp * 3.0,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    kColorBg.withValues(alpha: 0.98),
                    kColorBg.withValues(alpha: 0.10),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TransportBar extends StatelessWidget {
  final PlayerController ctrl;
  const _TransportBar({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final p = ctrl.player;
    final accent = Theme.of(context).colorScheme.primary;

    final controls = <Widget>[
      _IconBtn(
        icon: PhosphorIconsBold.skipBack,
        onTap: () async {
          if (!ctrl.isReady) return;
          if (p.hasPrevious) {
            await p.seekToPrevious();
          } else {
            final len = p.sequenceState.sequence.length;
            if (len > 0) {
              await p.seek(Duration.zero, index: len - 1);
            }
          }
          HapticFeedback.selectionClick();
        },
      ),
      _IconBtn(
        icon: PhosphorIconsBold.arrowCounterClockwise,
        onTap: () async {
          if (!ctrl.isReady) return;
          final pos = p.position;
          final newPos = pos - const Duration(seconds: 10);
          await p.seek(newPos.isNegative ? Duration.zero : newPos);
          HapticFeedback.selectionClick();
        },
      ),
      Semantics(
        label: 'Play or pause music',
        button: true,
        child: ElevatedButton(
          onPressed: () async {
            if (!ctrl.isReady) return;
            if (p.playing) {
              await p.pause();
            } else {
              await p.play();
            }
            HapticFeedback.selectionClick();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(14),
            elevation: 6,
            shadowColor: Colors.black54,
          ),
          child: StreamBuilder<bool>(
            stream: p.playingStream,
            initialData: p.playing,
            builder: (_, snap) {
              final playing = snap.data ?? false;
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: PhosphorIcon(
                  playing ? PhosphorIconsFill.pause : PhosphorIconsFill.play,
                  key: ValueKey(playing),
                  size: 30,
                  color: Colors.white,
                ),
              );
            },
          ),
        ),
      ),
      _IconBtn(
        icon: PhosphorIconsBold.arrowClockwise,
        onTap: () async {
          if (!ctrl.isReady) return;
          await p.seek(p.position + const Duration(seconds: 10));
          HapticFeedback.selectionClick();
        },
      ),
      _IconBtn(
        icon: PhosphorIconsBold.skipForward,
        onTap: () async {
          if (!ctrl.isReady) return;
          if (p.hasNext) {
            await p.seekToNext();
          } else {
            final len = p.sequenceState.sequence.length;
            if (len > 0) {
              await p.seek(Duration.zero, index: 0);
            }
          }
          HapticFeedback.selectionClick();
        },
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 260) {
          return Wrap(
            spacing: kSp,
            runSpacing: kSp * 0.6,
            alignment: WrapAlignment.center,
            children: controls,
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: controls,
        );
      },
    );
  }
}

class _SecondaryControls extends StatelessWidget {
  final PlayerController ctrl;
  const _SecondaryControls({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final p = ctrl.player;

    return Wrap(
      spacing: kSp,
      runSpacing: kSp,
      alignment: WrapAlignment.center,
      children: [
        StreamBuilder<bool>(
          stream: p.shuffleModeEnabledStream,
          initialData: p.shuffleModeEnabled,
          builder: (_, snap) {
            final shuf = snap.data ?? false;
            return _ChipIcon(
              icon:
                  shuf ? PhosphorIconsFill.shuffle : PhosphorIconsLight.shuffle,
              label: 'Shuffle',
              active: shuf,
              onTap: () async {
                if (!ctrl.isReady) return;
                await p.setShuffleModeEnabled(!shuf);
                if (!shuf) await p.shuffle();
                HapticFeedback.selectionClick();
              },
            );
          },
        ),
        StreamBuilder<LoopMode>(
          stream: p.loopModeStream,
          initialData: p.loopMode,
          builder: (_, snap) {
            final lm = snap.data ?? LoopMode.off;
            final next =
                lm == LoopMode.off
                    ? LoopMode.one
                    : (lm == LoopMode.one ? LoopMode.all : LoopMode.off);
            final icon =
                lm == LoopMode.one
                    ? PhosphorIconsBold.numberCircleOne
                    : PhosphorIconsBold.arrowsClockwise;
            final active = lm != LoopMode.off;
            return _ChipIcon(
              icon: icon,
              label:
                  lm == LoopMode.all
                      ? 'Repeat All'
                      : (lm == LoopMode.one ? 'Repeat One' : 'Repeat'),
              active: active,
              onTap: () {
                if (!ctrl.isReady) return;
                p.setLoopMode(next);
                HapticFeedback.selectionClick();
              },
            );
          },
        ),
        _ChipIcon(
          icon: PhosphorIconsBold.brain,
          label: 'Neural Mix',
          active: false,
          onTap: () async {
            if (!ctrl.isReady) return;
            showToast(context, 'Generating Neural Mix...');
            await ctrl.smartShuffle();
            if (!context.mounted) return;
            showToast(context, 'Mix Ready');
            HapticFeedback.mediumImpact();
          },
        ),
        _ChipIcon(
          icon: PhosphorIconsBold.gauge,
          label: 'Speed',
          active: false,
          onTap: () async {
            if (!ctrl.isReady) return;
            final current = p.speed;
            final picked = await showModalBottomSheet<double>(
              context: context,
              builder: (_) => _SpeedSheet(current: current),
            );
            if (picked != null && picked > 0) {
              try {
                await p.setSpeed(picked);
                HapticFeedback.selectionClick();
              } catch (_) {
                if (context.mounted) {
                  showToast(
                    context,
                    'Speed not supported on this track/device',
                  );
                }
              }
            }
          },
        ),
        _ChipIcon(
          icon: PhosphorIconsBold.bookmarkSimple,
          label: 'Bookmark',
          active: false,
          onTap: () {
            if (!ctrl.isReady) return;

            // Show dialog to annotate immediately
            final controller = TextEditingController();
            showDialog(
              context: context,
              builder: (ctx) {
                final a = Theme.of(ctx).colorScheme.primary;
                return AlertDialog(
                  backgroundColor: kColorSurface,
                  title: const Text('Add Chapter'),
                  content: TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Note (optional)...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: kColorOn2),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: a),
                      ),
                    ),
                    style: const TextStyle(color: kColorOn),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: kColorOn2),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        ctrl.addBookmark(note: controller.text);
                        Navigator.pop(ctx);
                        showToast(context, 'Chapter added');
                        HapticFeedback.selectionClick();
                      },
                      child: Text('Add', style: TextStyle(color: a)),
                    ),
                  ],
                );
              },
            );
          },
        ),
        _ChipIcon(
          icon: PhosphorIconsBold.microphoneStage,
          label: 'Lyrics',
          active: false,
          onTap: () {
            if (!ctrl.isReady) return;
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => LyricsSheet(ctrl: ctrl),
            );
          },
        ),
      ],
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: PhosphorIcon(icon, size: 26, color: kColorOn),
      onPressed: onTap,
    );
  }
}

class _ChipIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _ChipIcon({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? accent.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? accent : Colors.white10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: active ? accent : kColorOn2),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: active ? accent : kColorOn2,
                fontSize: 12,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeedSheet extends StatelessWidget {
  final double current;
  const _SpeedSheet({required this.current});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      color: kColorSurface,
      padding: const EdgeInsets.all(kSp * 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Playback Speed',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: kSp),
          Wrap(
            spacing: kSp,
            children:
                [0.5, 0.8, 1.0, 1.2, 1.5, 2.0].map((speed) {
                  final selected = (speed - current).abs() < 0.01;
                  return ChoiceChip(
                    label: Text('${speed}x'),
                    selected: selected,
                    onSelected: (_) => Navigator.pop(context, speed),
                    selectedColor: accent,
                    backgroundColor: kColorCard,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : kColorOn,
                    ),
                  );
                }).toList(),
          ),
        ],
      ),
    );
  }
}

class QueueSheet extends StatefulWidget {
  final PlayerController ctrl;
  final ScrollController scrollController;

  const QueueSheet({
    super.key,
    required this.ctrl,
    required this.scrollController,
  });

  @override
  State<QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends State<QueueSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GlassPanel(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      borderColor: Colors.white.withValues(alpha: 0.14),
      backgroundColor: kColorGlassBlackTint,
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            indicatorColor: accent,
            labelColor: accent,
            unselectedLabelColor: kColorOn2,
            tabs: const [Tab(text: 'Queue'), Tab(text: 'Library')],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildQueueList(), _buildLibraryList()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueList() {
    final p = widget.ctrl.player;
    return StreamBuilder<SequenceState?>(
      stream: p.sequenceStateStream,
      builder: (context, snapshot) {
        final accent = Theme.of(context).colorScheme.primary;
        final state = snapshot.data;
        final sequence = state?.sequence ?? [];
        return ReorderableListView.builder(
          scrollController: widget.scrollController,
          itemCount: sequence.length,
          onReorder: (oldIndex, newIndex) {
            if (oldIndex < newIndex) newIndex--;
            showToast(context, 'Reordering not implemented in this demo');
          },
          itemBuilder: (context, index) {
            final item = sequence[index];
            final isPlaying = index == state?.currentIndex;
            return ListTile(
              key: ValueKey(item),
              title: Text(
                item.tag.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isPlaying ? accent : kColorOn,
                  fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              subtitle: Text(
                item.tag.artist ?? 'Unknown',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: kColorOn2, fontSize: 12),
              ),
              trailing:
                  isPlaying
                      ? Icon(
                        PhosphorIconsFill.speakerHigh,
                        color: accent,
                        size: 16,
                      )
                      : null,
              onTap: () {
                p.seek(Duration.zero, index: index);
                Navigator.pop(context);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildLibraryList() {
    final songs =
        widget.ctrl.librarySongs.where((s) {
          if (_searchQuery.isEmpty) return true;
          return s.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              (s.artist?.toLowerCase().contains(_searchQuery.toLowerCase()) ??
                  false);
        }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search Library...',
              prefixIcon: const Icon(
                PhosphorIconsRegular.magnifyingGlass,
                color: kColorOn2,
              ),
              filled: true,
              fillColor: Colors.white10,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              hintStyle: const TextStyle(color: kColorOn2),
            ),
            style: const TextStyle(color: kColorOn),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        Expanded(
          child: ListView.builder(
            // Not attaching scrollController here to avoid conflict,
            // but this means this list won't drive the sheet drag.
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final s = songs[index];
              return ListTile(
                title: Text(
                  s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kColorOn),
                ),
                subtitle: Text(
                  s.artist ?? '<unknown>',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kColorOn2),
                ),
                trailing: IconButton(
                  icon: const Icon(
                    PhosphorIconsRegular.plusCircle,
                    color: kColorOn2,
                  ),
                  onPressed: () {
                    widget.ctrl.addToQueue(s);
                    showToast(context, 'Added to Queue');
                  },
                ),
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: kColorSurface,
                    builder:
                        (ctx) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(
                                PhosphorIconsRegular.play,
                                color: kColorOn,
                              ),
                              title: const Text(
                                'Play Now',
                                style: TextStyle(color: kColorOn),
                              ),
                              onTap: () {
                                widget.ctrl.replaceQueue([s]);
                                Navigator.pop(ctx);
                                Navigator.pop(context);
                              },
                            ),
                            ListTile(
                              leading: const Icon(
                                PhosphorIconsRegular.queue,
                                color: kColorOn,
                              ),
                              title: const Text(
                                'Play Next',
                                style: TextStyle(color: kColorOn),
                              ),
                              onTap: () {
                                widget.ctrl.insertNext(s);
                                Navigator.pop(ctx);
                                showToast(context, 'Playing Next');
                              },
                            ),
                            ListTile(
                              leading: const Icon(
                                PhosphorIconsRegular.plus,
                                color: kColorOn,
                              ),
                              title: const Text(
                                'Add to Queue',
                                style: TextStyle(color: kColorOn),
                              ),
                              onTap: () {
                                widget.ctrl.addToQueue(s);
                                Navigator.pop(ctx);
                                showToast(context, 'Added to Queue');
                              },
                            ),
                          ],
                        ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class BookmarksSheet extends StatelessWidget {
  final PlayerController ctrl;
  const BookmarksSheet({super.key, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final bookmarks = ctrl.bookmarks;
    final accent = Theme.of(context).colorScheme.primary;
    return GlassPanel(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      borderColor: Colors.white.withValues(alpha: 0.14),
      backgroundColor: kColorGlassBlackTint,
      child: SizedBox(
        height: 400,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Chapters / Bookmarks',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            if (bookmarks.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'No chapters added',
                    style: TextStyle(color: kColorOn2),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: bookmarks.length,
                  itemBuilder: (context, index) {
                    final b = bookmarks[index];
                    final pos = Duration(milliseconds: b['pos'] as int);
                    return ListTile(
                      leading: Text(
                        _fmt(pos),
                        style: TextStyle(
                          color: accent,
                          fontFamily: 'monospace',
                        ),
                      ),
                      title: Text(b['note'] as String),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () {
                          ctrl.removeBookmark(index);
                          Navigator.pop(context);
                          showToast(context, 'Chapter removed');
                        },
                      ),
                      onTap: () {
                        ctrl.player.seek(pos);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _fmt(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

class _SonicDnaBadge extends StatelessWidget {
  final String songId;
  const _SonicDnaBadge({required this.songId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SongMetadata?>(
      future: DatabaseService.instance.getSongMetadata(songId),
      builder: (context, snapshot) {
        final meta = snapshot.data;
        if (meta == null || meta.bpm == null) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF1B1F26),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                PhosphorIconsBold.waveform,
                size: 14,
                color: Color(0xFF8D5524),
              ),
              const SizedBox(width: 6),
              Text(
                '${meta.bpm!.toInt()} BPM',
                style: const TextStyle(
                  color: Color(0xFFE8DCCA),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (meta.key != null) ...[
                const SizedBox(width: 8),
                Container(width: 1, height: 10, color: Colors.white24),
                const SizedBox(width: 8),
                Text(
                  meta.key!,
                  style: const TextStyle(
                    color: Color(0xFFA68B6C),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
