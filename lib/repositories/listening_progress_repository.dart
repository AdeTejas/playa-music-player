import 'package:on_audio_query/on_audio_query.dart' as oaq;

import '../models/listening_progress.dart';
import '../services/database_service.dart';
import '../utils/bookmark_key.dart';
import '../utils/content_mode.dart';

class ListeningProgressRepository {
  ListeningProgressRepository._();
  static ListeningProgressRepository? _instance;
  static ListeningProgressRepository get instance =>
      _instance ??= ListeningProgressRepository._();

  Future<void> upsert(ListeningProgress progress) async {
    await DatabaseService.instance.upsertListeningProgress(progress);
  }

  Future<ListeningProgress?> getBySeriesKey(String seriesKey) async {
    return DatabaseService.instance.getListeningProgress(seriesKey);
  }

  Future<List<ListeningProgress>> getRecent({int limit = 8}) async {
    return DatabaseService.instance.getRecentListeningProgress(limit: limit);
  }

  Future<void> delete(String seriesKey) async {
    await DatabaseService.instance.deleteListeningProgress(seriesKey);
  }

  Future<void> recordFromPlayback({
    required String seriesKey,
    required String title,
    String? artist,
    required String songPath,
    int? mediaId,
    required int positionMs,
    required ContentMode contentMode,
  }) async {
    if (seriesKey.isEmpty || songPath.isEmpty) return;

    await upsert(
      ListeningProgress(
        seriesKey: seriesKey,
        title: title,
        artist: artist,
        lastSongPath: songPath,
        lastMediaId: mediaId,
        positionMs: positionMs,
        updatedAt: DateTime.now(),
        contentMode: contentMode,
      ),
    );
  }

  /// Index of the last-played file inside a multi-chapter series queue.
  static int resolveSeriesIndex(
    List<oaq.SongModel> seriesSongs,
    ListeningProgress progress,
  ) {
    if (seriesSongs.isEmpty) return 0;

    final canonical = BookmarkKey.canonical(progress.lastSongPath);
    var index = seriesSongs.indexWhere(
      (s) => BookmarkKey.canonical(s.data) == canonical,
    );
    if (index >= 0) return index;

    if (progress.lastMediaId != null) {
      index = seriesSongs.indexWhere((s) => s.id == progress.lastMediaId);
      if (index >= 0) return index;
    }

    return 0;
  }

  /// Single-track fallback when the series only has one file in the library.
  static oaq.SongModel? resolveSingleTrack(
    List<oaq.SongModel> library,
    ListeningProgress progress,
  ) {
    final canonical = BookmarkKey.canonical(progress.lastSongPath);
    for (final song in library) {
      if (BookmarkKey.canonical(song.data) == canonical) return song;
    }

    if (progress.lastMediaId != null) {
      for (final song in library) {
        if (song.id == progress.lastMediaId) return song;
      }
    }

    return null;
  }

  /// Track duration for progress UI (null if the file is not in the library).
  static int? durationMsForProgress(
    ListeningProgress progress,
    List<oaq.SongModel> library,
  ) {
    final canonical = BookmarkKey.canonical(progress.lastSongPath);
    for (final song in library) {
      if (BookmarkKey.canonical(song.data) == canonical) {
        return song.duration;
      }
    }

    if (progress.lastMediaId != null) {
      for (final song in library) {
        if (song.id == progress.lastMediaId) return song.duration;
      }
    }

    return null;
  }
}