import '../utils/content_mode.dart';

class ListeningProgress {
  final String seriesKey;
  final String title;
  final String? artist;
  final String lastSongPath;
  final int? lastMediaId;
  final int positionMs;
  final DateTime updatedAt;
  final ContentMode contentMode;

  const ListeningProgress({
    required this.seriesKey,
    required this.title,
    this.artist,
    required this.lastSongPath,
    this.lastMediaId,
    required this.positionMs,
    required this.updatedAt,
    this.contentMode = ContentMode.audiobook,
  });

  ListeningProgress copyWith({
    String? title,
    String? artist,
    String? lastSongPath,
    int? lastMediaId,
    int? positionMs,
    DateTime? updatedAt,
    ContentMode? contentMode,
  }) {
    return ListeningProgress(
      seriesKey: seriesKey,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      lastSongPath: lastSongPath ?? this.lastSongPath,
      lastMediaId: lastMediaId ?? this.lastMediaId,
      positionMs: positionMs ?? this.positionMs,
      updatedAt: updatedAt ?? this.updatedAt,
      contentMode: contentMode ?? this.contentMode,
    );
  }
}