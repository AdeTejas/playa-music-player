import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/listening_progress.dart';
import '../models/song_metadata.dart';
import '../models/playlist.dart';
import '../utils/bookmark_key.dart';
import '../utils/content_mode.dart';

class DatabaseService {
  static DatabaseService? _instance;
  static DatabaseService get instance => _instance ??= DatabaseService._();
  DatabaseService._();

  Database? _db;
  bool _isInitialized = false;
  String? _dbPath;

  final Map<String, SongMetadata> _metadataCache = <String, SongMetadata>{};
  final Map<String, Future<SongMetadata?>> _metadataInflight =
      <String, Future<SongMetadata?>>{};

  bool get isInitialized => _isInitialized;
  String? get dbPath => _dbPath;

  @visibleForTesting
  void initForTest(Database db) {
    _db = db;
    _isInitialized = true;
    _dbPath = ':memory:';
  }

  @visibleForTesting
  void resetForTest() {
    _db = null;
    _isInitialized = false;
    _dbPath = null;
    _metadataCache.clear();
    _metadataInflight.clear();
  }

  Future<void> ensureBookmarksReady() async {
    await init();
    if (kIsWeb || _db == null) return;
    await _ensureBookmarksTable(_db!);
  }

  Future<void> init() async {
    if (_isInitialized) {
      if (_db != null) await _ensureBookmarksTable(_db!);
      return;
    }

    if (kIsWeb) {
      if (kDebugMode) {
        debugPrint(
          'DatabaseService: Web detected, skipping SQLite initialization.',
        );
      }
      _isInitialized = true;
      return;
    }

    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, 'playa.db');
    _dbPath = path;

    _db = await openDatabase(
      path,
      version: 7,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    await _ensureBookmarksTable(_db!);
    _isInitialized = true;
  }

  Future<void> _ensureBookmarksTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        track_key TEXT NOT NULL,
        position_ms INTEGER NOT NULL,
        note TEXT DEFAULT '',
        UNIQUE(track_key, position_ms)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_bookmarks_track_key ON bookmarks(track_key)',
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE song_metadata (
        song_id TEXT PRIMARY KEY,
        rating INTEGER,
        lyrics TEXT,
        play_count INTEGER,
        last_played INTEGER,
        bpm REAL,
        key TEXT,
        dna_sig TEXT
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_song_metadata_play_count ON song_metadata(play_count)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_song_metadata_last_played ON song_metadata(last_played)',
    );

    await db.execute('''
      CREATE TABLE playlists (
        id TEXT PRIMARY KEY,
        name TEXT,
        song_ids TEXT,
        description TEXT
      )
    ''');

    await db.execute('''
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

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_listening_progress_updated ON listening_progress(updated_at DESC)',
    );

    await _ensureBookmarksTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Additive, safe migrations only.
    if (oldVersion < 2) {
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_song_metadata_play_count ON song_metadata(play_count)',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_song_metadata_last_played ON song_metadata(last_played)',
      );
    }

    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE song_metadata ADD COLUMN dna_sig TEXT');
      } catch (_) {
        // Column may already exist.
      }
    }

    if (oldVersion < 4) {
      try {
        await db.execute('ALTER TABLE playlists ADD COLUMN description TEXT');
      } catch (_) {
        // Column may already exist.
      }
    }

    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS listening_progress (
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
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_listening_progress_updated ON listening_progress(updated_at DESC)',
      );
    }

    if (oldVersion < 7) {
      await _ensureBookmarksTable(db);
    }
  }

  // ═══ Song Metadata ═══

  SongMetadata _mapToSongMetadata(Map<String, Object?> map) {
    return SongMetadata(
      id: map['song_id'] as String,
      rating: map['rating'] as int?,
      lyrics: map['lyrics'] as String?,
      playCount: map['play_count'] as int? ?? 0,
      lastPlayed:
          map['last_played'] != null
              ? DateTime.fromMillisecondsSinceEpoch(map['last_played'] as int)
              : null,
      bpm: map['bpm'] as double?,
      key: map['key'] as String?,
      dnaSignature: map['dna_sig'] as String?,
    );
  }

  void _cachePut(SongMetadata meta) {
    _metadataCache[meta.id] = meta;
  }

  /// Cached read of metadata. Returns `null` if none exists.
  Future<SongMetadata?> getSongMetadata(String songId) async {
    if (kIsWeb || _db == null) return null;
    final cached = _metadataCache[songId];
    if (cached != null) return cached;

    final inflight = _metadataInflight[songId];
    if (inflight != null) return inflight;

    final future = () async {
      final maps = await _db!.query(
        'song_metadata',
        where: 'song_id = ?',
        whereArgs: [songId],
      );
      if (maps.isEmpty) return null;
      final meta = _mapToSongMetadata(maps.first);
      _cachePut(meta);
      return meta;
    }();

    _metadataInflight[songId] = future;
    try {
      return await future;
    } finally {
      _metadataInflight.remove(songId);
    }
  }

  /// Batch fetch metadata for `songIds` in a small number of queries.
  /// Returns a map of `songId -> SongMetadata` for rows that exist.
  Future<Map<String, SongMetadata>> getSongMetadataForIds(
    Iterable<String> songIds,
  ) async {
    if (kIsWeb || _db == null) return <String, SongMetadata>{};

    final unique = songIds.toSet();
    if (unique.isEmpty) return <String, SongMetadata>{};

    final result = <String, SongMetadata>{};
    final missing = <String>[];

    for (final id in unique) {
      final cached = _metadataCache[id];
      if (cached != null) {
        result[id] = cached;
      } else {
        missing.add(id);
      }
    }

    // SQLite has a variable limit (commonly 999). Keep a safe buffer.
    const chunkSize = 800;
    for (var i = 0; i < missing.length; i += chunkSize) {
      final chunk = missing.sublist(
        i,
        (i + chunkSize) > missing.length ? missing.length : (i + chunkSize),
      );
      if (chunk.isEmpty) continue;

      final placeholders = List.filled(chunk.length, '?').join(',');
      final maps = await _db!.query(
        'song_metadata',
        where: 'song_id IN ($placeholders)',
        whereArgs: chunk,
      );
      for (final row in maps) {
        final meta = _mapToSongMetadata(row);
        result[meta.id] = meta;
        _cachePut(meta);
      }
    }

    return result;
  }

  Future<void> updateRating(String songId, int rating) async {
    if (kIsWeb || _db == null) return;
    final count = await _db!.update(
      'song_metadata',
      {'rating': rating},
      where: 'song_id = ?',
      whereArgs: [songId],
    );

    if (count == 0) {
      await _db!.insert('song_metadata', {'song_id': songId, 'rating': rating});
    }

    final current = _metadataCache[songId];
    _cachePut((current ?? SongMetadata(id: songId)).copyWith(rating: rating));
  }

  Future<void> saveLyrics(
    String songId,
    String lyrics, {
    String? source,
  }) async {
    if (kIsWeb || _db == null) return;
    final count = await _db!.update(
      'song_metadata',
      {'lyrics': lyrics},
      where: 'song_id = ?',
      whereArgs: [songId],
    );

    if (count == 0) {
      await _db!.insert('song_metadata', {'song_id': songId, 'lyrics': lyrics});
    }

    final current = _metadataCache[songId];
    _cachePut((current ?? SongMetadata(id: songId)).copyWith(lyrics: lyrics));
  }

  Future<void> updateLastPlayed(String songId) async {
    if (kIsWeb || _db == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final count = await _db!.update(
      'song_metadata',
      {'last_played': now},
      where: 'song_id = ?',
      whereArgs: [songId],
    );

    if (count == 0) {
      await _db!.insert('song_metadata', {
        'song_id': songId,
        'last_played': now,
      });
    }

    final current = _metadataCache[songId];
    _cachePut(
      (current ?? SongMetadata(id: songId)).copyWith(
        lastPlayed: DateTime.fromMillisecondsSinceEpoch(now),
      ),
    );
  }

  Future<void> incrementPlayCount(String songId) async {
    if (kIsWeb || _db == null) return;

    // Avoid a read-before-write roundtrip.
    final rows = await _db!.rawUpdate(
      'UPDATE song_metadata '
      'SET play_count = COALESCE(play_count, 0) + 1 '
      'WHERE song_id = ?',
      [songId],
    );

    if (rows == 0) {
      await _db!.insert('song_metadata', {'song_id': songId, 'play_count': 1});
    }

    final current = _metadataCache[songId];
    if (current != null) {
      _cachePut(current.copyWith(playCount: current.playCount + 1));
    }
  }

  Future<void> updateSonicDna(
    String songId, {
    double? bpm,
    String? key,
    String? dnaSignature,
  }) async {
    if (kIsWeb || _db == null) return;
    final values = <String, Object?>{};
    if (bpm != null) values['bpm'] = bpm;
    if (key != null) values['key'] = key;
    if (dnaSignature != null) values['dna_sig'] = dnaSignature;
    if (values.isEmpty) return;

    final rows = await _db!.update(
      'song_metadata',
      values,
      where: 'song_id = ?',
      whereArgs: [songId],
    );

    if (rows == 0) {
      await _db!.insert('song_metadata', {'song_id': songId, ...values});
    }

    final current = _metadataCache[songId];
    _cachePut(
      (current ?? SongMetadata(id: songId)).copyWith(
        bpm: bpm,
        key: key,
        dnaSignature: dnaSignature,
      ),
    );
  }

  Future<List<SongMetadata>> getAllSongMetadata() async {
    if (kIsWeb || _db == null) return [];
    final maps = await _db!.query('song_metadata');
    final list = maps.map(_mapToSongMetadata).toList();
    for (final m in list) {
      _cachePut(m);
    }
    return list;
  }

  Future<List<SongMetadata>> getMostPlayed({int limit = 20}) async {
    if (kIsWeb || _db == null) return [];
    final maps = await _db!.query(
      'song_metadata',
      orderBy: 'play_count DESC',
      limit: limit,
    );
    return maps
        .map(
          (map) => SongMetadata(
            id: map['song_id'] as String,
            rating: map['rating'] as int?,
            lyrics: map['lyrics'] as String?,
            playCount: map['play_count'] as int? ?? 0,
            lastPlayed:
                map['last_played'] != null
                    ? DateTime.fromMillisecondsSinceEpoch(
                      map['last_played'] as int,
                    )
                    : null,
            bpm: map['bpm'] as double?,
            key: map['key'] as String?,
            dnaSignature: map['dna_sig'] as String?,
          ),
        )
        .toList();
  }

  Future<List<SongMetadata>> getRecentlyPlayed({int limit = 20}) async {
    if (kIsWeb || _db == null) return [];
    final maps = await _db!.query(
      'song_metadata',
      orderBy: 'last_played DESC',
      limit: limit,
    );
    return maps
        .map(
          (map) => SongMetadata(
            id: map['song_id'] as String,
            rating: map['rating'] as int?,
            lyrics: map['lyrics'] as String?,
            playCount: map['play_count'] as int? ?? 0,
            lastPlayed:
                map['last_played'] != null
                    ? DateTime.fromMillisecondsSinceEpoch(
                      map['last_played'] as int,
                    )
                    : null,
            bpm: map['bpm'] as double?,
            key: map['key'] as String?,
            dnaSignature: map['dna_sig'] as String?,
          ),
        )
        .toList();
  }

  // ═══ Playlists ═══

  Future<List<Playlist>> getAllPlaylists() async {
    if (kIsWeb || _db == null) return [];
    final maps = await _db!.query('playlists');
    return maps.map((map) {
      final songIdsJson = map['song_ids'] as String?;
      final songIds =
          songIdsJson != null
              ? List<String>.from(json.decode(songIdsJson))
              : <String>[];
      return Playlist(
        id: map['id'] as String,
        name: map['name'] as String,
        description: map['description'] as String?,
        songIds: songIds,
      );
    }).toList();
  }

  Future<Playlist?> getPlaylist(String id) async {
    if (kIsWeb || _db == null) return null;
    final maps = await _db!.query(
      'playlists',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;

    final map = maps.first;
    final songIdsJson = map['song_ids'] as String?;
    final songIds =
        songIdsJson != null
            ? List<String>.from(json.decode(songIdsJson))
            : <String>[];
    return Playlist(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      songIds: songIds,
    );
  }

  Future<void> createPlaylist(Playlist playlist) async {
    if (kIsWeb || _db == null) return;
    await _db!.insert('playlists', {
      'id': playlist.id,
      'name': playlist.name,
      'song_ids': json.encode(playlist.songIds),
      'description': playlist.description,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updatePlaylist(Playlist playlist) async {
    if (kIsWeb || _db == null) return;
    await _db!.update(
      'playlists',
      {
        'name': playlist.name,
        'song_ids': json.encode(playlist.songIds),
        'description': playlist.description,
      },
      where: 'id = ?',
      whereArgs: [playlist.id],
    );
  }

  Future<void> deletePlaylist(String id) async {
    if (kIsWeb || _db == null) return;
    await _db!.delete('playlists', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addToPlaylist(String playlistId, String songId) async {
    if (kIsWeb || _db == null) return;
    final playlist = await getPlaylist(playlistId);
    if (playlist != null && !playlist.songIds.contains(songId)) {
      playlist.songIds.add(songId);
      await updatePlaylist(playlist);
    }
  }

  Future<void> removeFromPlaylist(String playlistId, String songId) async {
    if (kIsWeb || _db == null) return;
    final playlist = await getPlaylist(playlistId);
    if (playlist != null) {
      playlist.songIds.remove(songId);
      await updatePlaylist(playlist);
    }
  }

  // ═══ Listening Progress (audiobook-weighted resume) ═══

  ListeningProgress _mapToListeningProgress(Map<String, Object?> map) {
    final modeRaw = (map['content_mode'] as String?) ?? 'audiobook';
    final mode =
        modeRaw == 'music' ? ContentMode.music : ContentMode.audiobook;

    return ListeningProgress(
      seriesKey: map['series_key'] as String,
      title: map['title'] as String,
      artist: map['artist'] as String?,
      lastSongPath: map['last_song_path'] as String,
      lastMediaId: map['last_media_id'] as int?,
      positionMs: map['position_ms'] as int? ?? 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        map['updated_at'] as int? ?? 0,
      ),
      contentMode: mode,
    );
  }

  Future<void> upsertListeningProgress(ListeningProgress progress) async {
    if (kIsWeb || _db == null) return;

    await _db!.insert(
      'listening_progress',
      {
        'series_key': progress.seriesKey,
        'title': progress.title,
        'artist': progress.artist,
        'last_song_path': progress.lastSongPath,
        'last_media_id': progress.lastMediaId,
        'position_ms': progress.positionMs,
        'updated_at': progress.updatedAt.millisecondsSinceEpoch,
        'content_mode':
            progress.contentMode == ContentMode.music ? 'music' : 'audiobook',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ListeningProgress?> getListeningProgress(String seriesKey) async {
    if (kIsWeb || _db == null || seriesKey.isEmpty) return null;

    final maps = await _db!.query(
      'listening_progress',
      where: 'series_key = ?',
      whereArgs: [seriesKey],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return _mapToListeningProgress(maps.first);
  }

  Future<List<ListeningProgress>> getRecentListeningProgress({
    int limit = 8,
  }) async {
    if (kIsWeb || _db == null) return [];

    final maps = await _db!.query(
      'listening_progress',
      orderBy: 'updated_at DESC',
      limit: limit,
    );
    return maps.map(_mapToListeningProgress).toList();
  }

  Future<void> deleteListeningProgress(String seriesKey) async {
    if (kIsWeb || _db == null || seriesKey.isEmpty) return;
    await _db!.delete(
      'listening_progress',
      where: 'series_key = ?',
      whereArgs: [seriesKey],
    );
  }

  // ═══ Bookmarks ═══

  Future<void> _rekeyLegacyBookmarksForCanonical(String canonicalKey) async {
    if (kIsWeb || _db == null || canonicalKey.isEmpty) return;

    try {
      final legacy = await _db!.query(
        'bookmarks',
        where: r"LOWER(REPLACE(track_key, '\', '/')) = ? AND track_key != ?",
        whereArgs: [canonicalKey, canonicalKey],
      );

      for (final row in legacy) {
        final id = (row['id'] as num).toInt();
        final pos = (row['position_ms'] as num).toInt();
        final conflict = await _db!.query(
          'bookmarks',
          where: 'track_key = ? AND position_ms = ?',
          whereArgs: [canonicalKey, pos],
          limit: 1,
        );

        if (conflict.isNotEmpty) {
          await _db!.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
        } else {
          await _db!.update(
            'bookmarks',
            {'track_key': canonicalKey},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[BOOKMARKS] legacy rekey failed: $e');
        debugPrint('$st');
      }
    }
  }

  Future<List<Map<String, dynamic>>> getBookmarksForTrack(String trackKey) async {
    final key = BookmarkKey.canonical(trackKey);
    await ensureBookmarksReady();
    if (kIsWeb || _db == null || key.isEmpty) {
      if (kDebugMode && !kIsWeb && _db == null) {
        debugPrint('[BOOKMARKS] load skipped: database not open');
      }
      return [];
    }

    try {
      await _rekeyLegacyBookmarksForCanonical(key);

      final maps = await _db!.query(
        'bookmarks',
        where: 'track_key = ?',
        whereArgs: [key],
        orderBy: 'position_ms ASC',
      );

      return maps
          .map(
            (row) => <String, dynamic>{
              'id': (row['id'] as num).toInt(),
              'pos': (row['position_ms'] as num).toInt(),
              'note': (row['note'] as String?) ?? '',
            },
          )
          .toList(growable: false);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[BOOKMARKS] load failed: $e');
        debugPrint('$st');
      }
      return [];
    }
  }

  Future<bool> upsertBookmark({
    required String trackKey,
    required int positionMs,
    required String note,
  }) async {
    if (kIsWeb) return false;
    final key = BookmarkKey.canonical(trackKey);
    await ensureBookmarksReady();
    if (_db == null) {
      if (kDebugMode) {
        debugPrint('[BOOKMARKS] upsert skipped: database not open');
      }
      return false;
    }
    if (key.isEmpty) return false;

    try {
      final rowId = await _db!.insert(
        'bookmarks',
        {
          'track_key': key,
          'position_ms': positionMs,
          'note': note,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (kDebugMode) {
        debugPrint(
          '[BOOKMARKS] upsert ok id=$rowId key=$key pos=$positionMs',
        );
      }
      return true;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[BOOKMARKS] upsert failed: $e');
        debugPrint('$st');
      }
      return false;
    }
  }

  Future<void> updateBookmarkNote(int id, String note) async {
    if (kIsWeb || _db == null) return;
    await _db!.update(
      'bookmarks',
      {'note': note},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteBookmark(int id) async {
    if (kIsWeb || _db == null) return;
    await _db!.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }
}
