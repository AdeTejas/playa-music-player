import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/database_service.dart';
import '../utils/bookmark_key.dart';

/// Bookmarks are stored in SharedPreferences (primary) and SQLite (secondary).
/// Prefs are the reliable fallback on Android when DB reads/writes fail silently.
class BookmarkRepository {
  BookmarkRepository._();
  static BookmarkRepository? _instance;
  static BookmarkRepository get instance => _instance ??= BookmarkRepository._();

  static String prefsKeyForTrack(String trackKey) {
    final canonical = BookmarkKey.canonical(trackKey);
    if (canonical.isEmpty) return '';
    return 'bookmarks_$canonical';
  }

  String _canonicalTrackKey(String trackKey) => BookmarkKey.canonical(trackKey);

  int _pos(Map<String, dynamic> bookmark) =>
      (bookmark['pos'] as num?)?.toInt() ?? 0;

  Map<String, dynamic>? _parseEntry(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final pos = (map['pos'] as num?)?.toInt();
      if (pos == null) return null;
      return {'pos': pos, 'note': (map['note'] as String?) ?? ''};
    } catch (_) {
      final ms = int.tryParse(raw);
      if (ms == null) return null;
      return {'pos': ms, 'note': ''};
    }
  }

  Future<void> _mergeLegacyPrefsKeys(String canonicalKey) async {
    if (canonicalKey.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final targetKey = prefsKeyForTrack(canonicalKey);
    if (targetKey.isEmpty) return;

    final merged = <String>[
      ...?prefs.getStringList(targetKey),
    ];
    var dirty = false;

    for (final prefKey in prefs.getKeys()) {
      if (!prefKey.startsWith('bookmarks_') || prefKey == targetKey) continue;

      final suffix = prefKey.substring('bookmarks_'.length);
      if (_canonicalTrackKey(suffix) != canonicalKey) continue;

      final legacyEntries = prefs.getStringList(prefKey) ?? const <String>[];
      for (final entry in legacyEntries) {
        final parsed = _parseEntry(entry);
        if (parsed == null) continue;
        final pos = _pos(parsed);
        merged.removeWhere((existing) {
          final existingParsed = _parseEntry(existing);
          return existingParsed != null && _pos(existingParsed) == pos;
        });
        merged.add(entry);
        dirty = true;
      }
      await prefs.remove(prefKey);
      dirty = true;
    }

    if (!dirty) return;

    merged.sort((a, b) {
      final pa = _parseEntry(a);
      final pb = _parseEntry(b);
      return _pos(pa ?? const {}).compareTo(_pos(pb ?? const {}));
    });
    await prefs.setStringList(targetKey, merged);
  }

  Future<List<Map<String, dynamic>>> _loadFromPrefs(String trackKey) async {
    final prefKey = prefsKeyForTrack(trackKey);
    if (prefKey.isEmpty) return const [];

    final prefs = await SharedPreferences.getInstance();
    final entries = prefs.getStringList(prefKey) ?? const <String>[];
    final rows = <Map<String, dynamic>>[];

    for (final entry in entries) {
      final parsed = _parseEntry(entry);
      if (parsed == null) continue;
      final pos = _pos(parsed);
      rows.add({
        // Negative ids mark prefs-backed rows (not SQLite autoincrement).
        'id': -pos,
        'pos': pos,
        'note': (parsed['note'] as String?) ?? '',
        'source': 'prefs',
      });
    }

    rows.sort((a, b) => _pos(a).compareTo(_pos(b)));
    return rows;
  }

  Future<bool> _saveToPrefs(
    String trackKey,
    int positionMs,
    String note,
  ) async {
    final prefKey = prefsKeyForTrack(trackKey);
    if (prefKey.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(prefKey) ?? <String>[];
    final kept = <String>[];

    for (final entry in existing) {
      final parsed = _parseEntry(entry);
      if (parsed == null) continue;
      if (_pos(parsed) == positionMs) continue;
      kept.add(entry);
    }

    kept.add(jsonEncode({'pos': positionMs, 'note': note}));
    kept.sort((a, b) {
      final pa = _parseEntry(a);
      final pb = _parseEntry(b);
      return _pos(pa ?? const {}).compareTo(_pos(pb ?? const {}));
    });

    final ok = await prefs.setStringList(prefKey, kept);
    if (kDebugMode) {
      debugPrint(
        '[BOOKMARKS] prefs save ok=$ok key=$prefKey pos=$positionMs count=${kept.length}',
      );
    }
    return ok;
  }

  Future<bool> _updatePrefsNote(
    String trackKey,
    int positionMs,
    String note,
  ) async {
    final prefKey = prefsKeyForTrack(trackKey);
    if (prefKey.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(prefKey) ?? <String>[];
    if (existing.isEmpty) return false;

    var found = false;
    final updated = existing.map((entry) {
      final parsed = _parseEntry(entry);
      if (parsed == null || _pos(parsed) != positionMs) return entry;
      found = true;
      return jsonEncode({'pos': positionMs, 'note': note});
    }).toList();

    if (!found) return false;
    return prefs.setStringList(prefKey, updated);
  }

  Future<bool> _removeFromPrefs(String trackKey, int positionMs) async {
    final prefKey = prefsKeyForTrack(trackKey);
    if (prefKey.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getStringList(prefKey) ?? <String>[];
    final updated = <String>[];

    for (final entry in existing) {
      final parsed = _parseEntry(entry);
      if (parsed == null) continue;
      if (_pos(parsed) == positionMs) continue;
      updated.add(entry);
    }

    return prefs.setStringList(prefKey, updated);
  }

  Future<List<Map<String, dynamic>>> loadForTrack(
    String trackKey, {
    List<String> aliases = const [],
  }) async {
    final keys = <String>{
      _canonicalTrackKey(trackKey),
      for (final alias in aliases) _canonicalTrackKey(alias),
    }..removeWhere((key) => key.isEmpty);

    if (keys.isEmpty) return const [];

    for (final key in keys) {
      await _mergeLegacyPrefsKeys(key);
    }

    final byPos = <int, Map<String, dynamic>>{};

    for (final key in keys) {
      for (final row in await _loadFromPrefs(key)) {
        byPos[_pos(row)] = row;
      }
    }

    try {
      for (final key in keys) {
        for (final row in await DatabaseService.instance.getBookmarksForTrack(
          key,
        )) {
          byPos[_pos(row)] = {...row, 'source': 'db'};
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BOOKMARKS] db load skipped: $e');
      }
    }

    final merged = byPos.values.toList()
      ..sort((a, b) => _pos(a).compareTo(_pos(b)));
    return List<Map<String, dynamic>>.unmodifiable(merged);
  }

  Future<bool> add({
    required String trackKey,
    required int positionMs,
    required String note,
  }) async {
    final key = _canonicalTrackKey(trackKey);
    if (key.isEmpty) return false;

    final prefsSaved = await _saveToPrefs(key, positionMs, note);
    var dbSaved = false;
    try {
      await DatabaseService.instance.ensureBookmarksReady();
      dbSaved = await DatabaseService.instance.upsertBookmark(
        trackKey: key,
        positionMs: positionMs,
        note: note,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BOOKMARKS] db save skipped: $e');
      }
    }

    final ok = prefsSaved || dbSaved;
    if (kDebugMode) {
      debugPrint(
        '[BOOKMARKS] add track=$key pos=$positionMs prefs=$prefsSaved db=$dbSaved',
      );
    }
    return ok;
  }

  Future<bool> updateNote({
    required String trackKey,
    required Map<String, dynamic> bookmark,
    required String note,
  }) async {
    final key = _canonicalTrackKey(trackKey);
    if (key.isEmpty) return false;

    final pos = _pos(bookmark);
    final id = bookmark['id'] as int?;

    var ok = await _updatePrefsNote(key, pos, note);
    if (id != null && id > 0) {
      try {
        await DatabaseService.instance.updateBookmarkNote(id, note);
        ok = true;
      } catch (_) {}
    }
    return ok;
  }

  Future<bool> remove({
    required String trackKey,
    required Map<String, dynamic> bookmark,
  }) async {
    final key = _canonicalTrackKey(trackKey);
    if (key.isEmpty) return false;

    final pos = _pos(bookmark);
    final id = bookmark['id'] as int?;

    var ok = await _removeFromPrefs(key, pos);
    if (id != null && id > 0) {
      try {
        await DatabaseService.instance.deleteBookmark(id);
        ok = true;
      } catch (_) {}
    }
    return ok;
  }
}