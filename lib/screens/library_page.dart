// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart' as oaq;
import 'package:permission_handler/permission_handler.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../services/settings_service.dart';
import '../services/library_scan_service.dart';
import '../services/service_locator.dart';
import '../repositories/song_repository.dart';
import '../widgets/star_rating.dart';
import 'settings_screen.dart';
import 'playlists_screen.dart';
import '../widgets/player_provider.dart';
import '../widgets/artwork_image.dart';
import '../utils/ui_utils.dart';
import '../repositories/playlist_repository.dart';

// Design System (Phase 3 Migration)
import '../design/design_system.dart';
import '../ui/tokens.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  List<oaq.SongModel> _allSongs = [];
  List<oaq.SongModel> _songs = [];
  bool _loading = true;
  bool _showFavoritesOnly = false;
  final _searchCtrl = TextEditingController();

  // Multi-select mode
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    SettingsService.instance.removeListener(_onSettingsChanged);
    LibraryScanService.instance.removeListener(_onScanChanged);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    SettingsService.instance.addListener(_onSettingsChanged);
    LibraryScanService.instance.addListener(_onScanChanged);
    _bootstrap();
  }

  void _onScanChanged() {
    if (!mounted) return;
    final scan = LibraryScanService.instance;

    if (scan.phase == LibraryScanPhase.done) {
      final songs = ServiceLocator.instance.playerController.librarySongs;
      setState(() {
        final seen = <String>{};
        _allSongs =
            songs.where((s) => (s.data).isNotEmpty).where((s) {
              final key = Platform.isWindows ? s.data.toLowerCase() : s.data;
              return seen.add(key);
            }).toList();
        _songs = _computeFiltered(_searchCtrl.text);
        _loading = false;
      });
    } else if (scan.phase == LibraryScanPhase.error) {
      setState(() {
        _loading = false;
      });
    }
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
    _loadSongs();
  }

  Future<void> _bootstrap() async {
    final granted = await _requestPermissions();
    if (!mounted) return;
    if (granted) {
      try {
        await _loadSongs();
      } catch (e) {
        if (mounted) {
          setState(() => _loading = false);
        }
      }
    } else {
      setState(() => _loading = false);
    }
  }

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      Map<Permission, PermissionStatus> statuses =
          await [
            Permission.audio,
            Permission.photos,
            Permission.videos,
          ].request();

      if (statuses[Permission.audio] == PermissionStatus.granted) {
        return true;
      }

      final storageStatus = await Permission.storage.request();
      if (storageStatus.isGranted) return true;

      return false;
    }
    return true;
  }

  Future<void> _loadSongs() async {
    try {
      if (mounted) {
        setState(() => _loading = true);
      }

      final songs = await LibraryScanService.instance.scanLibrary(
        restorePlayerState: true,
      );

      if (!mounted) return;
      setState(() {
        _allSongs = songs.where((s) => (s.data).isNotEmpty).toList();
        _songs = _computeFiltered(_searchCtrl.text);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<oaq.SongModel> _computeFiltered(String query) {
    List<oaq.SongModel> filtered = _allSongs;

    if (_showFavoritesOnly) {
      final favs = ServiceLocator.instance.playerController.favoritesNotifier.value;
      filtered = filtered.where((s) => favs.contains(s.id.toString())).toList();
    }

    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      filtered =
          filtered.where((s) {
            return s.title.toLowerCase().contains(q) ||
                (s.artist?.toLowerCase().contains(q) ?? false) ||
                (s.album?.toLowerCase().contains(q) ?? false);
          }).toList();
    }

    return filtered;
  }

  void _filterSongs(String query) {
    if (_isSelectionMode) {
      // Keep selection but only act on currently visible items when batch actions run
    }
    setState(() {
      _songs = _computeFiltered(query);
    });
  }

  // ==================== MULTI-SELECT HELPERS ====================

  void _enterSelectionMode(String songId) {
    setState(() {
      _isSelectionMode = true;
      _selectedIds.clear();
      _selectedIds.add(songId);
    });
    HapticFeedback.selectionClick();
  }

  void _toggleSelection(String songId) {
    setState(() {
      if (_selectedIds.contains(songId)) {
        _selectedIds.remove(songId);
      } else {
        _selectedIds.add(songId);
      }
      if (_selectedIds.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }

  void _selectAllVisible() {
    setState(() {
      _selectedIds.addAll(_songs.map((s) => s.id.toString()));
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
      _isSelectionMode = false;
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectedIds.clear();
      _isSelectionMode = false;
    });
  }

  List<oaq.SongModel> get _selectedSongs {
    final idSet = _selectedIds;
    return _songs.where((s) => idSet.contains(s.id.toString())).toList();
  }

  Future<void> _playSelected() async {
    final selected = _selectedSongs;
    if (selected.isEmpty) return;
    final ctrl = ServiceLocator.instance.playerController;
    await ctrl.replaceQueue(selected, initialIndex: 0);
    _exitSelectionMode();
    HapticFeedback.selectionClick();
  }

  Future<void> _playNextSelected() async {
    final selected = _selectedSongs;
    if (selected.isEmpty) return;
    final ctrl = ServiceLocator.instance.playerController;
    for (final song in selected) {
      await ctrl.insertNext(song);
    }
    _exitSelectionMode();
    if (mounted) showToast(context, 'Added ${selected.length} song(s) to queue');
    HapticFeedback.selectionClick();
  }

  Future<void> _addSelectedToQueue() async {
    final selected = _selectedSongs;
    if (selected.isEmpty) return;
    final ctrl = ServiceLocator.instance.playerController;
    for (final song in selected) {
      await ctrl.addToQueue(song);
    }
    _exitSelectionMode();
    if (mounted) showToast(context, 'Added ${selected.length} song(s) to queue');
    HapticFeedback.selectionClick();
  }

  Future<void> _toggleFavoriteForSelected() async {
    final selected = _selectedSongs;
    if (selected.isEmpty) return;

    final ctrl = ServiceLocator.instance.playerController;
    final currentFavs = ctrl.favoritesNotifier.value.toSet();

    final anyNotFavorited = selected.any((s) => !currentFavs.contains(s.id.toString()));

    for (final song in selected) {
      final id = song.id.toString();
      final isFav = currentFavs.contains(id);

      if (anyNotFavorited) {
        // Add all that aren't favorited
        if (!isFav) await ctrl.toggleFavorite(id);
      } else {
        // All are favorited → remove all
        if (isFav) await ctrl.toggleFavorite(id);
      }
    }

    _exitSelectionMode();
    if (mounted) {
      final action = anyNotFavorited ? 'favorited' : 'unfavorited';
      showToast(context, '${selected.length} song(s) $action');
    }
    HapticFeedback.selectionClick();
  }

  Future<void> _addSelectedToPlaylist() async {
    final selected = _selectedSongs;
    if (selected.isEmpty) return;

    final playlists = await PlaylistRepository.instance.getAll();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(PlayaSpacing.sm * 2),
          child: PlayaCard(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Add ${selected.length} song(s) to Playlist',
                    style: const TextStyle(
                      color: PlayaColors.onSurface,
                      fontSize: PlayaTypography.lg,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (playlists.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No playlists found', style: TextStyle(color: PlayaColors.onSurfaceVariant)),
                  )
                else
                  ...playlists.map((p) => ListTile(
                        leading: const Icon(Icons.queue_music, color: PlayaColors.onSurfaceVariant),
                        title: Text(p.name, style: const TextStyle(color: PlayaColors.onSurface)),
                        subtitle: Text('${p.songCount} songs', style: const TextStyle(color: PlayaColors.onSurfaceVariant)),
                        onTap: () async {
                          for (final song in selected) {
                            await PlaylistRepository.instance.addSong(p.id, song.id.toString());
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            showToast(context, 'Added ${selected.length} song(s) to "${p.name}"');
                            _exitSelectionMode();
                          }
                        },
                      )),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _playNow(oaq.SongModel s) async {
    final ctrl = ServiceLocator.instance.playerController;
    final index = _songs.indexOf(s);
    if (index != -1) {
      await ctrl.replaceQueue(_songs, initialIndex: index);
    }
    HapticFeedback.selectionClick();
  }

  Future<void> _playNext(oaq.SongModel s) async {
    final ctrl = ServiceLocator.instance.playerController;
    await ctrl.insertNext(s);
    if (!mounted) return;
    showToast(context, 'Added to queue');
    HapticFeedback.selectionClick();
  }

  Future<void> _showRatingDialog(String songId) async {
    final meta = await SongRepository.instance.getMetadata(songId);
    if (!mounted) return;

    int tempRating = meta?.rating ?? 0;
    await showDialog(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setState) => Dialog(
                  backgroundColor: Colors.transparent,
                  child: PlayaCard(
                    padding: const EdgeInsets.all(PlayaSpacing.lg),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Rate Song',
                          style: TextStyle(
                            color: PlayaColors.onSurface,
                            fontSize: PlayaTypography.lg,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: PlayaSpacing.md),
                        Center(
                          child: StarRating(
                            rating: tempRating,
                            size: 36,
                            onRatingChanged:
                                (r) => setState(() => tempRating = r),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            tempRating == 0
                                ? 'No rating'
                                : '$tempRating star${tempRating > 1 ? "s" : ""}',
                            style: const TextStyle(color: PlayaColors.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(height: PlayaSpacing.md),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Cancel'),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () async {
                                await SongRepository.instance.updateRating(
                                  songId,
                                  tempRating,
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (mounted) this.setState(() {});
                              },
                              child: const Text('Save'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
          ),
    );
  }

  void _showSortMenu() {
    final accentColor = Theme.of(context).colorScheme.primary;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(PlayaSpacing.md),
              child: GlassPanel(
                borderRadius: BorderRadius.circular(20),
                color: kColorGlassBlackTint,
                padding: const EdgeInsets.all(PlayaSpacing.sm * 2),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sort Library',
                        style: TextStyle(
                          fontSize: PlayaTypography.lg,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: PlayaSpacing.sm),
                      _buildSortOption(label: 'Date Added', value: 'DATE_ADDED'),
                      _buildSortOption(label: 'Title', value: 'TITLE'),
                      _buildSortOption(label: 'Artist', value: 'ARTIST'),
                      _buildSortOption(label: 'Album', value: 'ALBUM'),
                      const Divider(color: Colors.white10),
                      ListTile(
                        dense: true,
                        title: const Text('Ascending'),
                        leading: Radio<int>(
                          value: 0,
                          groupValue: SettingsService.instance.librarySortOrder,
                          onChanged: (v) {
                            SettingsService.instance.setLibrarySort(
                              SettingsService.instance.librarySortType,
                              v!,
                            );
                            Navigator.pop(context);
                          },
                          activeColor: accentColor,
                        ),
                      ),
                      ListTile(
                        dense: true,
                        title: const Text('Descending'),
                        leading: Radio<int>(
                          value: 1,
                          groupValue: SettingsService.instance.librarySortOrder,
                          onChanged: (v) {
                            SettingsService.instance.setLibrarySort(
                              SettingsService.instance.librarySortType,
                              v!,
                            );
                            Navigator.pop(context);
                          },
                          activeColor: accentColor,
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

  Widget _buildSortOption({required String label, required String value}) {
    final current = SettingsService.instance.librarySortType;
    final accentColor = Theme.of(context).colorScheme.primary;
    return ListTile(
      title: Text(
        label,
        style: TextStyle(color: current == value ? accentColor : PlayaColors.onSurface),
      ),
      trailing: current == value ? Icon(Icons.check, color: accentColor) : null,
      onTap: () {
        SettingsService.instance.setLibrarySort(
          value,
          SettingsService.instance.librarySortOrder,
        );
        Navigator.pop(context);
      },
      dense: true,
    );
  }

  Widget _buildSongTile(oaq.SongModel s, bool isPlaying, Color accentColor) {
    final songId = s.id.toString();
    final isSelected = _selectedIds.contains(songId);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (_isSelectionMode) {
            _toggleSelection(songId);
          } else {
            _playNow(s);
          }
        },
        onLongPress: _isSelectionMode ? null : () => _enterSelectionMode(songId),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected
                ? accentColor.withValues(alpha: 0.15)
                : (isPlaying ? accentColor.withValues(alpha: 0.10) : null),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              // Playing indicator bar or selection checkbox
              if (_isSelectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 8, left: 4),
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) => _toggleSelection(songId),
                    activeColor: accentColor,
                    side: BorderSide(color: PlayaColors.onSurfaceVariant),
                  ),
                )
              else if (isPlaying)
                Container(
                  width: 3,
                  height: 36,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )
              else
                const SizedBox(width: 9),

              ClipRRect(
                borderRadius: BorderRadius.circular(PlayaRadii.sm),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: PlayaColors.glassLight,
                    ),
                    child: ArtworkImage(
                      id: s.id,
                      type: oaq.ArtworkType.AUDIO,
                      nullArtworkWidget: const Icon(
                        Icons.music_note,
                        color: PlayaColors.onSurfaceVariant,
                      ),
                      artworkBorder: BorderRadius.circular(PlayaRadii.sm),
                      artworkFit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: (isPlaying || isSelected) ? accentColor : PlayaColors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.artist ?? '<unknown>',
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

              if (!_isSelectionMode)
                PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_vert,
                    color: PlayaColors.onSurfaceVariant,
                  ),
                  color: PlayaColors.card,
                  onSelected: (value) {
                    switch (value) {
                      case 'play_next':
                        _playNext(s);
                        break;
                      case 'add_playlist':
                        _addToPlaylist(s);
                        break;
                      case 'rate':
                        _showRatingDialog(s.id.toString());
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'play_next',
                      child: Row(
                        children: [
                          Icon(Icons.playlist_add, color: PlayaColors.onSurfaceVariant),
                          SizedBox(width: 12),
                          Text('Play Next', style: TextStyle(color: PlayaColors.onSurface)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'add_playlist',
                      child: Row(
                        children: [
                          Icon(Icons.queue_music, color: PlayaColors.onSurfaceVariant),
                          SizedBox(width: 12),
                          Text('Add to Playlist', style: TextStyle(color: PlayaColors.onSurface)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'rate',
                      child: Row(
                        children: [
                          Icon(Icons.star_outline, color: PlayaColors.onSurfaceVariant),
                          SizedBox(width: 12),
                          Text('Rate Song', style: TextStyle(color: PlayaColors.onSurface)),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addToPlaylist(oaq.SongModel song) async {
    final playlists = await PlaylistRepository.instance.getAll();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(PlayaSpacing.sm * 2),
              child: PlayaCard(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text(
                        'Add to Playlist',
                         style: TextStyle(
                           color: PlayaColors.onSurface,
                           fontSize: PlayaTypography.lg,
                           fontWeight: FontWeight.bold,
                         ),
                      ),
                    ),
                    if (playlists.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No playlists found',
                           style: TextStyle(color: PlayaColors.onSurfaceVariant),
                        ),
                      )
                    else
                      ...playlists.map(
                        (p) => ListTile(
                          leading: const Icon(
                            Icons.queue_music,
                            color: PlayaColors.onSurfaceVariant,
                          ),
                          title: Text(
                            p.name,
                            style: const TextStyle(color: PlayaColors.onSurface),
                          ),
                          subtitle: Text(
                            '${p.songCount} songs',
                            style: const TextStyle(color: PlayaColors.onSurfaceVariant),
                          ),
                          onTap: () async {
                            await PlaylistRepository.instance.addSong(
                              p.id,
                              song.id.toString(),
                            );
                            if (context.mounted) {
                              Navigator.pop(context);
                              showToast(context, 'Added to "${p.name}"');
                            }
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = PlayerProvider.of(context);
    final currentSongId = player.currentMediaItem?.id;
    final scan = LibraryScanService.instance;
    final accentColor = Theme.of(context).colorScheme.primary;

    return AnimatedBuilder(
      animation: scan,
      builder: (context, _) {
        return SafeArea(
          top: true,
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(PlayaSpacing.sm * 2, PlayaSpacing.sm, PlayaSpacing.sm * 2, 0),
                child: SizedBox(
                  height: 44,
                  child: NavigationToolbar(
                    centerMiddle: true,
                    middleSpacing: 0,
                    leading: const SizedBox.shrink(),
                    middle: Text(
                      _isSelectionMode
                          ? '${_selectedIds.length} selected'
                          : 'Library',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _isSelectionMode ? accentColor : null,
                      ),
                    ),
                    trailing: _isSelectionMode
                        ? SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                              // Selection controls
                              IconButton(
                                tooltip: 'Select all visible',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(PhosphorIconsRegular.checks, size: 20),
                                onPressed: _selectAllVisible,
                              ),
                              IconButton(
                                tooltip: 'Clear selection',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(PhosphorIconsRegular.x, size: 20),
                                onPressed: _clearSelection,
                              ),

                              const SizedBox(width: 6),

                              // Playback actions
                              IconButton(
                                tooltip: 'Play',
                                visualDensity: VisualDensity.compact,
                                icon: Icon(PhosphorIconsBold.play, color: accentColor, size: 20),
                                onPressed: _selectedIds.isEmpty ? null : _playSelected,
                              ),
                              IconButton(
                                tooltip: 'Play Next',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(PhosphorIconsRegular.playlist, size: 20),
                                onPressed: _selectedIds.isEmpty ? null : _playNextSelected,
                              ),
                              IconButton(
                                tooltip: 'Add to Queue',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(PhosphorIconsRegular.queue, size: 20),
                                onPressed: _selectedIds.isEmpty ? null : _addSelectedToQueue,
                              ),

                              const SizedBox(width: 4),

                              // Organization
                              IconButton(
                                tooltip: 'Add to Playlist',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(PhosphorIconsBold.playlist, size: 20),
                                onPressed: _selectedIds.isEmpty ? null : _addSelectedToPlaylist,
                              ),
                              IconButton(
                                tooltip: 'Toggle favorite',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(PhosphorIconsRegular.heart, size: 20),
                                onPressed: _selectedIds.isEmpty ? null : _toggleFavoriteForSelected,
                              ),

                              const SizedBox(width: 6),

                              // Exit
                              IconButton(
                                tooltip: 'Done',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(PhosphorIconsRegular.check, size: 20),
                                onPressed: _exitSelectionMode,
                              ),
                            ],
                          ),
                        )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ValueListenableBuilder<List<String>>(
                                valueListenable:
                                    ServiceLocator.instance.playerController.favoritesNotifier,
                                builder: (context, favs, _) {
                                  return IconButton(
                                    tooltip:
                                        _showFavoritesOnly
                                            ? 'Show All'
                                            : 'Show Favorites',
                                    icon: Icon(
                                      _showFavoritesOnly
                                          ? PhosphorIconsFill.heart
                                          : PhosphorIconsRegular.heart,
                                       color:
                                           _showFavoritesOnly
                                               ? Theme.of(context).colorScheme.primary
                                               : PlayaColors.onSurface,
                                    ),
                                    onPressed:
                                        scan.isScanning
                                            ? null
                                       : () {
                                         _exitSelectionMode();
                                         setState(() {
                                           _showFavoritesOnly =
                                               !_showFavoritesOnly;
                                           _songs = _computeFiltered(
                                             _searchCtrl.text,
                                           );
                                         });
                                       },
                                  );
                                },
                              ),
                              IconButton(
                                tooltip: 'Playlists',
                                icon: const Icon(PhosphorIconsBold.playlist),
                                onPressed:
                                    scan.isScanning
                                        ? null
                                        : () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => const PlaylistsScreen(),
                                          ),
                                        ),
                              ),
                              IconButton(
                                tooltip: 'Sort',
                                icon: const Icon(
                                  PhosphorIconsRegular.slidersHorizontal,
                                ),
                                onPressed: scan.isScanning ? null : () {
                            _exitSelectionMode();
                            _showSortMenu();
                          },
                              ),
                              IconButton(
                                tooltip: 'Settings',
                                icon: const Icon(PhosphorIconsBold.gear),
                                onPressed:
                                    () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const SettingsScreen(),
                                      ),
                                    ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              if (scan.isScanning)
                Padding(
                  padding: const EdgeInsets.fromLTRB(PlayaSpacing.sm * 2, PlayaSpacing.sm, PlayaSpacing.sm * 2, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: accentColor,
                            ),
                          ),
                          const SizedBox(width: PlayaSpacing.sm),
                          Text(
                            'Scanning… ${scan.phase.name}',
                            style: const TextStyle(
                              color: PlayaColors.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: scan.progress == 0 ? null : scan.progress,
                          backgroundColor: Colors.white10,
                          color: accentColor,
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                ),
              if (scan.phase == LibraryScanPhase.error &&
                  scan.lastError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(PlayaSpacing.sm * 2, PlayaSpacing.sm, PlayaSpacing.sm * 2, 0),
                  child: GlassPanel(
                    borderRadius: BorderRadius.circular(kRadius),
                    padding: const EdgeInsets.all(PlayaSpacing.sm),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.redAccent,
                          size: 18,
                        ),
                        const SizedBox(width: PlayaSpacing.sm),
                        Expanded(
                          child: Text(
                            'Scan failed. ${scan.lastError}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: PlayaColors.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: scan.isScanning ? null : _loadSongs,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(PlayaSpacing.sm * 2, 0, PlayaSpacing.sm * 2, 0),
                  child: GlassPanel(
                    borderRadius: BorderRadius.circular(18),
                    color: PlayaColors.glassLight,
                    boxShadow: const [],
                    padding: const EdgeInsets.all(PlayaSpacing.sm),
                    child: Column(
                      children: [
                        GlassPanel(
                          borderRadius: BorderRadius.circular(999),
                          color: PlayaColors.glassLight,
                          boxShadow: const [],
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: _filterSongs,
                            style: const TextStyle(color: PlayaColors.onSurface),
                            decoration: const InputDecoration(
                              hintText: 'Search songs, artists…',
                              hintStyle: TextStyle(color: PlayaColors.onSurfaceVariant),
                              prefixIcon: Icon(
                                PhosphorIconsRegular.magnifyingGlass,
                                color: PlayaColors.onSurfaceVariant,
                              ),
                              filled: false,
                              border: OutlineInputBorder(
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        Container(
                          height: 1,
                          color: PlayaColors.borderSubtle,
                        ),
                        const SizedBox(height: 6),

                        Expanded(
                          child:
                              _loading
                                  ? Center(
                                    child: CircularProgressIndicator(
                                      color: accentColor,
                                    ),
                                  )
                                  : _songs.isEmpty
                                  ? Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          _showFavoritesOnly
                                              ? PhosphorIconsRegular.heartBreak
                                              : PhosphorIconsRegular.musicNotes,
                                          size: 54,
                                          color: PlayaColors.onSurfaceVariant,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          _showFavoritesOnly
                                              ? 'No favorites yet'
                                              : (_allSongs.isEmpty
                                                  ? 'No songs found'
                                                  : 'No matches'),
                                          style: const TextStyle(
                                            color: PlayaColors.onSurfaceVariant,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (_allSongs.isEmpty &&
                                            !_showFavoritesOnly)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 10,
                                            ),
                                            child: TextButton(
                                              onPressed:
                                                  scan.isScanning
                                                      ? null
                                                      : _loadSongs,
                                              child: const Text(
                                                'Refresh Library',
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  )
                                  : ListView.separated(
                                    padding: const EdgeInsets.only(
                                      bottom: 72, 
                                    ),
                                    itemCount: _songs.length,
                                    separatorBuilder: (context, index) {
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          left: 64,
                                        ),
                                        child: Container(
                                          height: 1,
                                          color: Colors.white.withValues(
                                            alpha: 0.06,
                                          ),
                                        ),
                                      );
                                    },
                                     itemBuilder: (context, index) {
                                       final s = _songs[index];
                                       final isPlaying =
                                           currentSongId == s.id.toString();

                                        return _buildSongTile(s, isPlaying, accentColor);
                                      },
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
