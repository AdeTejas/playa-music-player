import 'package:uuid/uuid.dart';
import '../models/playlist.dart';
import '../services/database_service.dart';

class PlaylistRepository {
  static PlaylistRepository? _instance;
  static PlaylistRepository get instance =>
      _instance ??= PlaylistRepository._();
  PlaylistRepository._();

  final _uuid = const Uuid();

  Future<List<Playlist>> getAll() async {
    return await DatabaseService.instance.getAllPlaylists();
  }

  Future<void> create(String name, {String? description}) async {
    final playlist = Playlist(
      id: _uuid.v4(),
      name: name,
      description: description,
    );
    await DatabaseService.instance.createPlaylist(playlist);
  }

  Future<Playlist> createWithSongs(
    String name,
    List<String> songIds, {
    String? description,
  }) async {
    final playlist = Playlist(
      id: _uuid.v4(),
      name: name,
      description: description,
      songIds: List<String>.from(songIds),
    );
    await DatabaseService.instance.createPlaylist(playlist);
    return playlist;
  }

  Future<void> delete(String id) async {
    await DatabaseService.instance.deletePlaylist(id);
  }

  Future<void> addSong(String playlistId, String songId) async {
    await DatabaseService.instance.addToPlaylist(playlistId, songId);
  }

  Future<void> removeSong(String playlistId, String songId) async {
    await DatabaseService.instance.removeFromPlaylist(playlistId, songId);
  }
}
