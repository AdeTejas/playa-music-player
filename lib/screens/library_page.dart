import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart' as oaq;
import 'package:permission_handler/permission_handler.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../ui/tokens.dart';
import '../services/player_controller.dart';
import '../services/settings_service.dart';
import '../services/library_scan_service.dart';
import '../repositories/song_repository.dart';
import '../widgets/star_rating.dart';
import 'settings_screen.dart';
import 'playlists_screen.dart';
import '../widgets/player_provider.dart';
import '../widgets/artwork_image.dart';
import '../utils/ui_utils.dart';
import '../repositories/playlist_repository.dart';
import '../ui/glass_panel.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final _query = oaq.OnAudioQuery();
  List<oaq.SongModel> _allSongs = [];
  List<oaq.SongModel> _songs = [];
  bool _loading = true;
  bool _showFavoritesOnly = false;
  final _searchCtrl = TextEditingController();

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

    // If a scan was started from elsewhere (e.g. Settings), refresh the view
    // when it completes by reading the PlayerController library cache.
    if (scan.phase == LibraryScanPhase.done) {
      final songs = PlayerController.ensure().librarySongs;
      setState(() {
        // Safety-net dedupe in case a platform query returns duplicates.
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
    debugPrint('DEBUG: _bootstrap started');
    final granted = await _requestPermissions();
    debugPrint('DEBUG: Permissions granted: $granted');
    if (!mounted) return;
    if (granted) {
      try {
        // Check if on_audio_query recognizes the permission
        bool oaqStatus = true;
        if (Platform.isAndroid) {
          oaqStatus = await _query.permissionsStatus();
          debugPrint('DEBUG: on_audio_query status: $oaqStatus');

          if (!oaqStatus) {
            debugPrint(
              'DEBUG: on_audio_query needs permission update. Calling permissionsRequest()...',
            );
            try {
              // Call permissionsRequest to update internal state, but with timeout
              oaqStatus = await _query.permissionsRequest().timeout(
                const Duration(seconds: 2),
              );
              debugPrint('DEBUG: permissionsRequest result: $oaqStatus');
            } catch (e) {
              debugPrint('DEBUG: permissionsRequest failed/timed out: $e');
            }
          }
        }

        debugPrint('DEBUG: Starting _loadSongs');
        await _loadSongs();
        debugPrint('DEBUG: _loadSongs completed');
      } catch (e) {
        debugPrint('DEBUG: _loadSongs failed: $e');
        if (mounted) {
          setState(() => _loading = false);
          showToast(context, 'Failed to load songs: $e');
        }
      }
    } else {
      debugPrint('DEBUG: Permissions denied, skipping song load');
      setState(() => _loading = false);
    }
  }

  Future<bool> _requestPermissions() async {
    debugPrint('DEBUG: Requesting permissions...');
    if (Platform.isAndroid) {
      // Try audio permission first (Android 13+)
      Map<Permission, PermissionStatus> statuses =
          await [
            Permission.audio,
            Permission.photos,
            Permission.videos,
          ].request();

      if (statuses[Permission.audio] == PermissionStatus.granted) {
        return true;
      }

      // If audio permission is not granted, try storage permission (Android 12 and below)
      final storageStatus = await Permission.storage.request();
      if (storageStatus.isGranted) return true;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Storage/Audio permission is required to access music files',
            ),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () {
                openAppSettings();
              },
            ),
          ),
        );
      }
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
      showToast(
        context,
        "Couldn't read your audio library: ${e is TimeoutException ? 'Query timed out' : 'Check permissions'}",
      );
    }
  }

  List<oaq.SongModel> _computeFiltered(String query) {
    List<oaq.SongModel> filtered = _allSongs;

    // 1. Filter by Favorites
    if (_showFavoritesOnly) {
      final favs = PlayerController.ensure().favoritesNotifier.value;
      filtered = filtered.where((s) => favs.contains(s.id.toString())).toList();
    }

    // 2. Filter by Search Query
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
    setState(() {
      _songs = _computeFiltered(query);
    });
  }

  Future<void> _playNow(oaq.SongModel s) async {
    final ctrl = PlayerController.ensure();
    final index = _songs.indexOf(s);
    if (index != -1) {
      await ctrl.replaceQueue(_songs, initialIndex: index);
    }
    HapticFeedback.selectionClick();
  }

  Future<void> _playNext(oaq.SongModel s) async {
    final ctrl = PlayerController.ensure();
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
                  child: GlassPanel(
                    borderRadius: BorderRadius.circular(18),
                    borderColor: Colors.white.withValues(alpha: 0.15),
                    backdropBlurSigma: 0,
                    backgroundColor: kColorGlassBlackTint,
                    padding: const EdgeInsets.all(kSp * 2),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Rate Song',
                          style: TextStyle(
                            color: kColorOn,
                            fontSize: kTextLg,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: kSp * 1.5),
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
                            style: const TextStyle(color: kColorOn2),
                          ),
                        ),
                        const SizedBox(height: kSp * 1.5),
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
                                if (mounted) setState(() {});
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
              padding: const EdgeInsets.all(kSp * 2),
              child: GlassPanel(
                borderRadius: BorderRadius.circular(20),
                borderColor: Colors.white.withValues(alpha: 0.15),
                backdropBlurSigma: 0,
                backgroundColor: kColorGlassBlackTint,
                padding: const EdgeInsets.all(kSp * 2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sort Library',
                      style: TextStyle(
                        fontSize: kTextLg,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: kSp),
                    _buildSortOption(label: 'Date Added', value: 'DATE_ADDED'),
                    _buildSortOption(label: 'Title', value: 'TITLE'),
                    _buildSortOption(label: 'Artist', value: 'ARTIST'),
                    _buildSortOption(label: 'Album', value: 'ALBUM'),
                    const Divider(color: Colors.white10),
                    ListTile(
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
    );
  }

  Widget _buildSortOption({required String label, required String value}) {
    final current = SettingsService.instance.librarySortType;
    final accentColor = Theme.of(context).colorScheme.primary;
    return ListTile(
      title: Text(
        label,
        style: TextStyle(color: current == value ? accentColor : kColorOn),
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

  Future<void> _addToPlaylist(oaq.SongModel song) async {
    final playlists = await PlaylistRepository.instance.getAll();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(kSp * 2),
              child: GlassPanel(
                borderRadius: BorderRadius.circular(20),
                borderColor: Colors.white.withValues(alpha: 0.15),
                backdropBlurSigma: 0,
                backgroundColor: kColorGlassBlackTint,
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text(
                        'Add to Playlist',
                        style: TextStyle(
                          color: kColorOn,
                          fontSize: kTextLg,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (playlists.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'No playlists found',
                          style: TextStyle(color: kColorOn2),
                        ),
                      )
                    else
                      ...playlists.map(
                        (p) => ListTile(
                          leading: const Icon(
                            Icons.queue_music,
                            color: kColorOn2,
                          ),
                          title: Text(
                            p.name,
                            style: const TextStyle(color: kColorOn),
                          ),
                          subtitle: Text(
                            '${p.songCount} songs',
                            style: const TextStyle(color: kColorOn2),
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
        // NOTE: LibraryPage is already hosted inside the app-wide Scaffold
        // in `main.dart`, so we avoid a nested Scaffold here to keep it
        // visually consistent with Now Playing.
        return SafeArea(
          top: true,
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(kSp * 2, kSp, kSp * 2, 0),
                child: SizedBox(
                  height: 44,
                  child: NavigationToolbar(
                    centerMiddle: true,
                    middleSpacing: 0,
                    leading: const SizedBox.shrink(),
                    middle: const Text(
                      'Library',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Favorites Toggle
                        ValueListenableBuilder<List<String>>(
                          valueListenable:
                              PlayerController.ensure().favoritesNotifier,
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
                                        ? Colors.redAccent
                                        : kColorOn,
                              ),
                              onPressed:
                                  scan.isScanning
                                      ? null
                                      : () {
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
                          onPressed: scan.isScanning ? null : _showSortMenu,
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
                  padding: const EdgeInsets.fromLTRB(kSp * 2, kSp, kSp * 2, 0),
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
                          const SizedBox(width: kSp),
                          Text(
                            'Scanning… ${scan.phase.name}',
                            style: const TextStyle(
                              color: kColorOn2,
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
                  padding: const EdgeInsets.fromLTRB(kSp * 2, kSp, kSp * 2, 0),
                  child: GlassPanel(
                    useShader: false,
                    borderRadius: BorderRadius.circular(kRadius),
                    borderColor: Colors.redAccent.withValues(alpha: 0.35),
                    padding: const EdgeInsets.all(kSp),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.redAccent,
                          size: 18,
                        ),
                        const SizedBox(width: kSp),
                        Expanded(
                          child: Text(
                            'Scan failed. ${scan.lastError}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: kColorOn2,
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

              // Main Glass Surface (Search + List)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(kSp * 2, 0, kSp * 2, 0),
                  child: GlassPanel(
                    useShader: false,
                    borderRadius: BorderRadius.circular(18),
                    borderColor: Colors.white.withValues(alpha: 0.15),
                    backgroundColor: const Color(0x04FFFFFF),
                    boxShadow: const [],
                    padding: const EdgeInsets.all(kSp),
                    child: Column(
                      children: [
                        // Search Bar (match Now Playing chip-glass)
                        GlassPanel(
                          useShader: false,
                          borderRadius: BorderRadius.circular(999),
                          borderColor: Colors.white.withValues(alpha: 0.15),
                          backgroundColor: const Color(0x04FFFFFF),
                          boxShadow: const [],
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: TextField(
                            controller: _searchCtrl,
                            onChanged: _filterSongs,
                            style: const TextStyle(color: kColorOn),
                            decoration: const InputDecoration(
                              hintText: 'Search songs, artists…',
                              hintStyle: TextStyle(color: kColorOn2),
                              prefixIcon: Icon(
                                PhosphorIconsRegular.magnifyingGlass,
                                color: kColorOn2,
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

                        // Hairline divider under search
                        Container(
                          height: 1,
                          color: Colors.white.withValues(alpha: 0.08),
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
                                          color: kColorOn2,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          _showFavoritesOnly
                                              ? 'No favorites yet'
                                              : (_allSongs.isEmpty
                                                  ? 'No songs found'
                                                  : 'No matches'),
                                          style: const TextStyle(
                                            color: kColorOn2,
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
                                      bottom: kNavHeight + kSp,
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

                                      return Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () => _playNow(s),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                              vertical: 6,
                                            ),
                                            child: Row(
                                              children: [
                                                // Tiny selection accent
                                                SizedBox(
                                                  width: 4,
                                                  child: Align(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    child: AnimatedContainer(
                                                      duration: const Duration(
                                                        milliseconds: 160,
                                                      ),
                                                      width: 3,
                                                      height:
                                                          isPlaying ? 22 : 0,
                                                      decoration: BoxDecoration(
                                                        color: accentColor,
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              99,
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                // Artwork (minimal chrome)
                                                ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  child: SizedBox(
                                                    width: 44,
                                                    height: 44,
                                                    child: DecoratedBox(
                                                      decoration:
                                                          const BoxDecoration(
                                                            color: Color(
                                                              0x04FFFFFF,
                                                            ),
                                                          ),
                                                      child: ArtworkImage(
                                                        id: s.id,
                                                        type:
                                                            oaq
                                                                .ArtworkType
                                                                .AUDIO,
                                                        nullArtworkWidget:
                                                            const Icon(
                                                              Icons.music_note,
                                                              color: kColorOn2,
                                                            ),
                                                        artworkBorder:
                                                            BorderRadius.circular(
                                                              8,
                                                            ),
                                                        artworkFit:
                                                            BoxFit.cover,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),

                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        s.title,
                                                        maxLines: 1,
                                                        overflow:
                                                            TextOverflow
                                                                .ellipsis,
                                                        style: TextStyle(
                                                          color:
                                                              isPlaying
                                                                  ? accentColor
                                                                  : kColorOn,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        s.artist ?? '<unknown>',
                                                        maxLines: 1,
                                                        overflow:
                                                            TextOverflow
                                                                .ellipsis,
                                                        style: const TextStyle(
                                                          color: kColorOn2,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),

                                                PopupMenuButton<String>(
                                                  icon: const Icon(
                                                    Icons.more_vert,
                                                    color: kColorOn2,
                                                  ),
                                                  color: kColorCard,
                                                  onSelected: (value) {
                                                    switch (value) {
                                                      case 'play_next':
                                                        _playNext(s);
                                                        break;
                                                      case 'add_playlist':
                                                        _addToPlaylist(s);
                                                        break;
                                                      case 'rate':
                                                        _showRatingDialog(
                                                          s.id.toString(),
                                                        );
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
                                                                Icons
                                                                    .playlist_add,
                                                                color:
                                                                    kColorOn2,
                                                              ),
                                                              SizedBox(
                                                                width: 12,
                                                              ),
                                                              Text(
                                                                'Play Next',
                                                                style: TextStyle(
                                                                  color:
                                                                      kColorOn,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        const PopupMenuItem(
                                                          value: 'add_playlist',
                                                          child: Row(
                                                            children: [
                                                              Icon(
                                                                Icons
                                                                    .queue_music,
                                                                color:
                                                                    kColorOn2,
                                                              ),
                                                              SizedBox(
                                                                width: 12,
                                                              ),
                                                              Text(
                                                                'Add to Playlist',
                                                                style: TextStyle(
                                                                  color:
                                                                      kColorOn,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        const PopupMenuItem(
                                                          value: 'rate',
                                                          child: Row(
                                                            children: [
                                                              Icon(
                                                                Icons
                                                                    .star_outline,
                                                                color:
                                                                    kColorOn2,
                                                              ),
                                                              SizedBox(
                                                                width: 12,
                                                              ),
                                                              Text(
                                                                'Rate Song',
                                                                style: TextStyle(
                                                                  color:
                                                                      kColorOn,
                                                                ),
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
