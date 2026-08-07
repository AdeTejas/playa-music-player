import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart' as oaq;

import 'package:playa_clean/models/song_metadata.dart';
import 'package:playa_clean/services/neural_mix_index_service.dart';
import 'package:playa_clean/services/sonic_dna_analysis_service.dart';
import 'package:playa_clean/utils/neural_mix_key.dart';

void main() {
  late NeuralMixIndexService svc;

  setUp(() {
    svc = NeuralMixIndexService.instance;
    svc.resetForTest();
  });

  tearDown(() {
    svc.resetForTest();
  });

  oaq.SongModel songFor(String path, {int id = 1, String? artist}) =>
      oaq.SongModel({
        '_id': id,
        '_data': path,
        'title': 'Track $id',
        if (artist != null) 'artist': artist,
      });

  test('parseNeuralMixKey parses majors, minors and sharps', () {
    expect(parseNeuralMixKey('C'), (pitch: 0, minor: false));
    expect(parseNeuralMixKey('F#m'), (pitch: 6, minor: true));
    expect(parseNeuralMixKey('A minor'), (pitch: 9, minor: true));
    expect(parseNeuralMixKey('Gb'), (pitch: 6, minor: false));
    expect(parseNeuralMixKey(' Bb min'), (pitch: 10, minor: true));
    expect(parseNeuralMixKey(null), isNull);
    expect(parseNeuralMixKey('  '), isNull);
    expect(parseNeuralMixKey('Z#'), isNull);
  });

  test('warm builds rows with bpm/key and pre-parsed key fields', () async {
    final songs = [
      songFor('c:/music/a.mp3', id: 1, artist: 'Artist A'),
      songFor('c:/music/b.flac', id: 2, artist: 'Artist B'),
    ];
    final metas = [
      const SongMetadata(id: 'c:/music/a.mp3', bpm: 128.0, key: 'F#m'),
      const SongMetadata(id: 'c:/music/b.flac', bpm: 95.0, key: 'Am'),
    ];

    svc.songsOverride = () => songs;
    svc.metadataOverride = () async => metas;

    await svc.warm();

    expect(svc.isWarm, isTrue);
    final rows = svc.songRows!;
    expect(rows.length, 2);

    final a = rows.firstWhere((r) => r['id'] == 'c:/music/a.mp3');
    expect(a['artist'], 'Artist A');
    expect(a['bpm'], 128.0);
    expect(a['key'], 'F#m');
    expect(a['keyPitch'], 6);
    expect(a['keyMinor'], isTrue);

    final b = rows.firstWhere((r) => r['id'] == 'c:/music/b.flac');
    expect(b['keyPitch'], 9);
    expect(b['keyMinor'], isTrue);
  });

  test('warm with no metadata leaves keys null but still warms', () async {
    svc.songsOverride = () => [songFor('c:/music/a.mp3', id: 1)];
    svc.metadataOverride = () async => const [];

    await svc.warm();

    expect(svc.isWarm, isTrue);
    final row = svc.songRows!.single;
    expect(row['bpm'], isNull);
    expect(row['key'], isNull);
    expect(row['keyPitch'], isNull);
  });

  test('warm with empty library is a no-op', () async {
    svc.songsOverride = () => [];
    await svc.warm();

    expect(svc.isWarm, isFalse);
    expect(svc.songRows, isNull);
  });

  test('invalidate drops the cached index', () async {
    svc.songsOverride = () => [songFor('c:/music/a.mp3', id: 1)];
    svc.metadataOverride = () async => const [];
    await svc.warm();
    expect(svc.isWarm, isTrue);

    svc.invalidate();
    expect(svc.isWarm, isFalse);
    expect(svc.songRows, isNull);
  });

  test('analysis done phase triggers a warm', () async {
    svc.songsOverride = () => [songFor('c:/music/a.mp3', id: 1)];
    svc.metadataOverride = () async => [
          const SongMetadata(id: 'c:/music/a.mp3', bpm: 120.0, key: 'C'),
        ];

    svc.start();
    final analysis = SonicDnaAnalysisService.instance;
    expect(analysis.phase, SonicDnaAnalysisPhase.idle);

    // Simulate the analysis completing by toggling through done.
    analysis.startAnalysis(songs: [songFor('c:/music/a.mp3', id: 1)]);

    // The listener fires on the done notification; give the event loop a beat.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(svc.isWarm, isTrue);
    expect(svc.songRows!.single['bpm'], 120.0);

    svc.resetForTest();
  });
}
