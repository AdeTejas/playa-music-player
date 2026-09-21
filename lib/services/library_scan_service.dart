import 'dart:async';
import 'dart:io';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart' as oaq;

import '../services/android_audio_query.dart';
import '../services/windows_audio_query.dart';
import '../services/settings_service.dart';
import '../utils/ui_utils.dart';
import '../utils/song_tag_enricher.dart';
import 'service_locator.dart';

enum LibraryScanPhase {
  idle,
  requestingPermissions,
  querying,
  filtering,
  updating,
  done,
  error,
}

class LibraryScanService extends ChangeNotifier {
  static final LibraryScanService instance = LibraryScanService._();
  LibraryScanService._();

  LibraryScanPhase _phase = LibraryScanPhase.idle;
  LibraryScanPhase get phase => _phase;

  double _progress = 0.0;
  double get progress => _progress;

  String? _lastError;
  String? get lastError => _lastError;

  DateTime? _lastScanAt;
  DateTime? get lastScanAt => _lastScanAt;

  Duration? _lastScanDuration;
  Duration? get lastScanDuration => _lastScanDuration;

  int _lastSongCount = 0;
  int get lastSongCount => _lastSongCount;

  int _scanId = 0;
  WindowsScanCancelToken? _windowsCancelToken;

  bool get isScanning =>
      _phase != LibraryScanPhase.idle &&
      _phase != LibraryScanPhase.done &&
      _phase != LibraryScanPhase.error;

  void cancelScan() {
    _scanId++;
    _windowsCancelToken?.cancel();
    _windowsCancelToken = null;
    if (isScanning) {
      _setPhase(LibraryScanPhase.idle, progress: 0.0);
    }
  }

  bool _sameSongList(List<oaq.SongModel> a, List<oaq.SongModel> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      final sa = a[i];
      final sb = b[i];
      if (sa.id != sb.id) return false;
      if (sa.data != sb.data) return false;
    }
    return true;
  }

  static List<oaq.SongModel> _filterSongsIsolate(List<oaq.SongModel> songs) {
    const supportedExtensions = {
      'mp3',
      'aac',
      'ogg',
      'wav',
      'flac',
      'm4a',
      'opus',
    };
    return songs.where((song) {
      final data = song.data;
      if (data.isEmpty) return false;
      final dot = data.lastIndexOf('.');
      if (dot < 0 || dot == data.length - 1) return false;
      final ext = data.substring(dot + 1).toLowerCase();
      return supportedExtensions.contains(ext);
    }).toList();
  }

  List<oaq.SongModel> _dedupeByData(List<oaq.SongModel> songs) {
    if (songs.isEmpty) return songs;
    // Preserve the original scan order.
    final out = <oaq.SongModel>[];
    final seen = HashSet<String>();
    for (final s in songs) {
      final key = songIdentity(s);
      if (key.isEmpty) continue;
      if (seen.add(key)) out.add(s);
    }
    return out;
  }

  /// Client-side sort that respects current library sort settings.
  List<oaq.SongModel> sortSongs(List<oaq.SongModel> songs) =>
      _sortSongs(songs);

  /// This is essential for Windows (native sort not supported) and acts as
  /// a safety net for other platforms.
  List<oaq.SongModel> _sortSongs(List<oaq.SongModel> songs) {
    if (songs.length < 2) return songs;

    final sortType = SettingsService.instance.librarySortType;
    final descending = SettingsService.instance.librarySortOrder == 1;

    int compare(oaq.SongModel a, oaq.SongModel b) {
      int result;
      switch (sortType) {
        case 'TITLE':
          result = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          break;
        case 'ARTIST':
          result = (a.artist ?? '').toLowerCase().compareTo((b.artist ?? '').toLowerCase());
          break;
        case 'ALBUM':
          result = (a.album ?? '').toLowerCase().compareTo((b.album ?? '').toLowerCase());
          break;
        case 'DATE_ADDED':
        default:
          result = (a.dateAdded ?? 0).compareTo(b.dateAdded ?? 0);
          break;
      }
      return descending ? -result : result;
    }

    final sorted = List<oaq.SongModel>.from(songs);
    sorted.sort(compare);
    return sorted;
  }

  void _setPhase(LibraryScanPhase phase, {double? progress, String? error}) {
    _phase = phase;
    if (progress != null) _progress = progress.clamp(0.0, 1.0);
    if (error != null) _lastError = error;
    notifyListeners();
  }

  Future<List<oaq.SongModel>> scanLibrary({
    String? path,
    bool restorePlayerState = true,
    bool force = false,
  }) async {
    if (kIsWeb) return [];

    if (!force && path == null && !isScanning) {
      final cached = ServiceLocator.instance.playerController.librarySongs;
      if (cached.isNotEmpty &&
          _phase == LibraryScanPhase.done &&
          _lastScanAt != null &&
          DateTime.now().difference(_lastScanAt!) <
              const Duration(minutes: 30)) {
        return cached;
      }
    }

    // Cancel any in-flight scan and start a new generation.
    cancelScan();
    final myScanId = _scanId;

    final sw = Stopwatch()..start();

    _lastError = null;
    _setPhase(LibraryScanPhase.querying, progress: 0.05);

    try {
      final settings = SettingsService.instance;
      final sortType = _getSortType(settings.librarySortType);
      final orderType = _getOrderType(settings.librarySortOrder);

      List<oaq.SongModel> songs;

      if (Platform.isWindows) {
        final token = WindowsAudioQuery.newCancelToken();
        _windowsCancelToken = token;
        if (path == null) {
          songs = await WindowsAudioQuery.instance.querySongsIsolated(
            onProgress: (
              scannedFiles,
              foundSongs,
              dirIndex,
              dirCount,
              dirPath,
            ) {
              // Heuristic progress: folder-based with a cap inside querying.
              final denom = dirCount == 0 ? 1 : dirCount;
              final p = 0.05 + 0.55 * (dirIndex / denom);
              _lastSongCount = foundSongs;
              _setPhase(LibraryScanPhase.querying, progress: p);
            },
            cancelToken: token,
          );
        } else {
          songs = await WindowsAudioQuery.instance.querySongsFromDirectory(
            path,
          );
        }
      } else if (Platform.isAndroid && path != null) {
        songs = await AndroidAudioQuery.instance.querySongsFromDirectory(path);
      } else {
        final query = oaq.OnAudioQuery();
        songs = await query.querySongs(
          path: path,
          sortType: sortType,
          orderType: orderType,
          uriType: oaq.UriType.EXTERNAL,
          ignoreCase: true,
        );
      }

      if (myScanId != _scanId) return const <oaq.SongModel>[];

      _setPhase(LibraryScanPhase.filtering, progress: 0.65);
      final List<oaq.SongModel> filteredSongs;
      if (Platform.isWindows) {
        // Windows isolate already filters by extension; keep this step cheap.
        filteredSongs = songs
            .where((s) => s.data.isNotEmpty)
            .toList(growable: false);
      } else {
        filteredSongs = await compute(_filterSongsIsolate, songs);
      }

      // Guard against duplicate results (some devices/scans can return duplicates).
      var dedupedSongs = _dedupeByData(filteredSongs);

      // Strengthen Unknown Artist / filename-as-title when tags are readable.
      if (!Platform.isWindows) {
        _setPhase(LibraryScanPhase.filtering, progress: 0.72);
        dedupedSongs = await SongTagEnricher.enrichWeakTags(dedupedSongs);
      }

      // Apply current sort settings (critical for Windows where native sort is not used).
      final sortedSongs = _sortSongs(dedupedSongs);

      if (myScanId != _scanId) return const <oaq.SongModel>[];

      _setPhase(LibraryScanPhase.updating, progress: 0.9);
      _lastScanAt = DateTime.now();
      _lastSongCount = sortedSongs.length;

      // Keep PlayerController's library cache in sync.
      final ctrl = ServiceLocator.instance.playerController;
      final unchanged = _sameSongList(ctrl.librarySongs, sortedSongs);
      if (!unchanged) {
        ctrl.updateLibrary(sortedSongs);
        if (restorePlayerState) {
          // Safe: replaceQueue drops missing files via _buildSource.
          await ctrl.restoreState(sortedSongs);
        }
      }

      _setPhase(LibraryScanPhase.done, progress: 1.0);
      _windowsCancelToken = null;
      sw.stop();
      _lastScanDuration = sw.elapsed;
      return sortedSongs;
    } catch (e) {
      sw.stop();
      _lastScanDuration = sw.elapsed;
      _windowsCancelToken = null;
      _setPhase(LibraryScanPhase.error, progress: 1.0, error: e.toString());
      return [];
    }
  }

  oaq.SongSortType _getSortType(String type) {
    switch (type) {
      case 'TITLE':
        return oaq.SongSortType.TITLE;
      case 'ARTIST':
        return oaq.SongSortType.ARTIST;
      case 'ALBUM':
        return oaq.SongSortType.ALBUM;
      case 'DATE_ADDED':
      default:
        return oaq.SongSortType.DATE_ADDED;
    }
  }

  oaq.OrderType _getOrderType(int order) {
    return order == 1
        ? oaq.OrderType.DESC_OR_GREATER
        : oaq.OrderType.ASC_OR_SMALLER;
  }
}
