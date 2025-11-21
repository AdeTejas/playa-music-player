import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;

class WindowsAudioQuery {
  static final WindowsAudioQuery _instance = WindowsAudioQuery._();
  static WindowsAudioQuery get instance => _instance;
  WindowsAudioQuery._();

  final _audioExtensions = {
    '.mp3', '.m4a', '.aac', '.wav', '.flac', '.ogg', '.wma', '.opus', '.aiff', '.alac'
  };

  Future<List<SongModel>> querySongs() async {
    debugPrint('WindowsAudioQuery: Starting scan...');
    final songs = <SongModel>[];
    
    try {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile == null) {
        debugPrint('WindowsAudioQuery: USERPROFILE not found');
        return [];
      }

      final musicDir = Directory(p.join(userProfile, 'Music'));
      final downloadsDir = Directory(p.join(userProfile, 'Downloads'));
      
      final dirs = [musicDir, downloadsDir];
      
      for (final dir in dirs) {
        if (await dir.exists()) {
          debugPrint('WindowsAudioQuery: Scanning ${dir.path}');
          await _scanDirectory(dir, songs);
        } else {
          debugPrint('WindowsAudioQuery: Directory not found: ${dir.path}');
        }
      }
    } catch (e) {
      debugPrint('WindowsAudioQuery: Error querying songs: $e');
    }
    
    debugPrint('WindowsAudioQuery: Found ${songs.length} songs');
    return songs;
  }

  Future<void> _scanDirectory(Directory dir, List<SongModel> songs) async {
    try {
      final entities = dir.list(recursive: true, followLinks: false);
      await for (final entity in entities) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (_audioExtensions.contains(ext)) {
            songs.add(_fileToSongModel(entity));
          }
        }
      }
    } catch (e) {
      debugPrint('Error scanning directory ${dir.path}: $e');
    }
  }

  SongModel _fileToSongModel(File file) {
    final name = p.basenameWithoutExtension(file.path);
    return SongModel({
      '_id': file.path.hashCode,
      '_data': file.path,
      '_display_name': p.basename(file.path),
      'title': name,
      'artist': 'Unknown Artist',
      'album': 'Unknown Album',
      'duration': 0,
      'is_music': true,
    });
  }
}
