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
import '../ui/now_playing_layout.dart';
import '../ui/turntable_widget.dart';
import '../ui/waveform_widget.dart';
import '../ui/lyrics_sheet.dart';
import 'screensaver_screen.dart';
import '../utils/content_mode.dart';
import '../utils/audio_display_labels.dart';
import '../utils/ui_utils.dart';
import '../widgets/audiobook_controls.dart';
import '../widgets/bookmarks_sheet.dart';
import '../widgets/player_provider.dart';
import '../repositories/playlist_repository.dart';

class _NowPlayingSpacing {
  const _NowPlayingSpacing._();

  static const double screenX = PlayaSpacing.sm;
  /// Between major blocks (metadata / scrub / transport).
  static const double section = PlayaSpacing.xxs;
  /// Within a related group (e.g. speed pills, transport extras).
  static const double group = PlayaSpacing.xxs;
  static const double tight = PlayaSpacing.xxs;
}

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
    if (SettingsService.instance.keepScreenOn &&
        !SettingsService.instance.batterySaver) {
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
                      final isAudiobook =
                          ctrl.currentContentMode == ContentMode.audiobook;

                      return OrientationBuilder(
                        builder: (context, orientation) {
                          final isLandscape =
                              orientation == Orientation.landscape;
                          final hasWaveform = SettingsService.instance
                                  .effectiveShowWaveforms &&
                              tag != null &&
                              tag.extras?['path'] is String &&
                              (tag.extras!['path'] as String).isNotEmpty;

                          final mediaSize = MediaQuery.sizeOf(context);
                          final layout = NowPlayingLayoutMetrics(
                            isLandscape: isLandscape,
                            isAudiobook: isAudiobook,
                            hasWaveform: hasWaveform,
                            viewportHeight: mediaSize.height,
                            viewportWidth: mediaSize.width,
                            musicToolsCollapsed: !isAudiobook,
                          );

                          final controls = _NowPlayingControlsColumn(
                            item: tag,
                            ctrl: ctrl,
                            player: p,
                            waveformHeight: layout.waveformHeight,
                            waveformMode: layout.waveformMode,
                            isVisible: widget.isVisible,
                          );

                          Widget scaledDock({
                            required double width,
                            required double availableHeight,
                            Alignment alignment = Alignment.topCenter,
                          }) {
                            if (layout.shouldScrollDock(availableHeight)) {
                              return SizedBox(
                                width: width,
                                height: availableHeight,
                                child: SingleChildScrollView(
                                  physics: const ClampingScrollPhysics(),
                                  child: Align(
                                    alignment: alignment,
                                    child: SizedBox(
                                      width: width,
                                      child: controls,
                                    ),
                                  ),
                                ),
                              );
                            }
                            return SizedBox(
                              width: width,
                              height: availableHeight,
                              child: FittedBox(
                                fit: BoxFit.contain,
                                alignment: alignment,
                                child: SizedBox(
                                  width: width,
                                  child: controls,
                                ),
                              ),
                            );
                          }

                          Widget turntableHero(double side) {
                            if (side <= 0) {
                              return const SizedBox.shrink();
                            }
                            return SizedBox(
                              width: side,
                              height: side,
                              child: RepaintBoundary(
                                child: TurntableDeck(
                                  ctrl: ctrl,
                                  item: tag,
                                  isVisible: widget.isVisible,
                                ),
                              ),
                            );
                          }

                          if (isLandscape) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: _NowPlayingSpacing.screenX,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 5,
                                    child: LayoutBuilder(
                                      builder: (context, panel) {
                                        final side = layout.turntableSide(
                                          maxWidth: panel.maxWidth,
                                          maxHeight: panel.maxHeight,
                                        );
                                        return Center(
                                          child: turntableHero(side),
                                        );
                                      },
                                    ),
                                  ),
                                  Expanded(
                                    flex: 4,
                                    child: LayoutBuilder(
                                      builder: (context, panel) {
                                        return scaledDock(
                                          width: panel.maxWidth,
                                          availableHeight: panel.maxHeight,
                                          alignment: Alignment.center,
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: _NowPlayingSpacing.screenX,
                            ),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final side = layout.turntableSide(
                                  maxWidth: constraints.maxWidth,
                                  maxHeight: constraints.maxHeight,
                                  viewportHeight: constraints.maxHeight,
                                );

                                return Column(
                                  children: [
                                    SizedBox(
                                      height: side,
                                      width: double.infinity,
                                      child: Center(
                                        child: turntableHero(side),
                                      ),
                                    ),
                                    SizedBox(
                                      height: _NowPlayingSpacing.tight,
                                    ),
                                    Expanded(
                                      child: LayoutBuilder(
                                        builder: (context, dockBox) {
                                          return scaledDock(
                                            width: constraints.maxWidth,
                                            availableHeight: dockBox.maxHeight,
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          );
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

class _NowPlayingControlsColumn extends StatelessWidget {
  final MediaItem? item;
  final PlayerController ctrl;
  final AudioPlayer player;
  final double waveformHeight;
  final WaveformDisplayMode waveformMode;
  final bool isVisible;

  const _NowPlayingControlsColumn({
    required this.item,
    required this.ctrl,
    required this.player,
    required this.waveformHeight,
    this.waveformMode = WaveformDisplayMode.compact,
    this.isVisible = true,
  });

  bool get _hasWaveform {
    if (!SettingsService.instance.effectiveShowWaveforms || item == null) {
      return false;
    }
    final path = item!.extras?['path'];
    return path is String && path.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final isAudiobook = ctrl.currentContentMode == ContentMode.audiobook;

    final metadata = _TrackInfoPanel(
      item: item,
      playerCtrl: ctrl,
      compact: true,
    );

    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: ctrl.bookmarksNotifier,
      builder: (context, bookmarks, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_hasWaveform)
              _WaveformSection(
                item: item,
                player: player,
                height: waveformHeight,
                showDuration: false,
                displayMode: waveformMode,
                bookmarks: bookmarks,
                isVisible: isVisible,
              ),
            const SizedBox(height: 2),
            _PlaybackTimeRow(ctrl: ctrl),
            const SizedBox(height: _NowPlayingSpacing.section),
            metadata,
            if (isAudiobook) ...[
              const SizedBox(height: _NowPlayingSpacing.group),
              AudiobookSpeedRow(ctrl: ctrl, compact: true),
            ],
            const SizedBox(height: _NowPlayingSpacing.section),
            _PlayerControlsSection(ctrl: ctrl, compact: true),
          ],
        );
      },
    );
  }
}

class _NowPlayingFavoriteButton extends StatelessWidget {
  final MediaItem? item;
  final PlayerController ctrl;

  const _NowPlayingFavoriteButton({
    required this.item,
    required this.ctrl,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: ctrl.favoritesNotifier,
      builder: (context, favorites, _) {
        final isFav = item != null && favorites.contains(item!.id);
        final accent = Theme.of(context).colorScheme.primary;
        return IconButton(
          tooltip: isFav ? 'Remove from favorites' : 'Add to favorites',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          onPressed: item == null ? null : () => ctrl.toggleFavorite(item!.id),
          icon: Icon(
            isFav ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
            color: isFav ? accent : PlayaColors.onSurfaceVariant,
            size: 20,
          ),
        );
      },
    );
  }
}class _PlayerControlsSection extends StatelessWidget {
  final PlayerController ctrl;
  final bool compact;

  const _PlayerControlsSection({
    required this.ctrl,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final mode = ctrl.currentContentMode;
    final isAudiobook = mode == ContentMode.audiobook;
    final gap = compact ? _NowPlayingSpacing.group : _NowPlayingSpacing.section;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TransportBar(ctrl: ctrl, compact: compact),
        if (isAudiobook) ...[
          SizedBox(height: gap),
          AudiobookActionRow(ctrl: ctrl, compact: compact),
          SizedBox(height: gap),
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
        ] else ...[
          if (compact) SizedBox(height: gap),
          // Keep shuffle/repeat primary; bury Neural Mix / Speed clutter in Tools.
          _SecondaryControls(
            ctrl: ctrl,
            visibleChips: const {'shuffle', 'repeat'},
            showReorder: false,
          ),
          SizedBox(height: gap),
          MusicToolsExpansion(
            ctrl: ctrl,
            child: _SecondaryControls(
              ctrl: ctrl,
              visibleChips: const {
                'neural_mix',
                'speed',
                'lyrics',
                'screensaver',
                'bookmark',
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _TransportBar extends StatelessWidget {
  final PlayerController ctrl;
  final bool compact;

  const _TransportBar({required this.ctrl, this.compact = false});

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
            padding: EdgeInsets.all(compact ? 11 : 14),
            elevation: compact ? 4 : 6,
            shadowColor: Colors.black54,
            minimumSize: Size(compact ? 46 : 52, compact ? 46 : 52),
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
                  size: compact ? 26 : 30,
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
  final bool showReorder;

  const _SecondaryControls({
    required this.ctrl,
    this.visibleChips,
    this.showReorder = true,
  });

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
            final summary = await widget.ctrl.smartShuffle();
            if (!context.mounted) return;
            if (summary == null) {
              showToast(context, 'Could not generate mix');
              return;
            }
            showToast(context, 'Mix Ready');
            HapticFeedback.mediumImpact();
            await showModalBottomSheet<void>(
              context: context,
              backgroundColor: Colors.transparent,
              builder: (_) => _NeuralMixReadySheet(
                ctrl: widget.ctrl,
                summary: summary,
              ),
            );
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
          key: const ValueKey('screensaver'),
          icon: PhosphorIconsRegular.monitor,
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
        if (widget.showReorder)
          Align(
          alignment: Alignment.centerRight,
          child: Tooltip(
            message: _isReordering ? 'Finish reordering' : 'Reorder controls',
            child: InkWell(
              onTap: () {
                setState(() {
                  _isReordering = !_isReordering;
                  if (!_isReordering) {
                    _selectedChipIndex = null;
                  }
                });
                HapticFeedback.mediumImpact();
                if (_isReordering) {
                  showToast(
                    context,
                    'Tap a chip to select, long-press to move',
                  );
                } else {
                  SettingsService.instance.setControlChipOrder(_chipOrder);
                  showToast(context, 'Order saved');
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _isReordering
                      ? Colors.blue.withValues(alpha: 0.2)
                      : PlayaColors.surface.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isReordering
                        ? Colors.blue.withValues(alpha: 0.6)
                        : Colors.white12,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isReordering
                          ? PhosphorIconsRegular.check
                          : PhosphorIconsRegular.list,
                      size: 15,
                      color: _isReordering
                          ? Colors.blue
                          : PlayaColors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isReordering ? 'Done' : 'Reorder',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _isReordering
                            ? Colors.blue
                            : PlayaColors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
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
    if (label == null) {
      return IconButton(
        tooltip: tooltip,
        icon: PhosphorIcon(icon, size: 24, color: PlayaColors.onSurface),
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      );
    }

    return Tooltip(
      message: tooltip ?? label!,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: 8,
                  child: PhosphorIcon(
                    icon,
                    size: 22,
                    color: PlayaColors.onSurface,
                  ),
                ),
                Positioned(
                  bottom: 6,
                  child: Text(
                    label!,
                    style: const TextStyle(
                      color: PlayaColors.onSurfaceVariant,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      height: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatPlaybackTime(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) return '$h:$m:$s';
  return '$m:$s';
}

class _PlaybackTimeRow extends StatelessWidget {
  final PlayerController ctrl;

  const _PlaybackTimeRow({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final player = ctrl.player;

    return StreamBuilder<Duration>(
      stream: player.positionStream,
      initialData: player.position,
      builder: (context, posSnap) {
        final position = posSnap.data ?? Duration.zero;
        return StreamBuilder<Duration?>(
          stream: player.durationStream,
          initialData: player.duration,
          builder: (context, durSnap) {
            final duration = durSnap.data ?? Duration.zero;
            return LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 180;
                final fontSize = narrow ? 11.0 : 12.0;
                final timeStyle = TextStyle(
                  fontSize: fontSize,
                  fontFamily: 'monospace',
                  height: 1,
                );

                return SizedBox(
                  height: 16,
                  width: double.infinity,
                  child: Row(
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _formatPlaybackTime(position),
                            maxLines: 1,
                            style: timeStyle.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            _formatPlaybackTime(duration),
                            maxLines: 1,
                            textAlign: TextAlign.right,
                            style: timeStyle.copyWith(
                              color: PlayaColors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _TrackInfoPanel extends StatelessWidget {
  final MediaItem? item;
  final PlayerController playerCtrl;
  final bool compact;

  const _TrackInfoPanel({
    required this.item,
    required this.playerCtrl,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final titleStyle = TextStyle(
      fontSize: compact ? 14 : 16,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      height: 1.15,
    );
    final artistStyle = TextStyle(
      color: PlayaColors.onSurfaceVariant,
      fontSize: compact ? 11 : 13,
      height: 1.15,
    );

    final metadata = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          item == null
              ? '—'
              : AudioDisplayLabels.displayTitle(
                  title: item!.title,
                  path: item!.extras?['path'] as String?,
                  artist: item!.artist,
                ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: titleStyle,
        ),
        const SizedBox(height: 2),
        Text(
          item == null
              ? ''
              : AudioDisplayLabels.displayArtistOrFallback(
                  artist: item!.artist,
                  path: item!.extras?['path'] as String?,
                ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: artistStyle,
        ),
        if (!compact &&
            item != null &&
            playerCtrl.currentContentMode == ContentMode.music) ...[
          const SizedBox(height: PlayaSpacing.xs),
          _SonicDnaBadge(songId: item!.id),
        ],
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(width: 32),
        Expanded(child: metadata),
        _NowPlayingFavoriteButton(item: item, ctrl: playerCtrl),
      ],
    );
  }
}

class _WaveformSection extends StatelessWidget {
  final MediaItem? item;
  final AudioPlayer player;
  final double height;
  final bool showDuration;
  final WaveformDisplayMode displayMode;
  final List<Map<String, dynamic>>? bookmarks;
  final bool isVisible;

  const _WaveformSection({
    required this.item,
    required this.player,
    this.height = 80,
    this.showDuration = false,
    this.displayMode = WaveformDisplayMode.compact,
    this.bookmarks,
    this.isVisible = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!SettingsService.instance.effectiveShowWaveforms || item == null) {
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
                  showDuration: showDuration,
                  displayMode: displayMode,
                  bookmarks: bookmarks,
                  isVisible: isVisible,
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                      : (widget.isReordering ? Colors.blue.withValues(alpha: 0.5) : PlayaColors.trackMuted)),
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
                  widget.isSelected ? PhosphorIconsRegular.checkCircle : PhosphorIconsRegular.dotsSixVertical,
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
                  fontSize: 12,
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
    return GlassPanel(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(PlayaRadii.lg),
      ),
      isLibraryPanel: true,
      child: Padding(
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
      borderColor: PlayaColors.border,
      isLibraryPanel: true,
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
              fillColor: PlayaColors.trackMuted,
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
                  tooltip: 'Add to Queue',
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
                    backgroundColor: Colors.transparent,
                    builder:
                        (ctx) => GlassPanel(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16),
                          ),
                          borderColor: Colors.white.withValues(alpha: 0.14),
                          backgroundColor: PlayaColors.glass,
                          child: Column(
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
          margin: const EdgeInsets.only(top: PlayaSpacing.xs),
          padding: const EdgeInsets.symmetric(horizontal: PlayaSpacing.sm, vertical: PlayaSpacing.xxs),
          decoration: PlayaEffects.matteSurface(
            borderRadius: BorderRadius.circular(PlayaRadii.sm),
            baseColor: PlayaColors.surfaceVariant,
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
