import '../models/listening_progress.dart';
import '../services/database_service.dart';
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
}