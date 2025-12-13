import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart' as oaq;
import 'package:path_provider/path_provider.dart';

class ArtworkCacheService {
  ArtworkCacheService._();
  static final ArtworkCacheService instance = ArtworkCacheService._();

  static const int _maxEntries = 220;
  static const int _maxDiskFiles = 600;
  static const int _diskPruneEveryNWrites = 25;

  // Map literals are insertion-ordered (LinkedHashMap) in Dart.
  final Map<String, Uint8List> _lru = <String, Uint8List>{};
  final Map<String, Future<Uint8List?>> _inflight =
      <String, Future<Uint8List?>>{};

  Directory? _diskDir;
  int _diskWriteCount = 0;

  String _key({
    required int id,
    required oaq.ArtworkType type,
    required int size,
    required oaq.ArtworkFormat format,
  }) {
    return '${type.index}:$id:$size:${format.index}';
  }

  String _fileNameForKey(String key, oaq.ArtworkFormat format) {
    final safe = base64UrlEncode(utf8.encode(key));
    final ext = switch (format) {
      oaq.ArtworkFormat.PNG => 'png',
      _ => 'jpg',
    };
    return '$safe.$ext';
  }

  Future<Directory?> _ensureDiskDir() async {
    if (!_supportedPlatform) return null;
    if (_diskDir != null) return _diskDir;
    try {
      final base = await getTemporaryDirectory();
      final dir = Directory(
        '${base.path}${Platform.pathSeparator}artwork_cache',
      );
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _diskDir = dir;
      return dir;
    } catch (_) {
      return null;
    }
  }

  Future<File?> _diskFileFor({
    required int id,
    required oaq.ArtworkType type,
    required int size,
    required oaq.ArtworkFormat format,
  }) async {
    final dir = await _ensureDiskDir();
    if (dir == null) return null;
    final key = _key(id: id, type: type, size: size, format: format);
    return File(
      '${dir.path}${Platform.pathSeparator}${_fileNameForKey(key, format)}',
    );
  }

  Uint8List? _getBestMemoryMatch({
    required int id,
    required oaq.ArtworkType type,
    required int minSize,
    required oaq.ArtworkFormat format,
  }) {
    final prefix = '${type.index}:$id:';
    Uint8List? best;
    int? bestSize;

    for (final entry in _lru.entries) {
      final k = entry.key;
      if (!k.startsWith(prefix)) continue;
      final parts = k.split(':');
      if (parts.length != 4) continue;
      final fmt = int.tryParse(parts[3]);
      if (fmt == null || fmt != format.index) continue;
      final sz = int.tryParse(parts[2]);
      if (sz == null || sz < minSize) continue;
      if (bestSize == null || sz < bestSize) {
        bestSize = sz;
        best = entry.value;
      }
    }
    return best;
  }

  Iterable<int> _diskSizeCandidates(int requested) sync* {
    // Common UI sizes (ascending), but always include requested first.
    final candidates = <int>{
      requested,
      64,
      96,
      128,
      200,
      300,
      400,
      600,
      800,
      1000,
      1200,
    }.toList(growable: false)..sort();

    // We want the smallest cached size >= requested.
    for (final s in candidates) {
      if (s >= requested) yield s;
    }
  }

  Future<Uint8List?> _readFromDiskBestEffort({
    required int id,
    required oaq.ArtworkType type,
    required int minSize,
    required oaq.ArtworkFormat format,
  }) async {
    final dir = await _ensureDiskDir();
    if (dir == null) return null;

    for (final s in _diskSizeCandidates(minSize)) {
      final file = await _diskFileFor(
        id: id,
        type: type,
        size: s,
        format: format,
      );
      if (file == null) return null;
      try {
        if (!await file.exists()) continue;
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) continue;
        return bytes;
      } catch (_) {
        // Ignore and try next candidate.
      }
    }
    return null;
  }

  Future<void> _writeToDisk({
    required int id,
    required oaq.ArtworkType type,
    required int size,
    required oaq.ArtworkFormat format,
    required Uint8List bytes,
  }) async {
    final file = await _diskFileFor(
      id: id,
      type: type,
      size: size,
      format: format,
    );
    if (file == null) return;
    try {
      if (await file.exists()) return;
      await file.writeAsBytes(bytes, flush: false);
      _diskWriteCount++;
      if (_diskWriteCount % _diskPruneEveryNWrites == 0) {
        unawaited(_pruneDiskCache());
      }
    } catch (_) {
      // ignore
    }
  }

  Future<void> _pruneDiskCache() async {
    final dir = await _ensureDiskDir();
    if (dir == null) return;
    try {
      final files =
          await dir
              .list(followLinks: false)
              .where((e) => e is File)
              .cast<File>()
              .toList();
      if (files.length <= _maxDiskFiles) return;

      files.sort((a, b) {
        final at = a.lastModifiedSync();
        final bt = b.lastModifiedSync();
        return at.compareTo(bt);
      });

      final toDelete = files.length - _maxDiskFiles;
      for (int i = 0; i < toDelete; i++) {
        try {
          await files[i].delete();
        } catch (_) {}
      }
    } catch (_) {
      // ignore
    }
  }

  bool get _supportedPlatform {
    if (kIsWeb) return false;
    return !(Platform.isWindows || Platform.isLinux);
  }

  Future<Uint8List?> getArtworkBytes({
    required int id,
    required oaq.ArtworkType type,
    int size = 300,
    oaq.ArtworkFormat format = oaq.ArtworkFormat.JPEG,
  }) async {
    if (!_supportedPlatform) return null;

    final key = _key(id: id, type: type, size: size, format: format);

    // 1) Exact in-memory hit.
    final exact = _lru.remove(key);
    if (exact != null) {
      _lru[key] = exact;
      return exact;
    }

    // 2) In-memory fallback: any cached size >= requested.
    final bestMem = _getBestMemoryMatch(
      id: id,
      type: type,
      minSize: size,
      format: format,
    );
    if (bestMem != null) {
      // Refresh LRU for whichever key it came from by reinserting best-effort.
      // (No-op if it was already last.)
      _lru[key] = bestMem;
      while (_lru.length > _maxEntries) {
        _lru.remove(_lru.keys.first);
      }
      return bestMem;
    }

    // 3) Dedupe concurrent fetches.
    final inflight = _inflight[key];
    if (inflight != null) return inflight;

    final future = () async {
      // 4) Disk cache best-effort (smallest >= requested).
      final disk = await _readFromDiskBestEffort(
        id: id,
        type: type,
        minSize: size,
        format: format,
      );
      if (disk != null && disk.isNotEmpty) {
        _lru[key] = disk;
        while (_lru.length > _maxEntries) {
          _lru.remove(_lru.keys.first);
        }
        return disk;
      }

      // 5) Query MediaStore.
      Uint8List? bytes;
      try {
        bytes = await oaq.OnAudioQuery().queryArtwork(
          id,
          type,
          format: format,
          size: size,
        );
      } catch (_) {
        bytes = null;
      }

      if (bytes == null || bytes.isEmpty) return null;

      _lru[key] = bytes;
      while (_lru.length > _maxEntries) {
        _lru.remove(_lru.keys.first);
      }

      unawaited(
        _writeToDisk(
          id: id,
          type: type,
          size: size,
          format: format,
          bytes: bytes,
        ),
      );
      return bytes;
    }();

    _inflight[key] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(key);
    }
  }

  Future<void> prefetchArtwork({
    required int id,
    required oaq.ArtworkType type,
    int size = 600,
    oaq.ArtworkFormat format = oaq.ArtworkFormat.JPEG,
  }) async {
    await getArtworkBytes(id: id, type: type, size: size, format: format);
  }

  void clear() {
    _lru.clear();
  }
}
