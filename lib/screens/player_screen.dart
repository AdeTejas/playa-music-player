// ignore_for_file: prefer_const_constructors

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'dart:math' as math;

import '../services/album_art_accent_service.dart';
import '../services/player_controller.dart';
import '../services/settings_service.dart';
import '../services/database_service.dart';
import '../models/song_metadata.dart';
import '../design/design_system.dart';
import '../ui/turntable_widget.dart';
import '../ui/waveform_widget.dart';
import '../ui/lyrics_sheet.dart';
import 'screensaver_screen.dart';
import '../utils/content_mode.dart';
import '../utils/ui_utils.dart';
import '../widgets/audiobook_controls.dart';
import '../widgets/bookmarks_sheet.dart';
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
                  if (tag != null) {
                    AlbumArtAccentService.instance.prefetch(tag);
                  }
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
                                  flex: 6,
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
                                  flex: 3,
                                  child: SingleChildScrollView(
                                    padding: const EdgeInsets.all(PlayaSpacing.kSp),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        // Track Info
                                        _TrackInfoPanel(item: tag, playerCtrl: ctrl),
                                        const SizedBox(height: PlayaSpacing.kSp * 2),
                                        _WaveformSection(
                                          item: tag,
                                          player: p,
                                          height: 80,
                                        ),
                                        const SizedBox(height: PlayaSpacing.kSp * 2),

                                        // Transport
                                        _PlayerControlsSection(ctrl: ctrl),
                                        const SizedBox(height: PlayaSpacing.kSp),
                                        // Favorite Button
                                        ValueListenableBuilder<List<String>>(
                                          valueListenable:
                                              ctrl.favoritesNotifier,
                                          builder: (context, favorites, _) {
                                             final isFav =
                                                 tag != null &&
                                                 favorites.contains(tag.id);
                                             final accent =
                                                 Theme.of(context)
                                                     .colorScheme
                                                     .primary;
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
                                                         ? accent
                                                        : PlayaColors.onSurfaceVariant,
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
                                    horizontal: PlayaSpacing.kSp * 1.5,
                                  ),
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: PlayaSpacing.kSp),
                                      Expanded(
                                        flex: 7,
                                        child: Center(
                                          child: AspectRatio(
                                            aspectRatio: 1.0,
                                            child: RepaintBoundary(
                                            child: Stack(
                                              children: [
                                                Positioned.fill(
                                                  child: TurntableDeck(
                                                    ctrl: ctrl,
                                                    item: tag,
                                                    isVisible: widget.isVisible,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: PlayaSpacing.kSp),
                                      _TrackInfoPanel(item: tag, playerCtrl: ctrl),
                                      const SizedBox(height: PlayaSpacing.kSp * 0.75),
                                      _WaveformSection(
                                        item: tag,
                                        player: p,
                                        height: 56,
                                      ),
                                      const SizedBox(height: PlayaSpacing.kSp * 0.75),
                                      _PlayerControlsSection(ctrl: ctrl),
                                      const SizedBox(height: PlayaSpacing.kSp),
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
      ],
    );
  }
}

class _PlayerControlsSection extends StatelessWidget {
  final PlayerController ctrl;
  const _PlayerControlsSection({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final mode = ctrl.currentContentMode;
    final isAudiobook = mode == ContentMode.audiobook;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TransportBar(ctrl: ctrl),
        SizedBox(height: isAudiobook ? PlayaSpacing.kSp : PlayaSpacing.kSp * 0.75),
        if (isAudiobook) ...[
          AudiobookQuickBar(ctrl: ctrl),
          const SizedBox(height: PlayaSpacing.kSp * 0.75),
          MusicToolsExpansion(
            ctrl: ctrl,
            child: _SecondaryControls(
              ctrl: ctrl,
              visibleChips: const {
                'shuffle',
                'repeat',
                'neural_mix',
                'lyrics',
                'screensaver',
              },
            ),
          ),
        ] else
          _SecondaryControls(ctrl: ctrl),
      ],
    );
  }
}

class _TransportBar extends StatelessWidget {
  final PlayerController ctrl;
  const _TransportBar({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SettingsService.instance,
      builder: (context, _) => _buildBar(context),
    );
  }

  Widget _buildBar(BuildContext context) {
    final p = ctrl.player;
    final accent = Theme.of(context).colorScheme.primary;
    final skipSec = ctrl.skipIntervalSeconds;
    final isAudiobook = ctrl.currentContentMode == ContentMode.audiobook;

    final controls = <Widget>[
      _IconBtn(
        icon: PhosphorIconsBold.skipBack,
        tooltip: 'Previous track',
        onTap: () async {
          if (!ctrl.isReady) return;
          if (p.hasPrevious) {
            await p.seekToPrevious();
          } else {
            final len = p.sequenceState?.sequence.length ?? 0;
            if (len > 0) {
              await p.seek(Duration.zero, index: len - 1);
            }
          }
          HapticFeedback.selectionClick();
        },
      ),
      _IconBtn(
        icon: PhosphorIconsBold.arrowCounterClockwise,
        tooltip: 'Back $skipSec seconds',
        label: isAudiobook ? '−${skipSec}s' : null,
        onTap: () async {
          if (!ctrl.isReady) return;
          await ctrl.skipBackward();
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
              await ctrl.pause();
            } else {
              await ctrl.play();
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
        tooltip: 'Forward $skipSec seconds',
        label: isAudiobook ? '+${skipSec}s' : null,
        onTap: () async {
          if (!ctrl.isReady) return;
          await ctrl.skipForward();
          HapticFeedback.selectionClick();
        },
      ),
      _IconBtn(
        icon: PhosphorIconsBold.skipForward,
        tooltip: 'Next track',
        onTap: () async {
          if (!ctrl.isReady) return;
          if (p.hasNext) {
            await p.seekToNext();
          } else {
            final len = p.sequenceState?.sequence.length ?? 0;
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
        if (constraints.maxWidth < 350) {
          return Wrap(
            spacing: PlayaSpacing.kSp * 1.5,
            runSpacing: PlayaSpacing.kSp,
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
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

class _SecondaryControls extends StatefulWidget {
  final PlayerController ctrl;
  final Set<String>? visibleChips;
  const _SecondaryControls({required this.ctrl, this.visibleChips});

  @override
  State<_SecondaryControls> createState() => _SecondaryControlsState();
}

class _SecondaryControlsState extends State<_SecondaryControls> {
  late List<String> _chipOrder;
  bool _isReordering = false;
  int? _selectedChipIndex;

  @override
  void initState() {
    super.initState();
    _chipOrder = List.from(SettingsService.instance.controlChipOrder);
  }

  void _reorderChips(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final item = _chipOrder.removeAt(oldIndex);
      _chipOrder.insert(newIndex, item);
    });
    HapticFeedback.selectionClick();
  }

  Widget _buildChip(String chipId, BuildContext context, int index) {
    final p = widget.ctrl.player;

    switch (chipId) {
      case 'shuffle':
        return StreamBuilder<bool>(
          stream: p.shuffleModeEnabledStream,
          initialData: p.shuffleModeEnabled,
          builder: (_, snap) {
            final shuf = snap.data ?? false;
            return _ReorderableChipIcon(
              key: const ValueKey('shuffle'),
              icon: shuf ? PhosphorIconsFill.shuffle : PhosphorIconsLight.shuffle,
              label: 'Shuffle',
              active: shuf,
              isReordering: _isReordering,
              isSelected: _selectedChipIndex == index,
              onTap: () async {
                if (_isReordering) {
                  // In reorder mode, tapping selects this chip for moving
                  setState(() => _selectedChipIndex = index);
                  HapticFeedback.selectionClick();
                  return;
                }
                if (!widget.ctrl.isReady) return;
                await p.setShuffleModeEnabled(!shuf);
                if (!shuf) await p.shuffle();
                HapticFeedback.selectionClick();
              },
              onLongPress: _isReordering ? () {
                // In reorder mode, long-press moves selected chip here
                if (_selectedChipIndex != null && _selectedChipIndex != index) {
                  _reorderChips(_selectedChipIndex!, index);
                  setState(() => _selectedChipIndex = null);
                }
              } : null,
            );
          },
        );

      case 'repeat':
        return StreamBuilder<LoopMode>(
          stream: p.loopModeStream,
          initialData: p.loopMode,
          builder: (_, snap) {
            final lm = snap.data ?? LoopMode.off;
            final next = lm == LoopMode.off
                ? LoopMode.one
                : (lm == LoopMode.one ? LoopMode.all : LoopMode.off);
            final icon = lm == LoopMode.one
                ? PhosphorIconsBold.numberCircleOne
                : PhosphorIconsBold.arrowsClockwise;
            final active = lm != LoopMode.off;
            return _ReorderableChipIcon(
              key: ValueKey('repeat'),
              icon: icon,
              label: lm == LoopMode.all
                  ? 'Repeat All'
                  : (lm == LoopMode.one ? 'Repeat One' : 'Repeat'),
              active: active,
              isReordering: _isReordering,
              isSelected: _selectedChipIndex == index,
              onTap: () {
                if (_isReordering) {
                  setState(() => _selectedChipIndex = index);
                  HapticFeedback.selectionClick();
                  return;
                }
                if (!widget.ctrl.isReady) return;
                p.setLoopMode(next);
                HapticFeedback.selectionClick();
              },
              onLongPress: _isReordering ? () {
                if (_selectedChipIndex != null && _selectedChipIndex != index) {
                  _reorderChips(_selectedChipIndex!, index);
                  setState(() => _selectedChipIndex = null);
                }
              } : null,
            );
          },
        );

      case 'neural_mix':
        return _ReorderableChipIcon(
          key: ValueKey('neural_mix'),
          icon: PhosphorIconsBold.brain,
          label: 'Neural Mix',
          active: false,
          isReordering: _isReordering,
          isSelected: _selectedChipIndex == index,
          onTap: () async {
            if (_isReordering) {
              setState(() => _selectedChipIndex = index);
              HapticFeedback.selectionClick();
              return;
            }
            if (!widget.ctrl.isReady) return;
            showToast(context, 'Generating Neural Mix...');
            await widget.ctrl.smartShuffle();
            if (!context.mounted) return;
            showToast(context, 'Mix Ready');
            HapticFeedback.mediumImpact();
          },
          onLongPress: _isReordering ? () {
            if (_selectedChipIndex != null && _selectedChipIndex != index) {
              _reorderChips(_selectedChipIndex!, index);
              setState(() => _selectedChipIndex = null);
            }
          } : null,
        );

      case 'speed':
        return _ReorderableChipIcon(
          key: ValueKey('speed'),
          icon: PhosphorIconsBold.gauge,
          label: 'Speed',
          active: false,
          isReordering: _isReordering,
          isSelected: _selectedChipIndex == index,
          onTap: () async {
            if (_isReordering) {
              setState(() => _selectedChipIndex = index);
              HapticFeedback.selectionClick();
              return;
            }
            if (!widget.ctrl.isReady) return;
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
          onLongPress: _isReordering ? () {
            if (_selectedChipIndex != null && _selectedChipIndex != index) {
              _reorderChips(_selectedChipIndex!, index);
              setState(() => _selectedChipIndex = null);
            }
          } : null,
        );

      case 'screensaver':
        return _ReorderableChipIcon(
          key: ValueKey('screensaver'),
          icon: Icons.slideshow,
          label: 'Screensaver',
          active: false,
          isReordering: _isReordering,
          isSelected: _selectedChipIndex == index,
          onTap: () {
            if (_isReordering) {
              setState(() => _selectedChipIndex = index);
              HapticFeedback.selectionClick();
              return;
            }
            HapticFeedback.selectionClick();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ScreensaverScreen(),
              ),
            );
          },
          onLongPress: () {
            if (_isReordering) {
              if (_selectedChipIndex != null && _selectedChipIndex != index) {
                _reorderChips(_selectedChipIndex!, index);
                setState(() => _selectedChipIndex = null);
              }
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ScreensaverScreen(),
              ),
            );
          },
        );

      case 'bookmark':
        return _ReorderableChipIcon(
          key: ValueKey('bookmark'),
          icon: PhosphorIconsBold.bookmarkSimple,
          label: 'Bookmark',
          active: false,
          isReordering: _isReordering,
          isSelected: _selectedChipIndex == index,
          onTap: () {
            if (_isReordering) {
              setState(() => _selectedChipIndex = index);
              HapticFeedback.selectionClick();
              return;
            }
            if (!widget.ctrl.isReady) return;

            final controller = TextEditingController();
            showDialog(
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
                        final ok = await widget.ctrl.addBookmark(
                          note: controller.text,
                        );
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        showToast(
                          context,
                          ok ? 'Bookmark saved' : 'Could not save bookmark',
                        );
                        HapticFeedback.selectionClick();
                      },
                      child: Text('Add', style: TextStyle(color: a)),
                    ),
                  ],
                );
              },
            );
          },
          onLongPress: () async {
            if (_isReordering) {
              if (_selectedChipIndex != null && _selectedChipIndex != index) {
                _reorderChips(_selectedChipIndex!, index);
                setState(() => _selectedChipIndex = null);
              }
              return;
            }
            if (!widget.ctrl.isReady) return;
            await widget.ctrl.reloadBookmarks();
            if (!context.mounted) return;
            showModalBottomSheet(
              context: context,
              backgroundColor: Colors.transparent,
              builder: (_) => BookmarksSheet(ctrl: widget.ctrl),
            );
          },
        );

      case 'lyrics':
        return _ReorderableChipIcon(
          key: ValueKey('lyrics'),
          icon: PhosphorIconsBold.microphoneStage,
          label: 'Lyrics',
          active: false,
          isReordering: _isReordering,
          isSelected: _selectedChipIndex == index,
          onTap: () {
            if (_isReordering) {
              setState(() => _selectedChipIndex = index);
              HapticFeedback.selectionClick();
              return;
            }
            if (!widget.ctrl.isReady) return;
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => LyricsSheet(ctrl: widget.ctrl),
            );
          },
          onLongPress: _isReordering ? () {
            if (_selectedChipIndex != null && _selectedChipIndex != index) {
              _reorderChips(_selectedChipIndex!, index);
              setState(() => _selectedChipIndex = null);
            }
          } : null,
        );

      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: GestureDetector(
            onLongPress: () {
              setState(() {
                _isReordering = !_isReordering;
                if (!_isReordering) {
                  _selectedChipIndex = null;
                }
              });
              HapticFeedback.mediumImpact();
              if (_isReordering) {
                showToast(context, 'Tap to select, long-press to move');
              } else {
                SettingsService.instance.setControlChipOrder(_chipOrder);
                showToast(context, 'Order saved');
              }
            },
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _isReordering ? Colors.blue.withValues(alpha: 0.2) : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                _isReordering ? Icons.check : Icons.reorder,
                size: 16,
                color: _isReordering ? Colors.blue : PlayaColors.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: PlayaSpacing.kSp,
          runSpacing: PlayaSpacing.kSp,
          alignment: WrapAlignment.center,
          children: _chipOrder.asMap().entries
              .where((e) => widget.visibleChips?.contains(e.value) ?? true)
              .map((entry) {
            final index = entry.key;
            final chipId = entry.value;
            return _buildChip(chipId, context, index);
          }).toList(),
        ),
      ],
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final String? label;

  const _IconBtn({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      tooltip: tooltip,
      icon: PhosphorIcon(icon, size: 26, color: PlayaColors.onSurface),
      onPressed: onTap,
    );
    if (label == null) return button;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        Text(
          label!,
          style: const TextStyle(color: PlayaColors.onSurfaceVariant, fontSize: 10),
        ),
      ],
    );
  }
}

class _TrackInfoPanel extends StatelessWidget {
  final MediaItem? item;
  final PlayerController playerCtrl;

  const _TrackInfoPanel({required this.item, required this.playerCtrl});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          item?.title ?? '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          item?.artist ?? 'Unknown',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: PlayaColors.onSurfaceVariant,
            fontSize: 13,
          ),
        ),
        if (item != null &&
            playerCtrl.currentContentMode == ContentMode.music)
          _SonicDnaBadge(songId: item!.id),
        const SizedBox(height: 4),
        ValueListenableBuilder<List<String>>(
          valueListenable: playerCtrl.favoritesNotifier,
          builder: (context, favorites, _) {
            final isFav = item != null && favorites.contains(item!.id);
            final accent = Theme.of(context).colorScheme.primary;
            return IconButton(
              onPressed: item == null
                  ? null
                  : () => playerCtrl.toggleFavorite(item!.id),
              icon: Icon(
                isFav ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
                color: isFav ? accent : PlayaColors.onSurfaceVariant,
                size: 28,
              ),
            );
          },
        ),
      ],
    );
  }
}

class _WaveformSection extends StatelessWidget {
  final MediaItem? item;
  final AudioPlayer player;
  final double height;

  const _WaveformSection({
    required this.item,
    required this.player,
    this.height = 80,
  });

  @override
  Widget build(BuildContext context) {
    if (!SettingsService.instance.showWaveforms || item == null) {
      return const SizedBox();
    }
    final path = item!.extras?['path'];
    if (path is! String || path.isEmpty) {
      return const SizedBox();
    }

    return SizedBox(
      height: height,
      child: Align(
        alignment: Alignment.center,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxW = math.min(560.0, constraints.maxWidth);
            return ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxW),
              child: SizedBox(
                height: height,
                child: WaveformWidget(
                  path: path,
                  player: player,
                  playedColor: SettingsService.instance.rawAccent,
                  item: item,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ReorderableChipIcon extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool isReordering;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  // removed unused onReorder callback (was never provided by callers)

  const _ReorderableChipIcon({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.isReordering,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<_ReorderableChipIcon> createState() => _ReorderableChipIconState();
}

class _ReorderableChipIconState extends State<_ReorderableChipIcon> {
  bool _isDragging = false;
  Offset _dragOffset = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: widget.isReordering ? null : widget.onTap,
      onLongPress: widget.isReordering ? null : widget.onLongPress,
      onLongPressStart: widget.isReordering ? (details) {
        setState(() => _isDragging = true);
        HapticFeedback.mediumImpact();
      } : null,
      onLongPressMoveUpdate: widget.isReordering ? (details) {
        setState(() => _dragOffset = details.localPosition);
      } : null,
      onLongPressEnd: widget.isReordering ? (details) {
        setState(() {
          _isDragging = false;
          _dragOffset = Offset.zero;
        });
      } : null,
      child: Transform.translate(
        offset: _isDragging ? _dragOffset : Offset.zero,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: widget.active
                ? accent.withValues(alpha: 0.2)
                : (widget.isSelected
                    ? Colors.orange.withValues(alpha: 0.3)
                    : (widget.isReordering ? Colors.blue.withValues(alpha: 0.1) : Colors.transparent)),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.active
                  ? accent
                  : (widget.isSelected
                      ? Colors.orange
                      : (widget.isReordering ? Colors.blue.withValues(alpha: 0.5) : Colors.white10)),
            ),
            boxShadow: _isDragging ? [
              BoxShadow(
                color: Colors.blue.withValues(alpha: 0.3),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ] : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isReordering) ...[
                Icon(
                  widget.isSelected ? Icons.radio_button_checked : Icons.drag_indicator,
                  size: 14,
                  color: widget.isSelected ? Colors.orange : Colors.blue,
                ),
                const SizedBox(width: 4),
              ],
              Icon(
                widget.icon,
                size: 13,
                color: widget.active ? accent : PlayaColors.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.active ? accent : PlayaColors.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: widget.active ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
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
      color: PlayaColors.surface,
      padding: const EdgeInsets.all(PlayaSpacing.kSp * 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Playback Speed',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: PlayaSpacing.kSp),
          Wrap(
            spacing: PlayaSpacing.kSp,
            children:
                [0.5, 0.8, 1.0, 1.2, 1.5, 2.0].map((speed) {
                  final selected = (speed - current).abs() < 0.01;
                  return ChoiceChip(
                    label: Text('${speed}x'),
                    selected: selected,
                    onSelected: (_) => Navigator.pop(context, speed),
                    selectedColor: accent,
                    backgroundColor: PlayaColors.card,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : PlayaColors.onSurface,
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
      backgroundColor: PlayaColors.glass,
      child: Column(
        children: [
          TabBar(
            controller: _tabController,
            indicatorColor: accent,
            labelColor: accent,
            unselectedLabelColor: PlayaColors.onSurfaceVariant,
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
          onReorder: (oldIndex, newIndex) async {
            if (oldIndex < newIndex) newIndex--;
            await widget.ctrl.reorderQueue(oldIndex, newIndex);
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
                  color: isPlaying ? accent : PlayaColors.onSurface,
                  fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              subtitle: Text(
                item.tag.artist ?? 'Unknown',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: PlayaColors.onSurfaceVariant, fontSize: 12),
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
                color: PlayaColors.onSurfaceVariant,
              ),
              filled: true,
              fillColor: Colors.white10,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              hintStyle: const TextStyle(color: PlayaColors.onSurfaceVariant),
            ),
            style: const TextStyle(color: PlayaColors.onSurface),
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
                  style: const TextStyle(color: PlayaColors.onSurface),
                ),
                subtitle: Text(
                  s.artist ?? '<unknown>',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: PlayaColors.onSurfaceVariant),
                ),
                trailing: IconButton(
                  icon: const Icon(
                    PhosphorIconsRegular.plusCircle,
                    color: PlayaColors.onSurfaceVariant,
                  ),
                  onPressed: () {
                    widget.ctrl.addToQueue(s);
                    showToast(context, 'Added to Queue');
                  },
                ),
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: PlayaColors.surface,
                    builder:
                        (ctx) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(
                                PhosphorIconsRegular.play,
                                color: PlayaColors.onSurface,
                              ),
                              title: const Text(
                                'Play Now',
                                style: TextStyle(color: PlayaColors.onSurface),
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
                                color: PlayaColors.onSurface,
                              ),
                              title: const Text(
                                'Play Next',
                                style: TextStyle(color: PlayaColors.onSurface),
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
                                color: PlayaColors.onSurface,
                              ),
                              title: const Text(
                                'Add to Queue',
                                style: TextStyle(color: PlayaColors.onSurface),
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
            color: PlayaColors.surfaceVariant,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                PhosphorIconsBold.waveform,
                size: 14,
                color: PlayaColors.sonic,
              ),
              const SizedBox(width: 6),
              Text(
                '${meta.bpm!.toInt()} BPM',
                style: const TextStyle(
                  color: PlayaColors.onSurface,
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
                    color: PlayaColors.onSurfaceVariant,
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
