import 'package:just_audio_background/just_audio_background.dart';
import 'package:on_audio_query/on_audio_query.dart' as oaq;

/// How Playa treats the current listening session in the UI.
enum ContentMode {
  /// Long-form / book-like content — audiobook controls are primary.
  audiobook,

  /// Music / short tracks — DJ and playlist tools are surfaced.
  music,
}

/// Library browse filter (single list, runtime classification).
enum LibraryBrowseFilter {
  all,
  music,
  audiobook;

  String get label => switch (this) {
    LibraryBrowseFilter.all => 'All',
    LibraryBrowseFilter.music => 'Music',
    LibraryBrowseFilter.audiobook => 'Audiobooks',
  };

  static LibraryBrowseFilter fromName(String? raw) {
    if (raw == null || raw.isEmpty) return LibraryBrowseFilter.all;
    for (final value in LibraryBrowseFilter.values) {
      if (value.name == raw) return value;
    }
    return LibraryBrowseFilter.all;
  }
}

/// Heuristics for hybrid audiobook-weighted playback.
class ContentModeDetector {
  ContentModeDetector._();

  static const int audiobookMinDurationMs = 45 * 60 * 1000;

  static const Set<String> audiobookExtensions = {
    'm4b',
    'aa',
    'aax',
    'opus',
  };

  static const Set<String> musicGenreHints = {
    'rock',
    'pop',
    'hip hop',
    'rap',
    'electronic',
    'dance',
    'metal',
    'punk',
    'jazz',
    'blues',
    'country',
    'r&b',
    'soul',
    'funk',
    'reggae',
    'classical',
    'soundtrack',
    'single',
  };

  static ContentMode detectFromMediaItem(MediaItem? item) {
    if (item == null) return ContentMode.audiobook;

    final path = (item.extras?['path'] as String?) ?? item.id;
    final durationMs = item.duration?.inMilliseconds ?? 0;
    final album = (item.album ?? '').trim().toLowerCase();
    final artist = (item.artist ?? '').trim().toLowerCase();
    final genre = (item.genre ?? '').trim().toLowerCase();

    if (_extensionOf(path) == 'm4b') return ContentMode.audiobook;
    if (durationMs >= audiobookMinDurationMs) return ContentMode.audiobook;

    if (album.contains('audiobook') ||
        album.contains('unabridged') ||
        album.contains('spoken word') ||
        artist.contains('narrator')) {
      return ContentMode.audiobook;
    }

    if (genre.isNotEmpty && musicGenreHints.any(genre.contains)) {
      return ContentMode.music;
    }

    if (durationMs > 0 && durationMs < 8 * 60 * 1000) {
      return ContentMode.music;
    }

    // Hybrid default: lean audiobook for ambiguous long-form content.
    if (durationMs >= 20 * 60 * 1000) return ContentMode.audiobook;

    return ContentMode.music;
  }

  static bool songMatchesBrowseFilter(
    oaq.SongModel song,
    LibraryBrowseFilter filter,
  ) {
    if (filter == LibraryBrowseFilter.all) return true;
    final mode = detectFromSong(song);
    return filter == LibraryBrowseFilter.audiobook
        ? mode == ContentMode.audiobook
        : mode == ContentMode.music;
  }

  static ContentMode detectFromSong(oaq.SongModel song) {
    final durationMs = song.duration ?? 0;
    final path = song.data;
    final album = (song.album ?? '').trim().toLowerCase();
    final artist = (song.artist ?? '').trim().toLowerCase();

    if (_extensionOf(path) == 'm4b') return ContentMode.audiobook;
    if (durationMs >= audiobookMinDurationMs) return ContentMode.audiobook;

    if (album.contains('audiobook') ||
        album.contains('unabridged') ||
        album.contains('spoken word') ||
        artist.contains('narrator')) {
      return ContentMode.audiobook;
    }

    if (durationMs > 0 && durationMs < 8 * 60 * 1000) {
      return ContentMode.music;
    }

    if (durationMs >= 20 * 60 * 1000) return ContentMode.audiobook;

    return ContentMode.music;
  }

  /// Stable key for multi-file books / series resume.
  static String seriesKeyForMediaItem(MediaItem? item) {
    if (item == null) return '';

    final album = (item.album ?? '').trim();
    if (album.isNotEmpty &&
        album.toLowerCase() != 'unknown album' &&
        album.toLowerCase() != 'unknown') {
      final artist = (item.artist ?? '').trim();
      if (artist.isNotEmpty &&
          artist.toLowerCase() != 'unknown artist' &&
          artist.toLowerCase() != 'unknown') {
        return '$artist::$album'.toLowerCase();
      }
      return album.toLowerCase();
    }

    final path = (item.extras?['path'] as String?) ?? item.id;
    final parent = _parentFolderKey(path);
    if (parent.isNotEmpty) return parent;

    return (item.title).trim().toLowerCase();
  }

  static String seriesKeyForSong(oaq.SongModel song) {
    final album = (song.album ?? '').trim();
    if (album.isNotEmpty &&
        album.toLowerCase() != 'unknown album' &&
        album.toLowerCase() != 'unknown') {
      final artist = (song.artist ?? '').trim();
      if (artist.isNotEmpty &&
          artist.toLowerCase() != 'unknown artist' &&
          artist.toLowerCase() != 'unknown') {
        return '$artist::$album'.toLowerCase();
      }
      return album.toLowerCase();
    }

    final parent = _parentFolderKey(song.data);
    if (parent.isNotEmpty) return parent;

    return song.title.trim().toLowerCase();
  }

  static String displayTitleForSeries(MediaItem item) {
    final album = (item.album ?? '').trim();
    if (album.isNotEmpty &&
        album.toLowerCase() != 'unknown album' &&
        album.toLowerCase() != 'unknown') {
      return album;
    }
    return item.title;
  }

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '';
    return path.substring(dot + 1).toLowerCase();
  }

  static String _parentFolderKey(String path) {
    try {
      final normalized = path.replaceAll('\\', '/');
      final idx = normalized.lastIndexOf('/');
      if (idx <= 0) return '';
      final parent = normalized.substring(0, idx);
      final name = parent.split('/').last.trim();
      if (name.isEmpty) return '';
      return 'folder::$name'.toLowerCase();
    } catch (_) {
      return '';
    }
  }
}