import 'dart:io';

import 'package:on_audio_query/on_audio_query.dart';

import 'audio_display_labels.dart';
import 'audio_tag_reader.dart';

/// Strengthens weak MediaStore / filename titles after an [OnAudioQuery] scan.
class SongTagEnricher {
  SongTagEnricher._();

  static Future<List<SongModel>> enrichWeakTags(
    List<SongModel> songs, {
    int maxReads = 400,
  }) async {
    if (songs.isEmpty) return songs;

    final out = <SongModel>[];
    var reads = 0;

    for (final song in songs) {
      final path = song.data;
      final needsTitle = AudioDisplayLabels.looksLikeFilenameTitle(
            song.title,
            path,
          ) ||
          song.title.trim().isEmpty;
      final needsArtist = AudioDisplayLabels.isUnknownArtist(song.artist);
      final needsAlbum = AudioDisplayLabels.isUnknownAlbum(song.album);

      if (!needsTitle && !needsArtist && !needsAlbum) {
        out.add(song);
        continue;
      }

      if (!_isReadableFilePath(path) || reads >= maxReads) {
        out.add(_withDisplayFallbacks(song));
        continue;
      }

      reads++;
      try {
        final tags = await AudioTagReader.readFromFilePath(path);
        out.add(
          _mergeTags(
            song,
            title: tags.title,
            artist: tags.artist,
            album: tags.album,
            durationMs: tags.durationMs,
          ),
        );
      } catch (_) {
        out.add(_withDisplayFallbacks(song));
      }
    }

    return out;
  }

  static bool _isReadableFilePath(String path) {
    if (path.isEmpty) return false;
    if (path.startsWith('content://')) return false;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return false;
    }
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  static SongModel _withDisplayFallbacks(SongModel song) {
    final title = AudioDisplayLabels.displayTitle(
      title: song.title,
      path: song.data,
      artist: song.artist,
    );
    final artist = AudioDisplayLabels.displayArtistOrFallback(
      artist: song.artist,
      path: song.data,
    );
    final album = AudioDisplayLabels.isUnknownAlbum(song.album)
        ? 'Album unknown'
        : (song.album ?? 'Album unknown');
    return _cloneSong(
      song,
      title: title,
      artist: artist,
      album: album,
    );
  }

  static SongModel _mergeTags(
    SongModel song, {
    String? title,
    String? artist,
    String? album,
    int? durationMs,
  }) {
    final nextTitle = (title != null && title.trim().isNotEmpty)
        ? title.trim()
        : AudioDisplayLabels.displayTitle(
            title: song.title,
            path: song.data,
            artist: song.artist,
          );
    final nextArtist = (artist != null && artist.trim().isNotEmpty)
        ? artist.trim()
        : AudioDisplayLabels.displayArtistOrFallback(
            artist: song.artist,
            path: song.data,
          );
    final nextAlbum = (album != null && album.trim().isNotEmpty)
        ? album.trim()
        : (AudioDisplayLabels.isUnknownAlbum(song.album)
            ? 'Album unknown'
            : (song.album ?? 'Album unknown'));
    final nextDuration =
        (durationMs != null && durationMs > 0) ? durationMs : song.duration;

    return _cloneSong(
      song,
      title: nextTitle,
      artist: nextArtist,
      album: nextAlbum,
      duration: nextDuration,
    );
  }

  static SongModel _cloneSong(
    SongModel song, {
    required String title,
    required String artist,
    required String album,
    int? duration,
  }) {
    // Preserve identity fields used elsewhere (favorites, Neural Mix, resume).
    return SongModel({
      '_id': song.id,
      '_data': song.data,
      '_display_name': song.displayName,
      'title': title,
      'artist': artist,
      'album': album,
      'duration': duration ?? song.duration ?? 0,
      'is_music': true,
    });
  }
}
