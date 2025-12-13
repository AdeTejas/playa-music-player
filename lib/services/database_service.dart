import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/song_metadata.dart';
import '../models/playlist.dart';

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

  Future<void> init() async {
    if (_isInitialized) return;

    if (kIsWeb) {
      debugPrint(
        'DatabaseService: Web detected, skipping SQLite initialization.',
      );
      _isInitialized = true;
      return;
    }

    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, 'playa.db');
    _dbPath = path;

    _db = await openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    _isInitialized = true;
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
        song_ids TEXT
      )
    ''');
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
      songIds: songIds,
    );
  }

  Future<void> createPlaylist(Playlist playlist) async {
    if (kIsWeb || _db == null) return;
    await _db!.insert('playlists', {
      'id': playlist.id,
      'name': playlist.name,
      'song_ids': json.encode(playlist.songIds),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updatePlaylist(Playlist playlist) async {
    if (kIsWeb || _db == null) return;
    await _db!.update(
      'playlists',
      {'name': playlist.name, 'song_ids': json.encode(playlist.songIds)},
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
}
