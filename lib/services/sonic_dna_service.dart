import 'dart:async';
import 'dart:math';
import 'package:on_audio_query/on_audio_query.dart';
import 'database_service.dart';

class SonicDnaService {
  static final SonicDnaService _instance = SonicDnaService._();
  static SonicDnaService get instance => _instance;

  SonicDnaService._();

  final _progressController = StreamController<double>.broadcast();
  Stream<double> get progressStream => _progressController.stream;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

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

    for (final song in songs) {
      // Check if already analyzed
      final meta = await DatabaseService.instance.getSongMetadata(song.id.toString());
      if (meta?.bpm != null) {
        processed++;
        _progressController.add(processed / total);
        continue;
      }

      // Simulate Analysis
      await Future.delayed(const Duration(milliseconds: 20));

      // Deterministic DNA
      final seed = (song.duration ?? 0) + (song.size);
      final rnd = Random(seed);
      final bpm = (70.0 + rnd.nextDouble() * 110.0).roundToDouble();
      final keys = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'];
      final modes = ['Maj', 'Min'];
      final key = '${keys[rnd.nextInt(keys.length)]} ${modes[rnd.nextInt(modes.length)]}';

      await DatabaseService.instance.updateSonicDna(song.id.toString(), bpm, key);

      processed++;
      _progressController.add(processed / total);
    }

    _isScanning = false;
    _progressController.add(1.0);
  }
}
