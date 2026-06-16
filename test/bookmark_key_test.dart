import 'package:flutter_test/flutter_test.dart';

import 'package:playa_clean/utils/bookmark_key.dart';

void main() {
  test('primaryForTrack prefers explicit bookmark key', () {
    expect(
      BookmarkKey.primaryForTrack(
        bookmarkKey: r'C:\Music\Song.mp3',
        path: '/other/path.mp3',
        itemId: 'fallback',
      ),
      'c:/music/song.mp3',
    );
  });

  test('aliasesForTrack includes path, id, and media id variants', () {
    final aliases = BookmarkKey.aliasesForTrack(
      bookmarkKey: r'C:\Books\Chapter 1.mp3',
      path: r'C:\Books\Chapter 1.mp3',
      mediaId: 42,
      itemId: r'C:\Books\Chapter 1.mp3',
    );

    expect(aliases, contains('c:/books/chapter 1.mp3'));
    expect(aliases, contains('media:42'));
    expect(aliases.length, greaterThan(1));
  });
}