import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:playa_clean/services/database_service.dart';
import 'package:playa_clean/utils/bookmark_key.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    DatabaseService.instance.resetForTest();
  });

  test('creates bookmarks table on legacy v6 schema without bookmarks', () async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 6,
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

    const trackKey =
        '/storage/emulated/0/snaptube/download/SnapTube Audio/sample.mp3';

    expect(
      await DatabaseService.instance.upsertBookmark(
        trackKey: trackKey,
        positionMs: 45210,
        note: 'Test note',
      ),
      isTrue,
    );

    final rows = await DatabaseService.instance.getBookmarksForTrack(trackKey);
    expect(rows.length, 1);
    expect(rows.first['pos'], 45210);
    expect(rows.first['note'], 'Test note');
    expect(BookmarkKey.canonical(trackKey), isNotEmpty);
  });
}