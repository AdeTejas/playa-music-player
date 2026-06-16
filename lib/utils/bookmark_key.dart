import 'dart:io';

/// Stable per-track key for bookmark storage.
class BookmarkKey {
  BookmarkKey._();

  static String canonical(String raw) {
    var path = raw.trim();
    if (path.isEmpty) return '';

    if (path.startsWith('file://')) {
      try {
        path = Uri.parse(path).toFilePath();
      } catch (_) {}
    }

    path = path.replaceAll('\\', '/');
    // Always lowercase for bookmark stability across different file providers/platforms
    return path.toLowerCase();
  }

  /// Primary storage key for the current track.
  static String primaryForTrack({
    String? bookmarkKey,
    String? path,
    Object? mediaId,
    String? itemId,
  }) {
    if (bookmarkKey != null && bookmarkKey.isNotEmpty) {
      return canonical(bookmarkKey);
    }
    if (path != null && path.isNotEmpty) {
      return canonical(path);
    }
    if (Platform.isAndroid && mediaId != null) {
      return 'media:$mediaId';
    }
    if (itemId != null && itemId.isNotEmpty) {
      return canonical(itemId);
    }
    return '';
  }

  /// Every key that might hold bookmarks for this track (legacy paths, media id, etc.).
  static List<String> aliasesForTrack({
    String? bookmarkKey,
    String? path,
    Object? mediaId,
    String? itemId,
  }) {
    final keys = <String>{};

    void add(String? raw) {
      if (raw == null || raw.isEmpty) return;
      final key = canonical(raw);
      if (key.isNotEmpty) keys.add(key);
    }

    add(bookmarkKey);
    add(path);
    add(itemId);
    if (mediaId != null) keys.add('media:$mediaId');

    final primary = primaryForTrack(
      bookmarkKey: bookmarkKey,
      path: path,
      mediaId: mediaId,
      itemId: itemId,
    );
    if (primary.isNotEmpty) keys.add(primary);

    return keys.toList(growable: false);
  }
}