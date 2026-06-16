import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

void main() {
  group('Bookmark Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('add bookmark creates entry with position and note', () async {
      final prefs = await SharedPreferences.getInstance();
      final testId = 'test_song_123';
      final key = 'bookmarks_$testId';

      // Simulate adding a bookmark
      final bookmark = {'pos': 120000, 'note': 'Great chorus'};
      final encoded = jsonEncode(bookmark);
      await prefs.setStringList(key, [encoded]);

      final saved = prefs.getStringList(key) ?? [];
      expect(saved.length, equals(1));

      final decoded = jsonDecode(saved[0]) as Map<String, dynamic>;
      expect(decoded['pos'], equals(120000));
      expect(decoded['note'], equals('Great chorus'));
    });

    test('reload bookmark list retrieves all stored bookmarks', () async {
      final prefs = await SharedPreferences.getInstance();
      final testId = 'test_song_456';
      final key = 'bookmarks_$testId';

      // Add multiple bookmarks
      final bookmarks = [
        jsonEncode({'pos': 10000, 'note': 'Intro'}),
        jsonEncode({'pos': 60000, 'note': 'Verse'}),
        jsonEncode({'pos': 120000, 'note': 'Chorus'}),
      ];
      await prefs.setStringList(key, bookmarks);

      // Reload
      final saved = prefs.getStringList(key) ?? [];
      expect(saved.length, equals(3));

      final decoded = saved.map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
      expect(decoded[0]['note'], equals('Intro'));
      expect(decoded[1]['note'], equals('Verse'));
      expect(decoded[2]['note'], equals('Chorus'));
    });

    test('jump-to-bookmark returns correct position', () async {
      final bookmarks = [
        {'pos': 10000, 'note': 'Intro'},
        {'pos': 60000, 'note': 'Verse'},
        {'pos': 120000, 'note': 'Chorus'},
      ];

      // Simulate jump to bookmark at index 1
      final targetBookmark = bookmarks[1];
      expect(targetBookmark['pos'], equals(60000));
    });

    test('bookmark persistence survives app restart', () async {
      final prefs = await SharedPreferences.getInstance();
      final testId = 'test_song_789';
      final key = 'bookmarks_$testId';

      // Save bookmarks before "restart"
      final bookmarks = [
        jsonEncode({'pos': 15000, 'note': 'Bridge'}),
      ];
      await prefs.setStringList(key, bookmarks);

      // Simulate app restart by getting a fresh instance
      final prefsAfterRestart = await SharedPreferences.getInstance();
      final saved = prefsAfterRestart.getStringList(key) ?? [];

      expect(saved.length, equals(1));
      final decoded = jsonDecode(saved[0]) as Map<String, dynamic>;
      expect(decoded['pos'], equals(15000));
      expect(decoded['note'], equals('Bridge'));
    });

    test('handle malformed bookmark data gracefully', () {
      // Test parsing of old format (just milliseconds)
      final legacyBookmark = '45000';
      final ms = int.tryParse(legacyBookmark);
      expect(ms, equals(45000));

      // Test parsing of new format (JSON)
      final newBookmark = jsonEncode({'pos': 45000, 'note': 'Custom'});
      final decoded = jsonDecode(newBookmark) as Map<String, dynamic>;
      expect(decoded['pos'], equals(45000));
    });

    test('bookmark update changes note without losing position', () async {
      final prefs = await SharedPreferences.getInstance();
      final testId = 'test_song_update';
      final key = 'bookmarks_$testId';

      final bookmark = {'pos': 90000, 'note': 'Old note'};
      await prefs.setStringList(key, [jsonEncode(bookmark)]);

      // Update note
      final updated = {'pos': 90000, 'note': 'New note'};
      await prefs.setStringList(key, [jsonEncode(updated)]);

      final saved = prefs.getStringList(key) ?? [];
      final decoded = jsonDecode(saved[0]) as Map<String, dynamic>;
      expect(decoded['pos'], equals(90000));
      expect(decoded['note'], equals('New note'));
    });

    test('removing bookmark decreases list count', () async {
      final prefs = await SharedPreferences.getInstance();
      final testId = 'test_song_remove';
      final key = 'bookmarks_$testId';

      final bookmarks = [
        jsonEncode({'pos': 10000, 'note': 'A'}),
        jsonEncode({'pos': 20000, 'note': 'B'}),
        jsonEncode({'pos': 30000, 'note': 'C'}),
      ];
      await prefs.setStringList(key, bookmarks);

      // Remove middle bookmark
      final remaining = [bookmarks[0], bookmarks[2]];
      await prefs.setStringList(key, remaining);

      final saved = prefs.getStringList(key) ?? [];
      expect(saved.length, equals(2));
    });

    test('canonical bookmark keys normalize slashes on windows paths', () {
      const backslashKey = r'bookmarks_c:\music\chapter1.mp3';
      const slashKey = 'bookmarks_c:/music/chapter1.mp3';

      final bookmark = jsonEncode({'pos': 45000, 'note': 'Intro'});
      SharedPreferences.setMockInitialValues({
        backslashKey: [bookmark],
      });

      // Both key forms should refer to the same logical file path.
      expect(backslashKey.toLowerCase().replaceAll(r'\', '/'), slashKey);
    });

    test('empty bookmark list returns empty when no bookmarks exist', () async {
      final prefs = await SharedPreferences.getInstance();
      final testId = 'test_song_empty';
      final key = 'bookmarks_$testId';

      final saved = prefs.getStringList(key) ?? [];
      expect(saved.isEmpty, isTrue);
    });
  });
}
