import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:playa_clean/utils/audiobook_series.dart';

SongModel song({
  required String path,
  required String title,
  String? artist,
  String? album,
  int durationMs = 60 * 60 * 1000,
}) {
  return SongModel({
    '_id': path.hashCode,
    '_data': path,
    '_display_name': path.split('/').last,
    'title': title,
    'artist': artist ?? 'Author',
    'album': album ?? 'The Book',
    'duration': durationMs,
    'is_music': true,
  });
}

void main() {
  test('parseChapterNumber understands common patterns', () {
    expect(parseChapterNumber('Chapter 12 - Arrival'), 12);
    expect(parseChapterNumber('Ch. 3'), 3);
    expect(parseChapterNumber('Part 2'), 2);
    expect(parseChapterNumber('No chapter here'), isNull);
  });

  test('groupAudiobookSeries orders chapters and skips singles', () {
    final songs = [
      song(path: '/b/ch1.mp3', title: 'Chapter 2', album: 'My Book'),
      song(path: '/b/ch0.mp3', title: 'Chapter 1', album: 'My Book'),
      song(path: '/b/ch2.mp3', title: 'Chapter 3', album: 'My Book'),
      song(
        path: '/m/single.mp3',
        title: 'Only One',
        album: 'Solo Book',
        durationMs: 90 * 60 * 1000,
      ),
    ];

    final groups = groupAudiobookSeries(songs);
    expect(groups.length, 1);
    expect(groups.first.title, 'My Book');
    expect(groups.first.chapterCount, 3);
    expect(groups.first.chapters.map((c) => c.chapterNumber).toList(), [1, 2, 3]);
  });
}
