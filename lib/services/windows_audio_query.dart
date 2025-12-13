import 'dart:io';
import 'dart:isolate';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path/path.dart' as p;

import 'settings_service.dart';

class WindowsAudioQuery {
  static final WindowsAudioQuery _instance = WindowsAudioQuery._();
  static WindowsAudioQuery get instance => _instance;
  WindowsAudioQuery._();

  Set<String> _audioExtensionsFromSettings() {
    final exts = SettingsService.instance.windowsScanExtensions;
    if (exts.isEmpty) {
      return {
        '.mp3',
        '.m4a',
        '.aac',
        '.wav',
        '.flac',
        '.ogg',
        '.wma',
        '.opus',
        '.aiff',
        '.alac',
      };
    }
    return exts
        .map((e) => e.startsWith('.') ? e.toLowerCase() : '.${e.toLowerCase()}')
        .toSet();
  }

  // Allows callers to cancel an in-flight isolate scan.
  // Safe to call cancel() before the worker has sent back its control port.
  static WindowsScanCancelToken newCancelToken() => WindowsScanCancelToken._();

  static void _scanWorker(List<dynamic> args) async {
    final SendPort port = args[0] as SendPort;
    final List<String> dirPaths = (args[1] as List).cast<String>();
    final bool recursive = args[2] as bool;
    final Set<String> audioExtensions =
        ((args[3] as List).cast<String>()).toSet();

    final cancelRp = ReceivePort();
    bool cancelled = false;
    cancelRp.listen((msg) {
      if (msg == 'cancel') cancelled = true;
    });
    port.send({'type': 'control', 'port': cancelRp.sendPort});

    int found = 0;
    int scannedFiles = 0;
    final songs = <Map<String, Object?>>[];

    final progressSw = Stopwatch()..start();

    void sendProgress(int dirIndex, int dirCount) {
      port.send({
        'type': 'progress',
        'dirIndex': dirIndex,
        'dirCount': dirCount,
        'scannedFiles': scannedFiles,
        'foundSongs': found,
      });
    }

    for (int d = 0; d < dirPaths.length; d++) {
      if (cancelled) {
        cancelRp.close();
        port.send({'type': 'cancelled', 'songs': songs});
        return;
      }
      final dir = Directory(dirPaths[d]);
      if (!await dir.exists()) {
        sendProgress(d + 1, dirPaths.length);
        continue;
      }

      port.send({
        'type': 'dir',
        'dirIndex': d + 1,
        'dirCount': dirPaths.length,
        'path': dir.path,
      });

      try {
        final entities = dir.list(recursive: recursive, followLinks: false);
        await for (final entity in entities) {
          if (cancelled) {
            cancelRp.close();
            port.send({'type': 'cancelled', 'songs': songs});
            return;
          }
          if (entity is File) {
            scannedFiles++;
            final ext = p.extension(entity.path).toLowerCase();
            if (audioExtensions.contains(ext)) {
              found++;
              final name = p.basenameWithoutExtension(entity.path);
              songs.add({
                '_id': entity.path.hashCode,
                '_data': entity.path,
                '_display_name': p.basename(entity.path),
                'title': name,
                'artist': 'Unknown Artist',
                'album': 'Unknown Album',
                'duration': 0,
                'is_music': true,
              });
            }

            if (scannedFiles % 500 == 0 ||
                progressSw.elapsedMilliseconds >= 250) {
              progressSw.reset();
              sendProgress(d + 1, dirPaths.length);
            }

            // Yield periodically to avoid hammering the disk too aggressively.
            if (scannedFiles % 2500 == 0) {
              await Future<void>.delayed(const Duration(milliseconds: 1));
            }
          }
        }
      } catch (_) {
        // Ignore per-folder errors.
      }

      sendProgress(d + 1, dirPaths.length);
    }

    cancelRp.close();
    port.send({'type': 'done', 'songs': songs});
  }

  Future<List<SongModel>> querySongsIsolated({
    void Function(
      int scannedFiles,
      int foundSongs,
      int dirIndex,
      int dirCount,
      String? dirPath,
    )?
    onProgress,
    WindowsScanCancelToken? cancelToken,
  }) async {
    final extSet = _audioExtensionsFromSettings();
    final recursive = SettingsService.instance.windowsScanRecursive;

    final configured = SettingsService.instance.windowsScanFolders;
    final dirPaths = <String>[];

    if (configured.isNotEmpty) {
      dirPaths.addAll(configured);
    } else {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null) {
        dirPaths.add(p.join(userProfile, 'Music'));
        dirPaths.add(p.join(userProfile, 'Downloads'));
      }
    }

    final rp = ReceivePort();
    final isolate = await Isolate.spawn(_scanWorker, [
      rp.sendPort,
      dirPaths,
      recursive,
      extSet.toList(),
    ], debugName: 'WindowsAudioQuery.scan');

    final songs = <SongModel>[];
    final completer = Completer<List<SongModel>>();

    rp.listen((msg) {
      if (msg is Map) {
        final type = msg['type'];
        if (type == 'control') {
          final sp = msg['port'];
          if (sp is SendPort) {
            cancelToken?._bind(sp);
          }
          return;
        }
        if (type == 'progress' || type == 'dir') {
          onProgress?.call(
            (msg['scannedFiles'] as int?) ?? 0,
            (msg['foundSongs'] as int?) ?? 0,
            (msg['dirIndex'] as int?) ?? 0,
            (msg['dirCount'] as int?) ?? 0,
            msg['path'] as String?,
          );
        } else if (type == 'done' || type == 'cancelled') {
          final raw = (msg['songs'] as List).cast<Map>();
          for (final m in raw) {
            songs.add(SongModel(m));
          }
          rp.close();
          isolate.kill(priority: Isolate.immediate);
          completer.complete(songs);
        }
      }
    });

    return completer.future;
  }

  Future<List<SongModel>> querySongs() async {
    debugPrint('WindowsAudioQuery: Starting scan...');
    final songs = <SongModel>[];

    try {
      final extSet = _audioExtensionsFromSettings();
      final recursive = SettingsService.instance.windowsScanRecursive;

      final configured = SettingsService.instance.windowsScanFolders;
      final dirs = <Directory>[];

      if (configured.isNotEmpty) {
        dirs.addAll(configured.map((d) => Directory(d)));
      } else {
        // Default fallback: USERPROFILE/Music + USERPROFILE/Downloads
        final userProfile = Platform.environment['USERPROFILE'];
        if (userProfile == null) {
          debugPrint('WindowsAudioQuery: USERPROFILE not found');
          return [];
        }
        dirs.add(Directory(p.join(userProfile, 'Music')));
        dirs.add(Directory(p.join(userProfile, 'Downloads')));
      }

      for (final dir in dirs) {
        if (await dir.exists()) {
          debugPrint('WindowsAudioQuery: Scanning ${dir.path}');
          await _scanDirectory(
            dir,
            songs,
            recursive: recursive,
            audioExtensions: extSet,
          );
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

  Future<List<SongModel>> querySongsFromDirectory(String directoryPath) async {
    debugPrint('WindowsAudioQuery: Scanning directory $directoryPath');
    final songs = <SongModel>[];

    try {
      final dir = Directory(directoryPath);
      if (await dir.exists()) {
        await _scanDirectory(
          dir,
          songs,
          recursive: SettingsService.instance.windowsScanRecursive,
          audioExtensions: _audioExtensionsFromSettings(),
        );
      } else {
        debugPrint('WindowsAudioQuery: Directory not found: $directoryPath');
      }
    } catch (e) {
      debugPrint('WindowsAudioQuery: Error querying songs from directory: $e');
    }

    debugPrint(
      'WindowsAudioQuery: Found ${songs.length} songs in $directoryPath',
    );
    return songs;
  }

  Future<void> _scanDirectory(
    Directory dir,
    List<SongModel> songs, {
    required bool recursive,
    required Set<String> audioExtensions,
  }) async {
    try {
      final entities = dir.list(recursive: recursive, followLinks: false);
      await for (final entity in entities) {
        if (entity is File) {
          final ext = p.extension(entity.path).toLowerCase();
          if (audioExtensions.contains(ext)) {
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

class WindowsScanCancelToken {
  WindowsScanCancelToken._();

  SendPort? _port;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _port?.send('cancel');
  }

  void _bind(SendPort port) {
    _port = port;
    if (_cancelled) {
      _port?.send('cancel');
    }
  }
}
