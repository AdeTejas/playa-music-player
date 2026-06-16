import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:playa_clean/services/database_service.dart';
import 'package:playa_clean/utils/bookmark_key.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    final db = await databaseFactory.openDatabase(
      'file:bookmark_test_${DateTime.now().microsecondsSinceEpoch}?mode=memory&cache=shared',
      options: OpenDatabaseOptions(
        version: 6,
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
    DatabaseService.instance.resetForTest();
    DatabaseService.instance.initForTest(db);
    await DatabaseService.instance.ensureBookmarksReady();
  });

  test('upsert and load bookmarks by canonical track key', () async {
    const rawPath = r'C:\Audiobooks\Book1.mp3';
    final trackKey = BookmarkKey.canonical(rawPath);

    final saved = await DatabaseService.instance.upsertBookmark(
      trackKey: trackKey,
      positionMs: 125000,
      note: 'Important scene',
    );
    expect(saved, isTrue);

    final rows = await DatabaseService.instance.getBookmarksForTrack(trackKey);
    expect(rows.length, 1);
    expect(rows.first['pos'], 125000);
    expect(rows.first['note'], 'Important scene');
  });

  test('update and delete bookmark by id', () async {
    const trackKey = 'c:/audiobooks/book1.mp3';

    expect(
      await DatabaseService.instance.upsertBookmark(
        trackKey: trackKey,
        positionMs: 5000,
        note: 'A',
      ),
      isTrue,
    );

    var rows = await DatabaseService.instance.getBookmarksForTrack(trackKey);
    final id = rows.first['id'] as int;

    await DatabaseService.instance.updateBookmarkNote(id, 'Updated');
    rows = await DatabaseService.instance.getBookmarksForTrack(trackKey);
    expect(rows.first['note'], 'Updated');

    await DatabaseService.instance.deleteBookmark(id);
    rows = await DatabaseService.instance.getBookmarksForTrack(trackKey);
    expect(rows, isEmpty);
  });
}