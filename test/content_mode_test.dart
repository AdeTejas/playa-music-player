import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:playa_clean/utils/content_mode.dart';

void main() {
  group('ContentModeDetector', () {
    test('detects m4b as audiobook', () {
      const item = MediaItem(
        id: '/books/book.m4b',
        title: 'Chapter 1',
        album: 'The Book',
        artist: 'Author',
        duration: Duration(minutes: 10),
        extras: {'path': '/books/book.m4b'},
      );

      expect(
        ContentModeDetector.detectFromMediaItem(item),
        ContentMode.audiobook,
      );
    });

    test('detects long tracks as audiobook', () {
      const item = MediaItem(
        id: '/books/long.mp3',
        title: 'Part 1',
        album: 'Series',
        artist: 'Narrator',
        duration: Duration(hours: 2),
        extras: {'path': '/books/long.mp3'},
      );

      expect(
        ContentModeDetector.detectFromMediaItem(item),
        ContentMode.audiobook,
      );
    });

    test('detects podcast metadata as audiobook', () {
      const item = MediaItem(
        id: '/podcasts/show/ep12.mp3',
        title: 'Episode 12: Deep Dive',
        album: 'My Favorite Podcast',
        artist: 'Host Name',
        duration: Duration(minutes: 35),
        extras: {'path': '/podcasts/show/ep12.mp3'},
      );

      expect(
        ContentModeDetector.detectFromMediaItem(item),
        ContentMode.audiobook,
      );
    });

    test('detects short tracks as music', () {
      const item = MediaItem(
        id: '/music/song.mp3',
        title: 'Single',
        album: 'Album',
        artist: 'Band',
        duration: Duration(minutes: 3),
        extras: {'path': '/music/song.mp3'},
      );

      expect(
        ContentModeDetector.detectFromMediaItem(item),
        ContentMode.music,
      );
    });

    test('series key groups by album and artist', () {
      const item = MediaItem(
        id: '/a.mp3',
        title: 'Track 1',
        album: 'My Book',
        artist: 'Jane Doe',
      );

      expect(
        ContentModeDetector.seriesKeyForMediaItem(item),
        'jane doe::my book',
      );
    });

    test('series key falls back to parent folder', () {
      const item = MediaItem(
        id: '/audiobooks/expanse/book1/03.mp3',
        title: '03',
        album: 'Unknown Album',
        artist: 'Unknown Artist',
        extras: {'path': r'C:\audiobooks\expanse\book1\03.mp3'},
      );

      expect(
        ContentModeDetector.seriesKeyForMediaItem(item),
        'folder::book1',
      );
    });
  });
}