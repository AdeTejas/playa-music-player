import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class LyricsService {
  LyricsService._();
  static final instance = LyricsService._();

  Future<String?> getLyrics(String artist, String title, {Duration? duration}) async {
    if (artist.isEmpty || title.isEmpty) return null;

    try {
      final queryParameters = {
        'artist_name': artist,
        'track_name': title,
      };
      if (duration != null) {
        queryParameters['duration'] = duration.inSeconds.toString();
      }

      final uri = Uri.https('lrclib.net', '/api/get', queryParameters);
      final response = await http.get(uri).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Prefer synced lyrics, then plain lyrics
        return data['syncedLyrics'] as String? ?? data['plainLyrics'] as String?;
      }
    } catch (e) {
      // Fail silently
    }
    
    return null;
  }
}
