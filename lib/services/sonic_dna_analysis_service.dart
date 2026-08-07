// lib/services/sonic_dna_analysis_service.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart' as oaq;

import '../utils/sonic_dna_tag_reader.dart';
import '../utils/ui_utils.dart';
import 'database_service.dart';
import 'service_locator.dart';
import 'sonic_dna_android_analyzer.dart';

enum SonicDnaAnalysisPhase { idle, running, done, error }

/// Cancellable, resumable full-library BPM/Key analysis.
///
/// Pass 1 reads embedded tags (fast, all platforms). On Android, tracks with
/// no embedded BPM/Key fall through to the native deep analyzer. Completed
/// tracks store a file signature (`mtime:size`) in `song_metadata.dna_sig`,
/// so a cancelled run resumes by skipping everything already processed.
class SonicDnaAnalysisService extends ChangeNotifier {
  static final SonicDnaAnalysisService instance = SonicDnaAnalysisService._();
  SonicDnaAnalysisService._();

  SonicDnaAnalysisPhase _phase = SonicDnaAnalysisPhase.idle;
  SonicDnaAnalysisPhase get phase => _phase;

  double _progress = 0.0;
  double get progress => _progress;

  int _total = 0;
  int get total => _total;

  int _done = 0;
  int get done => _done;

  int _skipped = 0;
  int get skipped => _skipped;

  int _found = 0;
  int get found => _found;

  String? _lastError;
  String? get lastError => _lastError;

  Duration? _lastRunDuration;
  Duration? get lastRunDuration => _lastRunDuration;

  int _generation = 0;

  bool get isRunning => _phase == SonicDnaAnalysisPhase.running;

  /// Yield to the event loop every N tracks; coarser batches keep the UI
  /// responsive on very large libraries.
  int _yieldEvery(int total) => total > 800 ? 20 : 50;

  void cancel() {
    _generation++;
    if (isRunning) {
      _phase = SonicDnaAnalysisPhase.idle;
      notifyListeners();
    }
  }

  /// Analyze [songs] (defaults to the cached library). No-op while running.
  Future<void> startAnalysis({List<oaq.SongModel>? songs}) async {
    if (isRunning) return;

    final list =
        songs ?? ServiceLocator.instance.playerController.librarySongs;
    if (list.isEmpty) {
      _phase = SonicDnaAnalysisPhase.idle;
      notifyListeners();
      return;
    }

    _generation++;
    final myGen = _generation;

    _phase = SonicDnaAnalysisPhase.running;
    _total = list.length;
    _done = 0;
    _skipped = 0;
    _found = 0;
    _lastError = null;
    _progress = 0.0;
    notifyListeners();

    final sw = Stopwatch()..start();
    final yieldEvery = _yieldEvery(list.length);
    final db = DatabaseService.instance;

    try {
      for (int i = 0; i < list.length; i++) {
        if (myGen != _generation) {
          _phase = SonicDnaAnalysisPhase.idle;
          notifyListeners();
          return;
        }

        try {
          await _analyzeOne(db, list[i], myGen);
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Sonic DNA analysis failed: $e');
          }
        }

        _done = i + 1;
        _progress = _done / _total;
        if (i % yieldEvery == yieldEvery - 1) {
          await Future<void>.delayed(Duration.zero);
        }
        notifyListeners();
      }

      sw.stop();
      _lastRunDuration = sw.elapsed;
      _phase = SonicDnaAnalysisPhase.done;
      notifyListeners();
    } catch (e) {
      sw.stop();
      _lastRunDuration = sw.elapsed;
      _lastError = e.toString();
      _phase = SonicDnaAnalysisPhase.error;
      notifyListeners();
    }
  }

  Future<void> _analyzeOne(DatabaseService db, oaq.SongModel song, int gen) async {
    final path = song.data;
    if (path.isEmpty) {
      _skipped++;
      return;
    }

    final id = songIdentity(song);
    final signature = await _fileSignature(path);
    if (signature == null) {
      _skipped++;
      return;
    }

    final existing = await db.getSongMetadata(id);
    if (existing?.dnaSignature == signature) {
      _skipped++;
      return;
    }
    if (gen != _generation) return;

    var dna = await SonicDnaTagReader.readFromFilePath(path);
    if (gen != _generation) return;

    // Deep analysis is Android-only today; everything else stays tag-based.
    if (dna.bpm == null &&
        dna.key == null &&
        defaultTargetPlatform == TargetPlatform.android) {
      final res = await SonicDnaAndroidAnalyzer.analyze(path);
      if (gen != _generation) return;
      dna = (bpm: dna.bpm ?? res.bpm, key: dna.key ?? res.key);
    }

    await db.updateSonicDna(
      id,
      bpm: dna.bpm,
      key: dna.key,
      dnaSignature: signature,
    );
    if (dna.bpm != null || dna.key != null) _found++;
  }

  Future<String?> _fileSignature(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return null;
      final st = await f.stat();
      return '${st.modified.millisecondsSinceEpoch}:${st.size}';
    } catch (_) {
      return null;
    }
  }
}
