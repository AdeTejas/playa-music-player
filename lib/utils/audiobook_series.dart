import 'package:on_audio_query/on_audio_query.dart' as oaq;

import 'content_mode.dart';

/// Best-effort chapter / series grouping for audiobooks.
///
/// Limits (also documented in docs/AUDIOBOOK_CHAPTERS.md):
/// - Embedded CUE sheets and MP4 `chpl`/`©chap` chapter atoms are **not**
///   parsed yet — only multi-file libraries and `Chapter N` title patterns.
/// - Series identity reuses [ContentModeDetector.seriesKeyForSong].
class AudiobookChapterRef {
  final oaq.SongModel song;
  final int? chapterNumber;
  final String label;

  const AudiobookChapterRef({
    required this.song,
    required this.label,
    this.chapterNumber,
  });
}

class AudiobookSeriesGroup {
  final String seriesKey;
  final String title;
  final String? artist;
  final List<AudiobookChapterRef> chapters;

  const AudiobookSeriesGroup({
    required this.seriesKey,
    required this.title,
    required this.chapters,
    this.artist,
  });

  int get chapterCount => chapters.length;
}

final RegExp _chapterPattern = RegExp(
  r'(?:chapter|ch\.?|part|pt\.?|disc|cd)\s*(\d{1,3})\b',
  caseSensitive: false,
);

int? parseChapterNumber(String title) {
  final m = _chapterPattern.firstMatch(title);
  if (m == null) return null;
  return int.tryParse(m.group(1)!);
}

String chapterLabelFor(oaq.SongModel song) {
  final n = parseChapterNumber(song.title);
  if (n != null) return 'Chapter $n';
  return song.title.trim().isEmpty ? 'Chapter' : song.title.trim();
}

List<AudiobookSeriesGroup> groupAudiobookSeries(
  List<oaq.SongModel> songs, {
  int minChapters = 2,
}) {
  final buckets = <String, List<oaq.SongModel>>{};
  for (final song in songs) {
    if (ContentModeDetector.detectFromSong(song) != ContentMode.audiobook) {
      continue;
    }
    final key = ContentModeDetector.seriesKeyForSong(song);
    if (key.isEmpty) continue;
    buckets.putIfAbsent(key, () => []).add(song);
  }

  final groups = <AudiobookSeriesGroup>[];
  for (final entry in buckets.entries) {
    final chapters = entry.value.map((s) {
      return AudiobookChapterRef(
        song: s,
        chapterNumber: parseChapterNumber(s.title),
        label: chapterLabelFor(s),
      );
    }).toList();

    chapters.sort((a, b) {
      final an = a.chapterNumber;
      final bn = b.chapterNumber;
      if (an != null && bn != null) return an.compareTo(bn);
      if (an != null) return -1;
      if (bn != null) return 1;
      return a.song.title.toLowerCase().compareTo(b.song.title.toLowerCase());
    });

    if (chapters.length < minChapters) continue;

    final first = chapters.first.song;
    final album = (first.album ?? '').trim();
    final title = (album.isNotEmpty &&
            album.toLowerCase() != 'unknown album' &&
            album.toLowerCase() != 'album unknown')
        ? album
        : first.title;
    final artist = (first.artist ?? '').trim();

    groups.add(
      AudiobookSeriesGroup(
        seriesKey: entry.key,
        title: title,
        artist: artist.isEmpty ? null : artist,
        chapters: chapters,
      ),
    );
  }

  groups.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return groups;
}
