import '../models/song_metadata.dart';
import '../services/database_service.dart';

class SongRepository {
  static SongRepository? _instance;
  static SongRepository get instance => _instance ??= SongRepository._();
  SongRepository._();

  Future<SongMetadata?> getMetadata(String songId) async {
    return await DatabaseService.instance.getSongMetadata(songId);
  }

  Future<List<SongMetadata>> getAllMetadata() async {
    return await DatabaseService.instance.getAllSongMetadata();
  }

  Future<void> updateRating(String songId, int rating) async {
    await DatabaseService.instance.updateRating(songId, rating);
  }

  Future<void> saveLyrics(String songId, String lyrics, {String? source}) async {
    await DatabaseService.instance.saveLyrics(songId, lyrics, source: source);
  }

  Future<void> updateLastPlayed(String songId) async {
    await DatabaseService.instance.updateLastPlayed(songId);
  }

  Future<void> incrementPlayCount(String songId) async {
     await DatabaseService.instance.incrementPlayCount(songId);
  }

  Future<void> recordPlay(String songId) async {
    await DatabaseService.instance.incrementPlayCount(songId);
  }
}