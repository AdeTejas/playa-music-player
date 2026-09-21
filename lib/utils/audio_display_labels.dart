import 'package:path/path.dart' as p;

/// UI-facing title/artist cleanup for tracks with weak or missing tags.
class AudioDisplayLabels {
  AudioDisplayLabels._();

  static const String _unknownArtistLiterals = 'unknown artist|unknown|various artists|<unknown>';
  static const String _unknownAlbumLiterals = 'unknown album|unknown|<unknown>';

  static bool isUnknownArtist(String? artist) {
    final v = (artist ?? '').trim();
    if (v.isEmpty) return true;
    return RegExp('^(?:$_unknownArtistLiterals)\$', caseSensitive: false)
        .hasMatch(v);
  }

  static bool isUnknownAlbum(String? album) {
    final v = (album ?? '').trim();
    if (v.isEmpty) return true;
    return RegExp('^(?:$_unknownAlbumLiterals)\$', caseSensitive: false)
        .hasMatch(v);
  }

  static bool looksLikeFilenameTitle(String? title, String? path) {
    if (title == null || title.trim().isEmpty) return true;
    if (path == null || path.isEmpty) return false;
    final base = p.basenameWithoutExtension(path);
    return title.trim().toLowerCase() == base.trim().toLowerCase();
  }

  /// Prefer embedded title; else parse `Artist - Title` from the basename.
  static String displayTitle({
    required String? title,
    String? path,
    String? artist,
  }) {
    final raw = (title ?? '').trim();
    if (raw.isNotEmpty && !looksLikeFilenameTitle(raw, path)) {
      return raw;
    }

    final fromName = _parseBasename(path);
    if (fromName.title != null && fromName.title!.isNotEmpty) {
      return fromName.title!;
    }

    if (raw.isNotEmpty) return _prettifyBasename(raw);
    if (path != null && path.isNotEmpty) {
      return _prettifyBasename(p.basenameWithoutExtension(path));
    }
    return 'Untitled';
  }

  /// Soft artist label — empty string when unknown so UI can omit clutter.
  static String displayArtist({
    required String? artist,
    String? path,
    String? title,
  }) {
    if (!isUnknownArtist(artist)) return artist!.trim();

    final fromName = _parseBasename(path);
    if (fromName.artist != null && fromName.artist!.isNotEmpty) {
      return fromName.artist!;
    }

    // Last resort: avoid shouting "Unknown Artist" in the Now Playing chrome.
    return '';
  }

  /// Artist line for list tiles where an empty subtitle looks broken.
  static String displayArtistOrFallback({
    required String? artist,
    String? path,
    String fallback = 'Artist unknown',
  }) {
    final label = displayArtist(artist: artist, path: path);
    return label.isEmpty ? fallback : label;
  }

  static ({String? artist, String? title}) _parseBasename(String? path) {
    if (path == null || path.isEmpty) {
      return (artist: null, title: null);
    }
    final base = p.basenameWithoutExtension(path).trim();
    if (base.isEmpty) return (artist: null, title: null);

    // Common rip patterns: "01 - Artist - Title", "Artist - Title"
    var cleaned = base.replaceFirst(RegExp(r'^\d{1,3}[\s._-]+'), '');
    final parts = cleaned.split(RegExp(r'\s[-–—]\s'));
    if (parts.length >= 2) {
      final maybeArtist = parts.first.trim();
      final maybeTitle = parts.sublist(1).join(' - ').trim();
      if (maybeArtist.isNotEmpty && maybeTitle.isNotEmpty) {
        return (artist: maybeArtist, title: maybeTitle);
      }
    }
    return (artist: null, title: _prettifyBasename(cleaned));
  }

  static String _prettifyBasename(String raw) {
    return raw
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
