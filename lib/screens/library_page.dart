import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart' as oaq;
import 'package:permission_handler/permission_handler.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../ui/tokens.dart';
import '../services/player_controller.dart';
import '../services/settings_service.dart';
import '../services/windows_audio_query.dart';
import '../repositories/song_repository.dart';
import '../widgets/star_rating.dart';
import 'settings_screen.dart';
import 'playlists_screen.dart';
import '../widgets/player_provider.dart';
import '../widgets/artwork_image.dart';
import '../utils/ui_utils.dart';
import '../repositories/playlist_repository.dart';

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
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    SettingsService.instance.addListener(_onSettingsChanged);
    _bootstrap();
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
             debugPrint('DEBUG: on_audio_query needs permission update. Calling permissionsRequest()...');
             try {
               // Call permissionsRequest to update internal state, but with timeout
               oaqStatus = await _query.permissionsRequest().timeout(const Duration(seconds: 2));
               debugPrint('DEBUG: permissionsRequest result: $oaqStatus');
             } catch (e) {
               debugPrint('DEBUG: permissionsRequest failed/timed out: $e');
             }
          }
        }

        debugPrint('DEBUG: Starting _loadSongs with timeout');
        await _loadSongs().timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            debugPrint('DEBUG: _loadSongs timed out');
            if (mounted) {
              setState(() => _loading = false);
              showToast(context, 'Song loading timed out. Try again.');
            }
          },
        );
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
    print('DEBUG: Requesting permissions...');
    if (Platform.isAndroid) {
      // Try audio permission first (Android 13+)
      Map<Permission, PermissionStatus> statuses = await [
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
            content: const Text('Storage/Audio permission is required to access music files'),
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
      final sortType = _getSortType(SettingsService.instance.librarySortType);
      final orderType = _getOrderType(SettingsService.instance.librarySortOrder);

      List<oaq.SongModel> songs;
      
      if (Platform.isWindows) {
        songs = await WindowsAudioQuery.instance.querySongs();
      } else {
        // Run query with timeout to prevent hanging
        songs = await _query
            .querySongs(
              sortType: sortType,
              orderType: orderType,
              uriType: oaq.UriType.EXTERNAL,
              ignoreCase: true,
            )
            .timeout(const Duration(seconds: 8));
      }
      
      if (!mounted) return;
      setState(() {
        _allSongs = songs.where((s) => (s.data).isNotEmpty).toList();
        _songs = List.from(_allSongs);
        _loading = false;
      });
      
      // Update PlayerController library cache
      PlayerController.ensure().updateLibrary(_allSongs);
      
      // Restore last played song
      PlayerController.ensure().restoreState(_songs);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showToast(
        context,
        "Couldn't read your audio library: ${e is TimeoutException ? 'Query timed out' : 'Check permissions'}",
      );
    }
  }

  void _filterSongs(String query) {
    setState(() {
      List<oaq.SongModel> filtered = _allSongs;
      
      // 1. Filter by Favorites
      if (_showFavoritesOnly) {
        final favs = PlayerController.ensure().favoritesNotifier.value;
        filtered = filtered.where((s) => favs.contains(s.id.toString())).toList();
      }

      // 2. Filter by Search Query
      if (query.isNotEmpty) {
        final q = query.toLowerCase();
        filtered = filtered.where((s) {
          return s.title.toLowerCase().contains(q) ||
                 (s.artist?.toLowerCase().contains(q) ?? false) ||
                 (s.album?.toLowerCase().contains(q) ?? false);
        }).toList();
      }
      
      _songs = filtered;
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
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Rate Song'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StarRating(
                rating: tempRating,
                size: 36,
                onRatingChanged: (r) => setState(() => tempRating = r),
              ),
              const SizedBox(height: 8),
              Text(
                tempRating == 0
                    ? 'No rating'
                    : '$tempRating star${tempRating > 1 ? "s" : ""}',
                style: const TextStyle(color: kColorOn2),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                await SongRepository.instance.updateRating(songId, tempRating);
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) setState(() {});
              },
              child: const Text('Save',
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSortMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: kColorSurface,
      builder: (context) => Container(
        padding: const EdgeInsets.all(kSp * 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sort Library', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                activeColor: kColorAppAccent,
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
                activeColor: kColorAppAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSortOption({required String label, required String value}) {
    final current = SettingsService.instance.librarySortType;
    return ListTile(
      title: Text(label, style: TextStyle(color: current == value ? kColorAppAccent : kColorOn)),
      trailing: current == value ? const Icon(Icons.check, color: kColorAppAccent) : null,
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

  oaq.SongSortType _getSortType(String type) {
    switch (type) {
      case 'TITLE': return oaq.SongSortType.TITLE;
      case 'ARTIST': return oaq.SongSortType.ARTIST;
      case 'ALBUM': return oaq.SongSortType.ALBUM;
      case 'DATE_ADDED': return oaq.SongSortType.DATE_ADDED;
      default: return oaq.SongSortType.DATE_ADDED;
    }
  }

  oaq.OrderType _getOrderType(int order) {
    return order == 0 ? oaq.OrderType.ASC_OR_SMALLER : oaq.OrderType.DESC_OR_GREATER;
  }

  Future<void> _addToPlaylist(oaq.SongModel song) async {
    final playlists = await PlaylistRepository.instance.getAll();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: kColorCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
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
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (playlists.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No playlists found', style: TextStyle(color: kColorOn2)),
              )
            else
              ...playlists.map((p) => ListTile(
                leading: const Icon(Icons.queue_music, color: kColorOn2),
                title: Text(p.name, style: const TextStyle(color: kColorOn)),
                subtitle: Text('${p.songCount} songs', style: const TextStyle(color: kColorOn2)),
                onTap: () async {
                  await PlaylistRepository.instance.addSong(p.id, song.id.toString());
                  if (context.mounted) {
                    Navigator.pop(context);
                    showToast(context, 'Added to "${p.name}"');
                  }
                },
              )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = PlayerProvider.of(context);
    final currentSongId = player.currentMediaItem?.id;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Library'),
        actions: [
          // Favorites Toggle
          ValueListenableBuilder<List<String>>(
            valueListenable: PlayerController.ensure().favoritesNotifier,
            builder: (context, favs, _) {
              return IconButton(
                tooltip: _showFavoritesOnly ? 'Show All' : 'Show Favorites',
                icon: Icon(
                  _showFavoritesOnly ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
                  color: _showFavoritesOnly ? Colors.redAccent : kColorOn,
                ),
                onPressed: () {
                  setState(() {
                    _showFavoritesOnly = !_showFavoritesOnly;
                    _filterSongs(_searchCtrl.text);
                  });
                },
              );
            },
          ),
          IconButton(
            tooltip: 'Playlists',
            icon: const Icon(PhosphorIconsBold.playlist),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PlaylistsScreen(),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Sort',
            icon: const Icon(PhosphorIconsRegular.slidersHorizontal),
            onPressed: _showSortMenu,
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(PhosphorIconsBold.gear),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Glass Background
          Positioned.fill(
            child: SettingsService.instance.highQualityBlur
                ? ClipRect(
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        color: kColorSurface.withValues(alpha: 0.3),
                      ),
                    ),
                  )
                : Container(
                    color: kColorBg.withValues(alpha: 0.9),
                  ),
          ),
          Column(
            children: [
              // Search Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: kSp * 2, vertical: kSp),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _filterSongs,
                  style: const TextStyle(color: kColorOn),
                  decoration: InputDecoration(
                    hintText: 'Search songs, artists...',
                    hintStyle: const TextStyle(color: kColorOn2),
                    prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass, color: kColorOn2),
                    filled: true,
                    fillColor: kColorCard.withValues(alpha: 0.5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(kRadius),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: kSp * 2),
                  ),
                ),
              ),

              // Song List
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: kColorAppAccent))
                    : _songs.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _showFavoritesOnly ? PhosphorIconsRegular.heartBreak : PhosphorIconsRegular.musicNotes,
                                  size: 64, 
                                  color: kColorOn2
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _showFavoritesOnly 
                                      ? 'No favorites yet' 
                                      : (_allSongs.isEmpty ? 'No songs found' : 'No matches'),
                                  style: const TextStyle(color: kColorOn2, fontSize: 16),
                                ),
                                if (_allSongs.isEmpty && !_showFavoritesOnly)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 16),
                                    child: TextButton(
                                      onPressed: _loadSongs,
                                      child: const Text('Refresh Library'),
                                    ),
                                  ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: kNavHeight + kSp * 2),
                            itemCount: _songs.length,
                            itemBuilder: (context, index) {
                              final s = _songs[index];
                              final isPlaying = currentSongId == s.id.toString();
                              
                              return ListTile(
                                tileColor: Colors.transparent,
                                contentPadding: const EdgeInsets.symmetric(horizontal: kSp * 2, vertical: 4),
                                leading: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: kColorCard.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: ArtworkImage(
                                    id: s.id,
                                    type: oaq.ArtworkType.AUDIO,
                                    nullArtworkWidget: const Icon(Icons.music_note, color: kColorOn2),
                                    artworkBorder: BorderRadius.circular(8),
                                    artworkFit: BoxFit.cover,
                                  ),
                                ),
                                title: Text(
                                  s.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isPlaying ? kColorAppAccent : kColorOn,
                                    fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                subtitle: Text(
                                  s.artist ?? '<unknown>',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: kColorOn2, fontSize: 12),
                            ),
                            trailing: PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert, color: kColorOn2),
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
                                    _showRatingDialog(s.id.toString());
                                    break;
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'play_next',
                                  child: Row(
                                    children: [
                                      Icon(Icons.playlist_add, color: kColorOn2),
                                      SizedBox(width: 12),
                                      Text('Play Next', style: TextStyle(color: kColorOn)),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'add_playlist',
                                  child: Row(
                                    children: [
                                      Icon(Icons.queue_music, color: kColorOn2),
                                      SizedBox(width: 12),
                                      Text('Add to Playlist', style: TextStyle(color: kColorOn)),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'rate',
                                  child: Row(
                                    children: [
                                      Icon(Icons.star_outline, color: kColorOn2),
                                      SizedBox(width: 12),
                                      Text('Rate Song', style: TextStyle(color: kColorOn)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            onTap: () => _playNow(s),
                          );
                        },
                      ),
          ),
        ],
      ),
        ],
      ),
    );
  }
}
