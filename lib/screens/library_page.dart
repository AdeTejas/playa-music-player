// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:on_audio_query/on_audio_query.dart' as oaq;
import 'package:permission_handler/permission_handler.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../services/settings_service.dart';
import '../services/library_scan_service.dart';
import '../services/service_locator.dart';
import '../repositories/song_repository.dart';
import '../widgets/star_rating.dart';
import 'settings_screen.dart';
import '../widgets/player_provider.dart';
import '../widgets/artwork_image.dart';
import '../widgets/equalizer_indicator.dart';
import '../utils/ui_utils.dart';
import '../repositories/playlist_repository.dart';
import '../models/listening_progress.dart';
import '../widgets/continue_listening_section.dart';
import '../utils/content_mode.dart';

import '../design/design_system.dart';

class LibraryPage extends StatefulWidget {
  final bool isVisible;

  const LibraryPage({super.key, this.isVisible = true});

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

  List<ListeningProgress> _allContinueListening = [];

  String _trackedSortType = SettingsService.instance.librarySortType;
  int _trackedSortOrder = SettingsService.instance.librarySortOrder;
  LibraryBrowseFilter _trackedBrowseFilter =
      SettingsService.instance.libraryBrowseFilter;

  List<ListeningProgress> get _filteredContinueListening =>
      _filterContinueListening(_allContinueListening);

  void _applySongList(List<oaq.SongModel> songs, {required bool loading}) {
    final seen = <String>{};
    _allSongs =
        songs.where((s) => s.data.isNotEmpty).where((s) {
          final key = Platform.isWindows ? s.data.toLowerCase() : s.data;
          return seen.add(key);
        }).toList();
    _songs = _computeFiltered(_searchCtrl.text);
    _loading = loading;
  }

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

  @override
  void didUpdateWidget(LibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadContinueListening();
    }
  }

  void _onScanChanged() {
    if (!mounted) return;
    final scan = LibraryScanService.instance;

    if (scan.phase == LibraryScanPhase.done) {
      final songs = ServiceLocator.instance.playerController.librarySongs;
      setState(() => _applySongList(songs, loading: false));
    } else if (scan.phase == LibraryScanPhase.error) {
      setState(() {
        _loading = false;
      });
    }
  }

  void _onSettingsChanged() {
    if (!mounted) return;

    final settings = SettingsService.instance;
    final sortChanged =
        _trackedSortType != settings.librarySortType ||
        _trackedSortOrder != settings.librarySortOrder;
    final filterChanged = _trackedBrowseFilter != settings.libraryBrowseFilter;
    if (!sortChanged && !filterChanged) return;

    _trackedSortType = settings.librarySortType;
    _trackedSortOrder = settings.librarySortOrder;
    _trackedBrowseFilter = settings.libraryBrowseFilter;

    setState(() {
      if (sortChanged) {
        _allSongs = LibraryScanService.instance.sortSongs(_allSongs);
      }
      _songs = _computeFiltered(_searchCtrl.text);
    });
    if (filterChanged) {
      unawaited(_loadContinueListening());
    }
  }

  Future<void> _bootstrap() async {
    final cached = ServiceLocator.instance.playerController.librarySongs;
    if (cached.isNotEmpty) {
      setState(() => _applySongList(cached, loading: false));
      unawaited(_loadContinueListening());
    }

    final granted = await _requestPermissions();
    if (!mounted) return;
    if (!granted) {
      if (cached.isEmpty) setState(() => _loading = false);
      return;
    }

    if (cached.isNotEmpty && !LibraryScanService.instance.isScanning) {
      return;
    }

    try {
      await _loadSongs(force: true);
    } catch (_) {
      if (mounted && cached.isEmpty) setState(() => _loading = false);
    }
  }

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      // Permission.audio = READ_MEDIA_AUDIO on Android 13+ (declared in the
      // manifest); older Android falls back to storage access below.
      if (await Permission.audio.isGranted) return true;

      final audioStatus = await Permission.audio.request();
      if (audioStatus.isGranted) return true;

      // READ_EXTERNAL_STORAGE only applies on Android 12 and below.
      final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      if (sdk < 33) {
        final storageStatus = await Permission.storage.request();
        return storageStatus.isGranted;
      }

      return false;
    }
    return true;
  }

  Future<void> _loadSongs({bool force = false}) async {
    try {
      final cached = ServiceLocator.instance.playerController.librarySongs;
      if (!force &&
          cached.isNotEmpty &&
          LibraryScanService.instance.phase == LibraryScanPhase.done) {
        if (mounted) setState(() => _applySongList(cached, loading: false));
        return;
      }

      if (mounted && _allSongs.isEmpty) {
        setState(() => _loading = true);
      }

      final songs = await LibraryScanService.instance.scanLibrary(
        restorePlayerState: true,
        force: force,
      );

      if (!mounted) return;
      setState(() => _applySongList(songs, loading: false));
      await _loadContinueListening();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadContinueListening() async {
    try {
      final items =
          await ServiceLocator.instance.playerController.getRecentListening();
      if (!mounted) return;
      setState(() {
        _allContinueListening = items;
      });
    } catch (_) {}
  }

  List<ListeningProgress> _filterContinueListening(
    List<ListeningProgress> items,
  ) {
    final browseFilter = SettingsService.instance.libraryBrowseFilter;

    return items
        .where((p) => p.positionMs >= 30 * 1000)
        .where((p) {
          if (browseFilter == LibraryBrowseFilter.all) return true;
          if (browseFilter == LibraryBrowseFilter.audiobook) {
            return p.contentMode == ContentMode.audiobook;
          }
          return p.contentMode == ContentMode.music;
        })
        .take(6)
        .toList();
  }

  Future<void> _dismissContinueListening(String seriesKey) async {
    await ServiceLocator.instance.playerController.dismissListeningProgress(
      seriesKey,
    );
    await _loadContinueListening();
  }

  String _emptyLibraryMessage() {
    if (_showFavoritesOnly) return 'No favorites yet';
    if (_allSongs.isEmpty) {
      return 'Your library is empty';
    }

    final filter = SettingsService.instance.libraryBrowseFilter;
    if (filter == LibraryBrowseFilter.audiobook) {
      return 'No audiobooks or podcasts found';
    }
    if (filter == LibraryBrowseFilter.music) {
      return 'No music tracks found';
    }
    return 'No matches';
  }

  String? _emptyLibraryHint() {
    if (_showFavoritesOnly) {
      return 'Tap the heart on any track to save it here.';
    }
    if (_allSongs.isEmpty) {
      return 'Grant media access or add folders in Settings, then refresh.';
    }
    final filter = SettingsService.instance.libraryBrowseFilter;
    if (filter == LibraryBrowseFilter.audiobook) {
      return 'Try All or Music, or rescan after adding long-form files.';
    }
    if (filter == LibraryBrowseFilter.music) {
      return 'Try All, or clear search if you are filtering.';
    }
    return 'Clear search or switch filters to see more.';
  }

  String _tracksHeaderLabel(LibraryScanService scan) {
    if (_isSelectionMode) return '${_selectedIds.length} selected';
    final n = _allSongs.length;
    if (scan.isScanning) return '$n TRACKS · updating';
    return '$n TRACKS';
  }

  List<oaq.SongModel> _computeFiltered(String query) {
    List<oaq.SongModel> filtered = _allSongs;

    final browseFilter = SettingsService.instance.libraryBrowseFilter;
    if (browseFilter != LibraryBrowseFilter.all) {
      filtered =
          filtered
              .where(
                (s) => ContentModeDetector.songMatchesBrowseFilter(
                  s,
                  browseFilter,
                ),
              )
              .toList();
    }

    if (_showFavoritesOnly) {
      final favs =
          ServiceLocator.instance.playerController.favoritesNotifier.value;
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
    // insertNext always inserts at currentIndex + 1, so iterate in reverse
    // to keep the selection order intact in the queue.
    for (final song in selected.reversed) {
      await ctrl.insertNext(song);
    }
    _exitSelectionMode();
    if (mounted) {
      showToast(context, 'Added ${selected.length} song(s) to queue');
    }
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
    if (mounted) {
      showToast(context, 'Added ${selected.length} song(s) to queue');
    }
    HapticFeedback.selectionClick();
  }

  Future<void> _toggleFavoriteForSelected() async {
    final selected = _selectedSongs;
    if (selected.isEmpty) return;

    final ctrl = ServiceLocator.instance.playerController;
    final currentFavs = ctrl.favoritesNotifier.value.toSet();

    final anyNotFavorited = selected.any(
      (s) => !currentFavs.contains(s.id.toString()),
    );

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
      builder:
          (ctx) => SafeArea(
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
                        child: Text(
                          'No playlists found',
                          style: TextStyle(color: PlayaColors.onSurfaceVariant),
                        ),
                      )
                    else
                      ...playlists.map(
                        (p) => ListTile(
                          leading: const Icon(
                            PhosphorIconsRegular.playlist,
                            color: PlayaColors.onSurfaceVariant,
                          ),
                          title: Text(
                            p.name,
                            style: const TextStyle(
                              color: PlayaColors.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            '${p.songCount} songs',
                            style: const TextStyle(
                              color: PlayaColors.onSurfaceVariant,
                            ),
                          ),
                          onTap: () async {
                            for (final song in selected) {
                              await PlaylistRepository.instance.addSong(
                                p.id,
                                song.id.toString(),
                              );
                            }
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) {
                              showToast(
                                context,
                                'Added ${selected.length} song(s) to "${p.name}"',
                              );
                              _exitSelectionMode();
                            }
                          },
                        ),
                      ),
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
                            style: const TextStyle(
                              color: PlayaColors.onSurfaceVariant,
                            ),
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
                useStrongVariant: true,
                borderRadius: BorderRadius.circular(PlayaRadii.lg),
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
                      _buildSortOption(
                        label: 'Date Added',
                        value: 'DATE_ADDED',
                      ),
                      _buildSortOption(label: 'Title', value: 'TITLE'),
                      _buildSortOption(label: 'Artist', value: 'ARTIST'),
                      _buildSortOption(label: 'Album', value: 'ALBUM'),
                      const Divider(color: PlayaColors.borderSubtle),
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
        style: TextStyle(
          color: current == value ? accentColor : PlayaColors.onSurface,
        ),
      ),
      trailing:
          current == value
              ? Icon(PhosphorIconsRegular.check, color: accentColor)
              : null,
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
    final player = PlayerProvider.of(context);
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
        onLongPress:
            _isSelectionMode ? null : () => _enterSelectionMode(songId),
        child: Container(
          decoration: BoxDecoration(
            color:
                isSelected
                    ? accentColor.withValues(alpha: 0.18)
                    : (isPlaying ? accentColor.withValues(alpha: 0.12) : null),
            borderRadius: BorderRadius.circular(PlayaRadii.sm),
            border:
                isSelected || isPlaying
                    ? Border.all(
                      color: accentColor.withValues(alpha: 0.2),
                      width: 0.5,
                    )
                    : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
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
                    side: const BorderSide(color: PlayaColors.onSurfaceVariant),
                  ),
                )
              else if (isPlaying)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: StreamBuilder<bool>(
                    stream: player.player.playingStream,
                    initialData: player.player.playing,
                    builder: (context, snap) {
                      final isActuallyPlaying = snap.data ?? false;
                      if (!isActuallyPlaying) {
                        return Container(
                          width: 3,
                          height: 36,
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        );
                      }
                      return SizedBox(
                        width: 12,
                        height: 36,
                        child: Center(
                          child: EqualizerIndicator(color: accentColor),
                        ),
                      );
                    },
                  ),
                )
              else
                const SizedBox(width: PlayaSpacing.sm),

              ClipRRect(
                borderRadius: BorderRadius.circular(PlayaRadii.sm),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: PlayaColors.surfaceVariant,
                    ),
                    child: ArtworkImage(
                      id: s.id,
                      type: oaq.ArtworkType.AUDIO,
                      nullArtworkWidget: const Icon(
                        PhosphorIconsRegular.musicNote,
                        color: PlayaColors.onSurfaceVariant,
                      ),
                      artworkBorder: BorderRadius.circular(PlayaRadii.sm),
                      artworkFit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: PlayaSpacing.xs),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color:
                            (isPlaying || isSelected)
                                ? accentColor
                                : PlayaColors.onSurface,
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
                    PhosphorIconsRegular.dotsThreeVertical,
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
                  itemBuilder:
                      (context) => [
                        const PopupMenuItem(
                          value: 'play_next',
                          child: Row(
                            children: [
                              Icon(
                                PhosphorIconsRegular.playlist,
                                color: PlayaColors.onSurfaceVariant,
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Play Next',
                                style: TextStyle(color: PlayaColors.onSurface),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'add_playlist',
                          child: Row(
                            children: [
                              Icon(
                                PhosphorIconsRegular.plusCircle,
                                color: PlayaColors.onSurfaceVariant,
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Add to Playlist',
                                style: TextStyle(color: PlayaColors.onSurface),
                              ),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'rate',
                          child: Row(
                            children: [
                              Icon(
                                PhosphorIconsRegular.star,
                                color: PlayaColors.onSurfaceVariant,
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Rate Song',
                                style: TextStyle(color: PlayaColors.onSurface),
                              ),
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
                            PhosphorIconsRegular.playlist,
                            color: PlayaColors.onSurfaceVariant,
                          ),
                          title: Text(
                            p.name,
                            style: const TextStyle(
                              color: PlayaColors.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            '${p.songCount} songs',
                            style: const TextStyle(
                              color: PlayaColors.onSurfaceVariant,
                            ),
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              PlayaSpacing.xs,
              PlayaSpacing.xs,
              PlayaSpacing.xs,
              0,
            ),
            child: GlassPanel(
              isLibraryPanel: true,
              useDeepVariant: true,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(PlayaRadii.lg),
              ),
              padding: const EdgeInsets.fromLTRB(
                PlayaSpacing.sm,
                PlayaSpacing.xs,
                PlayaSpacing.sm,
                PlayaSpacing.sm,
              ),
              child: Column(
                children: [
                  SizedBox(
                    height: 44,
                    child: Column(
                      children: [
                        Expanded(
                          child: NavigationToolbar(
                            centerMiddle: true,
                            middleSpacing: 0,
                            leading: const SizedBox.shrink(),
                            middle: Text(
                              _tracksHeaderLabel(scan),
                              style: TextStyle(
                                fontSize: 16,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                                color:
                                    _isSelectionMode
                                        ? accentColor
                                        : PlayaColors.onSurfaceVariant
                                            .withValues(alpha: 0.8),
                              ),
                            ),
                            trailing:
                                _isSelectionMode
                                    ? SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Selection controls
                                          IconButton(
                                            tooltip: 'Select all visible',
                                            visualDensity:
                                                VisualDensity.compact,
                                            icon: const Icon(
                                              PhosphorIconsRegular.checks,
                                              size: 20,
                                            ),
                                            onPressed: _selectAllVisible,
                                          ),
                                          IconButton(
                                            tooltip: 'Clear selection',
                                            visualDensity:
                                                VisualDensity.compact,
                                            icon: const Icon(
                                              PhosphorIconsRegular.x,
                                              size: 20,
                                            ),
                                            onPressed: _clearSelection,
                                          ),

                                          const SizedBox(width: 6),

                                          // Playback actions
                                          IconButton(
                                            tooltip: 'Play',
                                            visualDensity:
                                                VisualDensity.compact,
                                            icon: Icon(
                                              PhosphorIconsBold.play,
                                              color: accentColor,
                                              size: 20,
                                            ),
                                            onPressed:
                                                _selectedIds.isEmpty
                                                    ? null
                                                    : _playSelected,
                                          ),
                                          IconButton(
                                            tooltip: 'Play Next',
                                            visualDensity:
                                                VisualDensity.compact,
                                            icon: const Icon(
                                              PhosphorIconsRegular.playlist,
                                              size: 20,
                                            ),
                                            onPressed:
                                                _selectedIds.isEmpty
                                                    ? null
                                                    : _playNextSelected,
                                          ),
                                          IconButton(
                                            tooltip: 'Add to Queue',
                                            visualDensity:
                                                VisualDensity.compact,
                                            icon: const Icon(
                                              PhosphorIconsRegular.queue,
                                              size: 20,
                                            ),
                                            onPressed:
                                                _selectedIds.isEmpty
                                                    ? null
                                                    : _addSelectedToQueue,
                                          ),

                                          const SizedBox(width: 4),

                                          // Organization
                                          IconButton(
                                            tooltip: 'Add to Playlist',
                                            visualDensity:
                                                VisualDensity.compact,
                                            icon: const Icon(
                                              PhosphorIconsBold.playlist,
                                              size: 20,
                                            ),
                                            onPressed:
                                                _selectedIds.isEmpty
                                                    ? null
                                                    : _addSelectedToPlaylist,
                                          ),
                                          IconButton(
                                            tooltip: 'Toggle favorite',
                                            visualDensity:
                                                VisualDensity.compact,
                                            icon: const Icon(
                                              PhosphorIconsRegular.heart,
                                              size: 20,
                                            ),
                                            onPressed:
                                                _selectedIds.isEmpty
                                                    ? null
                                                    : _toggleFavoriteForSelected,
                                          ),

                                          const SizedBox(width: 6),

                                          // Exit
                                          IconButton(
                                            tooltip: 'Done',
                                            visualDensity:
                                                VisualDensity.compact,
                                            icon: const Icon(
                                              PhosphorIconsRegular.check,
                                              size: 20,
                                            ),
                                            onPressed: _exitSelectionMode,
                                          ),
                                        ],
                                      ),
                                    )
                                    : SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip: 'Settings',
                                            icon: const Icon(
                                              PhosphorIconsBold.gear,
                                            ),
                                            onPressed:
                                                () => Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder:
                                                        (_) =>
                                                            const SettingsScreen(),
                                                  ),
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                          ),
                        ),
                        Container(
                          height: 0.5,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.transparent,
                                accentColor.withValues(alpha: 0.3),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (scan.isScanning)
                    Padding(
                      padding: const EdgeInsets.only(top: PlayaSpacing.xs),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: PlayaColors.accent,
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
                            borderRadius: BorderRadius.circular(
                              PlayaRadii.pill,
                            ),
                            child: LinearProgressIndicator(
                              value: scan.progress == 0 ? null : scan.progress,
                              backgroundColor: PlayaColors.trackMuted,
                              color: accentColor,
                              minHeight: 6,
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (!_isSelectionMode &&
                      _filteredContinueListening.isNotEmpty)
                    ContinueListeningSection(
                      items: _filteredContinueListening,
                      ctrl: ServiceLocator.instance.playerController,
                      librarySongs: _allSongs,
                      onResume: () {
                        if (mounted) {
                          showToast(context, 'Resuming where you left off');
                        }
                      },
                      onDismiss:
                          (seriesKey) => _dismissContinueListening(seriesKey),
                    ),

                  const SizedBox(height: PlayaSpacing.sm),

                  Expanded(
                    child: Column(
                      children: [
                        DecoratedBox(
                          decoration: PlayaEffects.insetField(),
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: _filterSongs,
                            style: const TextStyle(
                              color: PlayaColors.onSurface,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Search songs, artists…',
                              hintStyle: const TextStyle(
                                color: PlayaColors.onSurfaceVariant,
                              ),
                              prefixIcon: const Icon(
                                PhosphorIconsRegular.magnifyingGlass,
                                color: PlayaColors.onSurfaceVariant,
                              ),
                              suffixIcon: IconButton(
                                tooltip: 'Sort',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(
                                  PhosphorIconsRegular.slidersHorizontal,
                                  color: PlayaColors.onSurfaceVariant,
                                  size: 18,
                                ),
                                onPressed:
                                    scan.isScanning ? null : _showSortMenu,
                              ),
                              filled: false,
                              border: const OutlineInputBorder(
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: PlayaSpacing.xs),
                        AnimatedBuilder(
                          animation: SettingsService.instance,
                          builder: (context, _) {
                            final filter =
                                SettingsService.instance.libraryBrowseFilter;
                            final accent =
                                Theme.of(context).colorScheme.primary;
                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (final option
                                      in LibraryBrowseFilter.values) ...[
                                    if (option !=
                                        LibraryBrowseFilter.values.first)
                                      const SizedBox(
                                        width: PlayaSpacing.xxs * 1.5,
                                      ),
                                    ChoiceChip(
                                      label: Text(option.label),
                                      selected: filter == option,
                                      onSelected:
                                          scan.isScanning
                                              ? null
                                              : (_) async {
                                                await SettingsService.instance
                                                    .setLibraryBrowseFilter(
                                                      option,
                                                    );
                                                if (!mounted) return;
                                                setState(() {
                                                  _songs = _computeFiltered(
                                                    _searchCtrl.text,
                                                  );
                                                });
                                              },
                                      selectedColor: accent.withValues(
                                        alpha: 0.25,
                                      ),
                                      labelStyle: TextStyle(
                                        color:
                                            filter == option
                                                ? accent
                                                : PlayaColors.onSurfaceVariant,
                                        fontSize: 12,
                                        fontWeight:
                                            filter == option
                                                ? FontWeight.w600
                                                : FontWeight.w500,
                                      ),
                                      side: BorderSide(
                                        color:
                                            filter == option
                                                ? accent.withValues(alpha: 0.5)
                                                : PlayaColors.borderSubtle,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(width: PlayaSpacing.xxs * 1.5),
                                  ChoiceChip(
                                    avatar: Icon(
                                      _showFavoritesOnly
                                          ? PhosphorIconsFill.heart
                                          : PhosphorIconsRegular.heart,
                                      size: 13,
                                      color:
                                          _showFavoritesOnly
                                              ? accent
                                              : PlayaColors.onSurfaceVariant,
                                    ),
                                    label: const Text('Favorites'),
                                    selected: _showFavoritesOnly,
                                    onSelected:
                                        scan.isScanning
                                            ? null
                                            : (_) {
                                              setState(() {
                                                _showFavoritesOnly =
                                                    !_showFavoritesOnly;
                                                _songs = _computeFiltered(
                                                  _searchCtrl.text,
                                                );
                                              });
                                            },
                                    selectedColor: accent.withValues(
                                      alpha: 0.25,
                                    ),
                                    labelStyle: TextStyle(
                                      color:
                                          _showFavoritesOnly
                                              ? accent
                                              : PlayaColors.onSurfaceVariant,
                                      fontSize: 12,
                                      fontWeight:
                                          _showFavoritesOnly
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                    ),
                                    side: BorderSide(
                                      color:
                                          _showFavoritesOnly
                                              ? accent.withValues(alpha: 0.5)
                                              : PlayaColors.borderSubtle,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: PlayaSpacing.xs),

                        Container(height: 1, color: PlayaColors.borderSubtle),
                        const SizedBox(height: PlayaSpacing.xs),

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
                                          _emptyLibraryMessage(),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: PlayaColors.onSurfaceVariant,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (_emptyLibraryHint() != null)
                                          Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                              24,
                                              8,
                                              24,
                                              0,
                                            ),
                                            child: Text(
                                              _emptyLibraryHint()!,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: PlayaColors
                                                    .onSurfaceVariant
                                                    .withValues(alpha: 0.85),
                                                fontSize: 12,
                                                height: 1.35,
                                              ),
                                            ),
                                          ),
                                        if (_allSongs.isEmpty &&
                                            !_showFavoritesOnly) ...[
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 14,
                                            ),
                                            child: FilledButton.tonal(
                                              onPressed: () => Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      const SettingsScreen(),
                                                ),
                                              ),
                                              child: const Text(
                                                'Open Settings',
                                              ),
                                            ),
                                          ),
                                          TextButton(
                                            onPressed:
                                                scan.isScanning
                                                    ? null
                                                    : () => _loadSongs(
                                                      force: true,
                                                    ),
                                            child: const Text(
                                              'Refresh Library',
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  )
                                  : ListView.separated(
                                    padding: const EdgeInsets.only(bottom: 72),
                                    itemCount: _songs.length,
                                    separatorBuilder: (context, index) {
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          left: 64,
                                        ),
                                        child: Container(
                                          height: 1,
                                          color: PlayaColors.borderSubtle,
                                        ),
                                      );
                                    },
                                    itemBuilder: (context, index) {
                                      final s = _songs[index];
                                      final isPlaying =
                                          currentSongId == s.id.toString();

                                      return _buildSongTile(
                                        s,
                                        isPlaying,
                                        accentColor,
                                      );
                                    },
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
