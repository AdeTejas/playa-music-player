import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../repositories/song_repository.dart';
import '../services/player_controller.dart';
import '../ui/tokens.dart';
import '../widgets/artwork_image.dart';

enum SmartPlaylistType {
  heavyRotation,
  forgottenFavorites,
  recentlyAdded,
}

class SmartPlaylistScreen extends StatefulWidget {
  final SmartPlaylistType type;
  const SmartPlaylistScreen({required this.type, super.key});

  @override
  State<SmartPlaylistScreen> createState() => _SmartPlaylistScreenState();
}

class _SmartPlaylistScreenState extends State<SmartPlaylistScreen> {
  final _query = OnAudioQuery();
  List<SongModel> _songs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  String get _title {
    switch (widget.type) {
      case SmartPlaylistType.heavyRotation:
        return 'Heavy Rotation';
      case SmartPlaylistType.forgottenFavorites:
        return 'Forgotten Favorites';
      case SmartPlaylistType.recentlyAdded:
        return 'Recently Added';
    }
  }

  Future<void> _loadSongs() async {
    final allSongs = await _query.querySongs(
      sortType: SongSortType.DATE_ADDED,
      orderType: OrderType.DESC_OR_GREATER,
      uriType: UriType.EXTERNAL,
    );

    List<SongModel> filtered = [];
    final repo = SongRepository.instance;

    switch (widget.type) {
      case SmartPlaylistType.recentlyAdded:
        // Already sorted by query, just take top 50
        filtered = allSongs.take(50).toList();
        break;

      case SmartPlaylistType.heavyRotation:
        final allMeta = await repo.getAllMetadata();
        final metaMap = {for (var m in allMeta) m.id: m};

        allSongs.sort((a, b) {
          final countA = metaMap[a.id.toString()]?.playCount ?? 0;
          final countB = metaMap[b.id.toString()]?.playCount ?? 0;
          return countB.compareTo(countA); // Descending
        });
        
        filtered = allSongs
            .where((s) => (metaMap[s.id.toString()]?.playCount ?? 0) > 0)
            .take(50)
            .toList();
        break;

      case SmartPlaylistType.forgottenFavorites:
        final allMeta = await repo.getAllMetadata();
        final metaMap = {for (var m in allMeta) m.id: m};
        final now = DateTime.now();
        final monthAgo = now.subtract(const Duration(days: 30));
        
        filtered = allSongs.where((s) {
          final meta = metaMap[s.id.toString()];
          if (meta == null) return false;
          
          final count = meta.playCount;
          final lastPlayed = meta.lastPlayed;
          
          // Played at least 3 times, but not in the last 30 days
          return count > 2 && 
                 lastPlayed != null && 
                 lastPlayed.isBefore(monthAgo);
        }).toList();
        break;
    }

    if (mounted) {
      setState(() {
        _songs = filtered;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kColorBg,
      appBar: AppBar(
        title: Text(_title),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _songs.isEmpty
              ? Center(
                  child: Text(
                    'No songs found for this criteria',
                    style: TextStyle(color: kColorOn2),
                  ),
                )
              : ListView.builder(
                  itemCount: _songs.length,
                  itemBuilder: (context, index) {
                    final song = _songs[index];
                    return ListTile(
                      leading: ArtworkImage(
                        id: song.id,
                        type: ArtworkType.AUDIO,
                        nullArtworkWidget: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: kColorCard,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(Icons.music_note, color: kColorOn2),
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
                      onTap: () {
                        PlayerController.ensure().replaceQueue(_songs, initialIndex: index);
                      },
                    );
                  },
                ),
    );
  }
}
