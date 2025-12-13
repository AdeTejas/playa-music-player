import 'dart:async';
import 'dart:io';
import 'package:on_audio_query/on_audio_query.dart';
import 'database_service.dart';
import '../models/song_metadata.dart';
import '../utils/sonic_dna_tag_reader.dart';
import 'sonic_dna_android_analyzer.dart';

class SonicDnaService {
  static final SonicDnaService _instance = SonicDnaService._();
  static SonicDnaService get instance => _instance;

  SonicDnaService._();

  final _progressController = StreamController<double>.broadcast();
  Stream<double> get progressStream => _progressController.stream;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  Future<String?> _fileSignature(String pathOrUri) async {
    try {
      final f = File(pathOrUri);
      if (!await f.exists()) return null;
      final st = await f.stat();
      return '${st.size}:${st.modified.millisecondsSinceEpoch}';
    } catch (_) {
      return null;
    }
  }

  Future<void> analyzeLibrary(List<SongModel> songs) async {
    // Forward to the implementation
    await analyzeLibraryMainThread(songs);
  }

  // Revised implementation running on main thread but using Future.delayed to yield
  // This is safer for the demo to ensure DB writes work
  Future<void> analyzeLibraryMainThread(List<SongModel> songs) async {
    if (_isScanning) return;
    _isScanning = true;
    _progressController.add(0.0);

    int processed = 0;
    final total = songs.length;

    final existing = await DatabaseService.instance.getAllSongMetadata();
    final metaById = {for (final m in existing) m.id: m};

    for (final song in songs) {
      final pathOrUri = song.data;
      final sig = await _fileSignature(pathOrUri);

      // Check if already analyzed for this exact file version.
      final meta = metaById[song.id.toString()];
      final hasDna = (meta?.bpm != null || meta?.key != null);
      final sigMatches =
          (sig != null &&
              meta?.dnaSignature != null &&
              meta!.dnaSignature == sig);
      if (hasDna && (sig == null || sigMatches)) {
        processed++;
        _progressController.add(processed / total);
        continue;
      }

      // Yield a little to keep UI responsive during large scans.
      await Future.delayed(const Duration(milliseconds: 1));

      // 1) Fast path: tags
      final dna = await SonicDnaTagReader.readFromFilePath(pathOrUri);
      double? bpm = dna.bpm;
      String? key = dna.key;

      // 2) Android fallback: decode PCM + analyze when tags are missing
      if ((bpm == null && key == null) && Platform.isAndroid) {
        final r = await SonicDnaAndroidAnalyzer.analyze(pathOrUri);
        bpm = r.bpm;
        key = r.key;
      }

      if (bpm != null || key != null) {
        await DatabaseService.instance.updateSonicDna(
          song.id.toString(),
          bpm: bpm,
          key: key,
          dnaSignature: sig,
        );
        // Keep local cache warm to avoid re-querying later in the loop.
        metaById[song.id.toString()] = (meta ??
                SongMetadata(id: song.id.toString()))
            .copyWith(bpm: bpm, key: key, dnaSignature: sig);
      }

      processed++;
      _progressController.add(processed / total);
    }

    _isScanning = false;
    _progressController.add(1.0);
  }
}
