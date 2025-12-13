import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../models/playlist.dart';
import '../repositories/playlist_repository.dart';
import '../services/player_controller.dart';
import '../ui/tokens.dart';
import '../ui/glass_panel.dart';
import '../widgets/artwork_image.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final Playlist playlist;
  const PlaylistDetailScreen({required this.playlist, super.key});

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  final _query = OnAudioQuery();
  final _repo = PlaylistRepository.instance;
  List<SongModel> _songs = [];
  bool _loading = true;
  late Playlist _currentPlaylist;

  @override
  void initState() {
    super.initState();
    _currentPlaylist = widget.playlist;
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    // Refresh playlist data first
    final allPlaylists = await _repo.getAll();
    try {
      _currentPlaylist = allPlaylists.firstWhere(
        (p) => p.id == widget.playlist.id,
      );
    } catch (_) {
      // Playlist might have been deleted
      if (mounted) Navigator.pop(context);
      return;
    }

    if (_currentPlaylist.songIds.isEmpty) {
      if (mounted) {
        setState(() {
          _songs = [];
          _loading = false;
        });
      }
      return;
    }

    // Fetch all songs and filter (inefficient but simple for local files)
    // Ideally we'd query by ID list if supported
    final allSongs = await _query.querySongs(
      sortType: SongSortType.DATE_ADDED,
      orderType: OrderType.DESC_OR_GREATER,
      uriType: UriType.EXTERNAL,
    );

    final songMap = {for (var s in allSongs) s.id.toString(): s};
    final List<SongModel> resolvedSongs = [];

    for (final id in _currentPlaylist.songIds) {
      if (songMap.containsKey(id)) {
        resolvedSongs.add(songMap[id]!);
      }
    }

    if (mounted) {
      setState(() {
        _songs = resolvedSongs;
        _loading = false;
      });
    }
  }

  Future<void> _removeSong(SongModel song) async {
    await _repo.removeSong(_currentPlaylist.id, song.id.toString());
    _loadSongs();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Removed "${song.title}"')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(_currentPlaylist.name),
        actions: [
          IconButton(
            icon: const Icon(PhosphorIconsRegular.play),
            onPressed:
                _songs.isEmpty
                    ? null
                    : () {
                      PlayerController.ensure().replaceQueue(
                        _songs,
                        queueContextType: 'playlist',
                        queueContextId: _currentPlaylist.id,
                      );
                    },
          ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : _songs.isEmpty
              ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      PhosphorIconsRegular.musicNotes,
                      size: 64,
                      color: kColorOn2,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'No songs yet',
                      style: TextStyle(color: kColorOn2, fontSize: 18),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Add songs from your Library',
                      style: TextStyle(color: Colors.white38),
                    ),
                  ],
                ),
              )
              : ListView.builder(
                itemCount: _songs.length,
                itemBuilder: (context, index) {
                  final song = _songs[index];
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: GlassPanel(
                      useShader: false,
                      borderRadius: BorderRadius.circular(14),
                      borderColor: Colors.white.withValues(alpha: 0.15),
                      child: Material(
                        color: Colors.transparent,
                        child: ListTile(
                          leading: ArtworkImage(
                            id: song.id,
                            type: ArtworkType.AUDIO,
                            nullArtworkWidget: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.12),
                                ),
                              ),
                              child: const Icon(
                                Icons.music_note,
                                color: kColorOn2,
                              ),
                            ),
                          ),
                          title: Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: kColorOn),
                          ),
                          subtitle: Text(
                            song.artist ?? 'Unknown',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: kColorOn2),
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              color: Colors.white38,
                            ),
                            onPressed: () => _removeSong(song),
                          ),
                          onTap: () {
                            PlayerController.ensure().replaceQueue(
                              _songs,
                              initialIndex: index,
                              queueContextType: 'playlist',
                              queueContextId: _currentPlaylist.id,
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              ),
    );
  }
}
