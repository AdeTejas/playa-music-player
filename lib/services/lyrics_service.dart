import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../repositories/song_repository.dart';

class LyricsService {
  LyricsService._();
  static final instance = LyricsService._();

  Future<String?> getLyricsForSong({
    required String songId,
    required String artist,
    required String title,
    Duration? duration,
  }) async {
    if (songId.isEmpty) return getLyrics(artist, title, duration: duration);

    try {
      final meta = await SongRepository.instance.getMetadata(songId);
      final cached = meta?.lyrics;
      if (cached != null && cached.trim().isNotEmpty) {
        return cached;
      }
    } catch (_) {
      // ignore caching failures
    }

    final fetched = await getLyrics(artist, title, duration: duration);
    if (fetched != null && fetched.trim().isNotEmpty) {
      try {
        await SongRepository.instance.saveLyrics(
          songId,
          fetched,
          source: 'lrclib',
        );
      } catch (_) {
        // ignore persistence failures
      }
    }
    return fetched;
  }

  Future<String?> getLyrics(
    String artist,
    String title, {
    Duration? duration,
  }) async {
    if (artist.isEmpty || title.isEmpty) return null;

    try {
      final queryParameters = {'artist_name': artist, 'track_name': title};
      if (duration != null) {
        queryParameters['duration'] = duration.inSeconds.toString();
      }

      final uri = Uri.https('lrclib.net', '/api/get', queryParameters);
      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Prefer synced lyrics, then plain lyrics
        return data['syncedLyrics'] as String? ??
            data['plainLyrics'] as String?;
      }
    } catch (e) {
      // Fail silently
    }

    return null;
  }
}
