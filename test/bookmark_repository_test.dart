import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:playa_clean/repositories/bookmark_repository.dart';
import 'package:playa_clean/services/database_service.dart';
import 'package:playa_clean/utils/bookmark_key.dart';

void main() {
  late Database testDb;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.instance.resetForTest();
    testDb = await databaseFactory.openDatabase(
      'file:bookmark_repo_${DateTime.now().microsecondsSinceEpoch}?mode=memory&cache=shared',
      options: OpenDatabaseOptions(
        version: 7,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE bookmarks (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              track_key TEXT NOT NULL,
              position_ms INTEGER NOT NULL,
              note TEXT DEFAULT '',
              UNIQUE(track_key, position_ms)
            )
          ''');
        },
      ),
    );
    DatabaseService.instance.initForTest(testDb);
  });

  test('saves and loads bookmark from prefs when db empty', () async {
    const trackKey =
        '/storage/emulated/0/snaptube/download/SnapTube Audio/sample.mp3';

    final saved = await BookmarkRepository.instance.add(
      trackKey: trackKey,
      positionMs: 12500,
      note: 'Chapter 2',
    );
    expect(saved, isTrue);

    final rows = await BookmarkRepository.instance.loadForTrack(trackKey);
    expect(rows.length, 1);
    expect(rows.first['pos'], 12500);
    expect(rows.first['note'], 'Chapter 2');
  });

  test('remove bookmark clears prefs entry', () async {
    const trackKey = '/music/book.mp3';

    await BookmarkRepository.instance.add(
      trackKey: trackKey,
      positionMs: 5000,
      note: 'A',
    );

    var rows = await BookmarkRepository.instance.loadForTrack(trackKey);
    expect(rows.length, 1);

    await BookmarkRepository.instance.remove(
      trackKey: trackKey,
      bookmark: rows.first,
    );

    rows = await BookmarkRepository.instance.loadForTrack(trackKey);
    expect(rows, isEmpty);
  });

  test('add stores canonical track key in database', () async {
    const mixed =
        '/storage/emulated/0/snaptube/download/SnapTube Audio/sample.mp3';
    const canonical =
        '/storage/emulated/0/snaptube/download/snaptube audio/sample.mp3';

    await BookmarkRepository.instance.add(
      trackKey: mixed,
      positionMs: 9000,
      note: 'Scene',
    );

    final dbRows =
        await DatabaseService.instance.getBookmarksForTrack(canonical);
    expect(dbRows.length, 1);
    expect(dbRows.first['note'], 'Scene');
    expect(BookmarkKey.canonical(mixed), canonical);
  });

  test('load finds legacy mixed-case database rows via canonical key', () async {
    const mixed =
        '/storage/emulated/0/snaptube/download/SnapTube Audio/sample.mp3';
    const canonical =
        '/storage/emulated/0/snaptube/download/snaptube audio/sample.mp3';

    await testDb.insert('bookmarks', {
      'track_key': mixed,
      'position_ms': 1000,
      'note': 'legacy',
    });

    final rows = await BookmarkRepository.instance.loadForTrack(canonical);
    expect(rows.length, 1);
    expect(rows.first['pos'], 1000);
    expect(rows.first['note'], 'legacy');
  });

  test('load merges legacy prefs keys with different slash casing', () async {
    const canonical = 'c:/audiobooks/book1.mp3';
    const legacyKey = r'bookmarks_C:\Audiobooks\Book1.mp3';

    SharedPreferences.setMockInitialValues({
      legacyKey: [jsonEncode({'pos': 15000, 'note': 'Old key'})],
    });
    DatabaseService.instance.resetForTest();
    testDb = await databaseFactory.openDatabase(
      'file:bookmark_repo_legacy_${DateTime.now().microsecondsSinceEpoch}?mode=memory&cache=shared',
      options: OpenDatabaseOptions(
        version: 7,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE bookmarks (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              track_key TEXT NOT NULL,
              position_ms INTEGER NOT NULL,
              note TEXT DEFAULT '',
              UNIQUE(track_key, position_ms)
            )
          ''');
        },
      ),
    );
    DatabaseService.instance.initForTest(testDb);

    final rows = await BookmarkRepository.instance.loadForTrack(canonical);
    expect(rows.length, 1);
    expect(rows.first['pos'], 15000);
    expect(rows.first['note'], 'Old key');
  });

  test('load merges bookmarks stored under alias keys', () async {
    const primary = 'c:/audiobooks/book1.mp3';
    const legacy = r'C:\Audiobooks\Book1.mp3';

    await BookmarkRepository.instance.add(
      trackKey: legacy,
      positionMs: 30000,
      note: 'Alias lookup',
    );

    final rows = await BookmarkRepository.instance.loadForTrack(
      primary,
      aliases: [legacy],
    );
    expect(rows.length, 1);
    expect(rows.first['note'], 'Alias lookup');
  });

  test('mixed-case add and canonical load round-trip', () async {
    const mixed = r'C:\Audiobooks\Book1.mp3';
    const canonical = 'c:/audiobooks/book1.mp3';

    await BookmarkRepository.instance.add(
      trackKey: mixed,
      positionMs: 42000,
      note: 'Chapter',
    );

    final rows = await BookmarkRepository.instance.loadForTrack(canonical);
    expect(rows.length, 1);
    expect(rows.first['pos'], 42000);
    expect(rows.first['note'], 'Chapter');
  });
}