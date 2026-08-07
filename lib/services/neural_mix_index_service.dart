// lib/services/neural_mix_index_service.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart' as oaq;

import '../models/song_metadata.dart';
import '../repositories/song_repository.dart';
import '../utils/neural_mix_key.dart';
import '../utils/ui_utils.dart';
import 'library_scan_service.dart';
import 'service_locator.dart';
import 'sonic_dna_analysis_service.dart';

/// Warms the Neural Mix ranking index.
///
/// After a Sonic DNA scan completes (manual or scheduled), this pre-builds and
/// caches the parsed BPM/key/artist rows that `smartShuffle` ranks against, so
/// the first mix after a scan is instant — no `getAllMetadata()` + key parsing
/// at mix time. The cache is invalidated whenever the library changes.
class NeuralMixIndexService extends ChangeNotifier {
  NeuralMixIndexService._();
  static final NeuralMixIndexService instance = NeuralMixIndexService._();

  /// Cached song rows: `{id, artist, bpm, key}` — the exact shape the Neural
  /// Mix rank isolate consumes. Keys are pre-parsed by [parseNeuralMixKey] so
  /// mix time does not re-parse them.
  List<Map<String, dynamic>>? _songRows;

  bool _started = false;
  bool _warming = false;

  bool get isWarm => _songRows != null && _songRows!.isNotEmpty;
  List<Map<String, dynamic>>? get songRows => _songRows;

  /// Test hooks: bypass the real library/DB pipeline in unit tests.
  @visibleForTesting
  List<oaq.SongModel> Function()? songsOverride;
  @visibleForTesting
  Future<List<SongMetadata>> Function()? metadataOverride;

  void start() {
    if (_started) return;
    _started = true;
    SonicDnaAnalysisService.instance.addListener(_onAnalysisChanged);
    LibraryScanService.instance.addListener(_onLibraryChanged);
  }

  @override
  void dispose() {
    _started = false;
    SonicDnaAnalysisService.instance.removeListener(_onAnalysisChanged);
    LibraryScanService.instance.removeListener(_onLibraryChanged);
    super.dispose();
  }

  /// Resets singleton state between unit tests. Detaches listeners but does
  /// not dispose the notifier (it's a singleton).
  @visibleForTesting
  void resetForTest() {
    SonicDnaAnalysisService.instance.removeListener(_onAnalysisChanged);
    LibraryScanService.instance.removeListener(_onLibraryChanged);
    _started = false;
    _songRows = null;
    _warming = false;
  }

  void _onAnalysisChanged() {
    if (SonicDnaAnalysisService.instance.phase ==
        SonicDnaAnalysisPhase.done) {
      unawaited(warm());
    }
  }

  void _onLibraryChanged() {
    if (!LibraryScanService.instance.isScanning) {
      invalidate();
    }
  }

  /// Drops the cached index (e.g. when the library changes).
  void invalidate() {
    _songRows = null;
    notifyListeners();
  }

  /// Builds (or rebuilds) the cached index from the current library and
  /// metadata. No-op while already warming. Pass [songs]/[metas] to reuse
  /// already-fetched data (avoids a second DB read at mix time).
  Future<void> warm({
    List<oaq.SongModel>? songs,
    List<SongMetadata>? metas,
  }) async {
    if (_warming) return;
    _warming = true;
    try {
      final songList =
          songs ??
          songsOverride?.call() ??
          ServiceLocator.instance.playerController.librarySongs;
      if (songList.isEmpty) return;

      final metaList =
          metas ??
          await (metadataOverride?.call() ??
              SongRepository.instance.getAllMetadata());
      final metaMap = {for (final m in metaList) m.id: m};

      final rows = <Map<String, dynamic>>[];
      for (final song in songList) {
        final id = songIdentity(song);
        final meta = metaMap[id] ?? metaMap[song.id.toString()];
        final key = meta?.key;
        final parsed = key == null ? null : parseNeuralMixKey(key);
        rows.add({
          'id': id,
          'artist': song.artist ?? '',
          'bpm': meta?.bpm,
          'key': key,
          'keyPitch': parsed?.pitch,
          'keyMinor': parsed?.minor,
        });
      }
      _songRows = rows;
      notifyListeners();
    } finally {
      _warming = false;
    }
  }
}
