import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart' as oaq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:playa_clean/models/listening_progress.dart';
import 'package:playa_clean/repositories/listening_progress_repository.dart';
import 'package:playa_clean/services/database_service.dart';
import 'package:playa_clean/utils/content_mode.dart';

oaq.SongModel _song({
  required int id,
  required String title,
  required String path,
  String? album,
  String? artist,
  int? durationMs,
  int? track,
}) {
  return oaq.SongModel({
    '_id': id,
    '_data': path,
    'title': title,
    'album': album ?? 'Unknown Album',
    'artist': artist ?? 'Unknown Artist',
    'duration': durationMs ?? 0,
    'track': track ?? 0,
  });
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    DatabaseService.instance.resetForTest();
    final db = await databaseFactory.openDatabase(
      'file:listening_progress_${DateTime.now().microsecondsSinceEpoch}?mode=memory&cache=shared',
      options: OpenDatabaseOptions(
        version: 7,
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE listening_progress (
              series_key TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              artist TEXT,
              last_song_path TEXT NOT NULL,
              last_media_id INTEGER,
              position_ms INTEGER NOT NULL DEFAULT 0,
              updated_at INTEGER NOT NULL,
              content_mode TEXT NOT NULL DEFAULT 'audiobook'
            )
          ''');
        },
      ),
    );
    DatabaseService.instance.initForTest(db);
  });

  test('recordFromPlayback upserts and getRecent returns newest first', () async {
    await ListeningProgressRepository.instance.recordFromPlayback(
      seriesKey: 'author::book one',
      title: 'Book One',
      artist: 'Author',
      songPath: '/books/book1/ch01.mp3',
      mediaId: 101,
      positionMs: 125000,
      contentMode: ContentMode.audiobook,
    );

    await Future<void>.delayed(const Duration(milliseconds: 2));

    await ListeningProgressRepository.instance.recordFromPlayback(
      seriesKey: 'author::book two',
      title: 'Book Two',
      artist: 'Author',
      songPath: '/books/book2/ch01.mp3',
      mediaId: 202,
      positionMs: 45000,
      contentMode: ContentMode.audiobook,
    );

    final recent = await ListeningProgressRepository.instance.getRecent(limit: 4);
    expect(recent.length, 2);
    expect(recent.first.seriesKey, 'author::book two');
    expect(recent.first.positionMs, 45000);
    expect(recent.last.seriesKey, 'author::book one');
  });

  test('getBySeriesKey returns saved progress for multi-chapter resume', () async {
    const seriesKey = 'narrator::saga';
    await ListeningProgressRepository.instance.recordFromPlayback(
      seriesKey: seriesKey,
      title: 'Saga',
      artist: 'Narrator',
      songPath: '/podcasts/saga/ep03.mp3',
      mediaId: 303,
      positionMs: 987000,
      contentMode: ContentMode.audiobook,
    );

    final saved = await ListeningProgressRepository.instance.getBySeriesKey(seriesKey);
    expect(saved, isNotNull);
    expect(saved!.lastSongPath, '/podcasts/saga/ep03.mp3');
    expect(saved.lastMediaId, 303);
    expect(saved.positionMs, 987000);
    expect(saved.contentMode, ContentMode.audiobook);
  });

  test('series keys align across chapters for queue resume', () {
    final ch1 = _song(
      id: 1,
      title: 'Chapter 1',
      path: r'C:\Audiobooks\Expanse\Leviathan Wakes\01.mp3',
      album: 'Leviathan Wakes',
      artist: 'James S. A. Corey',
      durationMs: 55 * 60 * 1000,
      track: 1,
    );
    final ch2 = _song(
      id: 2,
      title: 'Chapter 2',
      path: r'C:\Audiobooks\Expanse\Leviathan Wakes\02.mp3',
      album: 'Leviathan Wakes',
      artist: 'James S. A. Corey',
      durationMs: 48 * 60 * 1000,
      track: 2,
    );

    final key1 = ContentModeDetector.seriesKeyForSong(ch1);
    final key2 = ContentModeDetector.seriesKeyForSong(ch2);
    expect(key1, key2);
    expect(key1, 'james s. a. corey::leviathan wakes');
  });

  test('library browse filter separates long-form from short tracks', () {
    final audiobook = _song(
      id: 10,
      title: 'Part 1',
      path: '/audio/long.mp3',
      album: 'Long Book',
      artist: 'Narrator',
      durationMs: 2 * 60 * 60 * 1000,
    );
    final music = _song(
      id: 11,
      title: 'Single',
      path: '/audio/song.mp3',
      album: 'Album',
      artist: 'Band',
      durationMs: 3 * 60 * 1000,
    );

    expect(
      ContentModeDetector.songMatchesBrowseFilter(
        audiobook,
        LibraryBrowseFilter.audiobook,
      ),
      isTrue,
    );
    expect(
      ContentModeDetector.songMatchesBrowseFilter(
        music,
        LibraryBrowseFilter.audiobook,
      ),
      isFalse,
    );
    expect(
      ContentModeDetector.songMatchesBrowseFilter(
        music,
        LibraryBrowseFilter.music,
      ),
      isTrue,
    );
  });
}