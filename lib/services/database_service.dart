import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/song_metadata.dart';
import '../models/playlist.dart';

class DatabaseService {
  static DatabaseService? _instance;
  static DatabaseService get instance => _instance ??= DatabaseService._();
  DatabaseService._();

  late Database _db;
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, 'playa.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
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
        key TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE playlists (
        id TEXT PRIMARY KEY,
        name TEXT,
        song_ids TEXT
      )
    ''');
  }

  // ═══ Song Metadata ═══
  
  Future<SongMetadata?> getSongMetadata(String songId) async {
    final maps = await _db.query(
      'song_metadata',
      where: 'song_id = ?',
      whereArgs: [songId],
    );
    if (maps.isEmpty) return null;

    final map = maps.first;
    return SongMetadata(
      id: map['song_id'] as String,
      rating: map['rating'] as int?,
      lyrics: map['lyrics'] as String?,
      playCount: map['play_count'] as int? ?? 0,
      lastPlayed: map['last_played'] != null ? DateTime.fromMillisecondsSinceEpoch(map['last_played'] as int) : null,
      bpm: map['bpm'] as double?,
      key: map['key'] as String?,
    );
  }

  Future<void> updateRating(String songId, int rating) async {
    await _db.insert(
      'song_metadata',
      {'song_id': songId, 'rating': rating},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> saveLyrics(String songId, String lyrics, {String? source}) async {
    await _db.insert(
      'song_metadata',
      {'song_id': songId, 'lyrics': lyrics},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateLastPlayed(String songId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.insert(
      'song_metadata',
      {'song_id': songId, 'last_played': now},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> incrementPlayCount(String songId) async {
    final current = await getSongMetadata(songId);
    final count = (current?.playCount ?? 0) + 1;
    await _db.insert(
      'song_metadata',
      {'song_id': songId, 'play_count': count},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateSonicDna(String songId, double bpm, String key) async {
    await _db.insert(
      'song_metadata',
      {'song_id': songId, 'bpm': bpm, 'key': key},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<SongMetadata>> getAllSongMetadata() async {
    final maps = await _db.query('song_metadata');
    return maps.map((map) => SongMetadata(
      id: map['song_id'] as String,
      rating: map['rating'] as int?,
      lyrics: map['lyrics'] as String?,
      playCount: map['play_count'] as int? ?? 0,
      lastPlayed: map['last_played'] != null ? DateTime.fromMillisecondsSinceEpoch(map['last_played'] as int) : null,
      bpm: map['bpm'] as double?,
      key: map['key'] as String?,
    )).toList();
  }

  Future<List<SongMetadata>> getMostPlayed({int limit = 20}) async {
    final maps = await _db.query(
      'song_metadata',
      orderBy: 'play_count DESC',
      limit: limit,
    );
    return maps.map((map) => SongMetadata(
      id: map['song_id'] as String,
      rating: map['rating'] as int?,
      lyrics: map['lyrics'] as String?,
      playCount: map['play_count'] as int? ?? 0,
      lastPlayed: map['last_played'] != null ? DateTime.fromMillisecondsSinceEpoch(map['last_played'] as int) : null,
      bpm: map['bpm'] as double?,
      key: map['key'] as String?,
    )).toList();
  }

  Future<List<SongMetadata>> getRecentlyPlayed({int limit = 20}) async {
    final maps = await _db.query(
      'song_metadata',
      orderBy: 'last_played DESC',
      limit: limit,
    );
    return maps.map((map) => SongMetadata(
      id: map['song_id'] as String,
      rating: map['rating'] as int?,
      lyrics: map['lyrics'] as String?,
      playCount: map['play_count'] as int? ?? 0,
      lastPlayed: map['last_played'] != null ? DateTime.fromMillisecondsSinceEpoch(map['last_played'] as int) : null,
      bpm: map['bpm'] as double?,
      key: map['key'] as String?,
    )).toList();
  }

  // ═══ Playlists ═══
  
  Future<List<Playlist>> getAllPlaylists() async {
    final maps = await _db.query('playlists');
    return maps.map((map) {
      final songIdsJson = map['song_ids'] as String?;
      final songIds = songIdsJson != null ? List<String>.from(json.decode(songIdsJson)) : <String>[];
      return Playlist(
        id: map['id'] as String,
        name: map['name'] as String,
        songIds: songIds,
      );
    }).toList();
  }

  Future<Playlist?> getPlaylist(String id) async {
    final maps = await _db.query(
      'playlists',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;

    final map = maps.first;
    final songIdsJson = map['song_ids'] as String?;
    final songIds = songIdsJson != null ? List<String>.from(json.decode(songIdsJson)) : <String>[];
    return Playlist(
      id: map['id'] as String,
      name: map['name'] as String,
      songIds: songIds,
    );
  }

  Future<void> createPlaylist(Playlist playlist) async {
    await _db.insert(
      'playlists',
      {
        'id': playlist.id,
        'name': playlist.name,
        'song_ids': json.encode(playlist.songIds),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updatePlaylist(Playlist playlist) async {
    await _db.update(
      'playlists',
      {
        'name': playlist.name,
        'song_ids': json.encode(playlist.songIds),
      },
      where: 'id = ?',
      whereArgs: [playlist.id],
    );
  }

  Future<void> deletePlaylist(String id) async {
    await _db.delete(
      'playlists',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> addToPlaylist(String playlistId, String songId) async {
    final playlist = await getPlaylist(playlistId);
    if (playlist != null && !playlist.songIds.contains(songId)) {
      playlist.songIds.add(songId);
      await updatePlaylist(playlist);
    }
  }

  Future<void> removeFromPlaylist(String playlistId, String songId) async {
    final playlist = await getPlaylist(playlistId);
    if (playlist != null) {
      playlist.songIds.remove(songId);
      await updatePlaylist(playlist);
    }
  }
}
