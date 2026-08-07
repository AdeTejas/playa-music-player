import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../models/playlist.dart';
import '../repositories/playlist_repository.dart';
import '../services/player_controller.dart';
import '../design/design_system.dart';
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
    final allPlaylists = await _repo.getAll();
    try {
      _currentPlaylist = allPlaylists.firstWhere(
        (p) => p.id == widget.playlist.id,
      );
    } catch (_) {
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
      appBar: PlayaAppBar(
        title: _currentPlaylist.name,
        actions: [
          IconButton(
            tooltip: 'Play',
            icon: const Icon(PhosphorIconsRegular.play),
            onPressed:
                _songs.isEmpty
                    ? null
                    : () {
                      HapticFeedback.mediumImpact();
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
                      color: PlayaColors.onSurfaceVariant,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'No songs yet',
                      style: TextStyle(color: PlayaColors.onSurfaceVariant, fontSize: 18),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Add songs from your Library',
                      style: TextStyle(color: PlayaColors.onSurfaceVariant),
                    ),
                  ],
                ),
              )
              : ListView.builder(
                itemCount: _songs.length,
                padding: const EdgeInsets.symmetric(horizontal: PlayaSpacing.xs),
                itemBuilder: (context, index) {
                  final song = _songs[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: PlayaSpacing.xs),
                    child: PlayaCard(
                      useStrongVariant: true,
                      useMatteVariant: true,
                      padding: EdgeInsets.zero,
                      borderRadius: BorderRadius.circular(PlayaRadii.sm),
                      child: ListTile(
                        leading: ArtworkImage(
                          id: song.id,
                          type: ArtworkType.AUDIO,
                          nullArtworkWidget: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: PlayaColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(PlayaRadii.xs),
                              border: Border.all(
                                color: PlayaColors.borderSubtle,
                              ),
                            ),
                            child: const Icon(
                              PhosphorIconsRegular.musicNote,
                              color: PlayaColors.onSurfaceVariant,
                            ),
                          ),
                        ),
                        title: Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: PlayaColors.onSurface, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          song.artist ?? 'Unknown',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: PlayaColors.onSurfaceVariant, fontSize: 11),
                        ),
                        trailing: IconButton(
                          tooltip: 'Remove from playlist',
                          icon: const Icon(
                            PhosphorIconsRegular.minusCircle,
                            color: PlayaColors.onSurfaceVariant,
                            size: 20,
                          ),
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            _removeSong(song);
                          },
                        ),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          PlayerController.ensure().replaceQueue(
                            _songs,
                            initialIndex: index,
                            queueContextType: 'playlist',
                            queueContextId: _currentPlaylist.id,
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
    );
  }
}
