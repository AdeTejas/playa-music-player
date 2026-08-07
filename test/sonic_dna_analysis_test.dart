import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query/on_audio_query.dart' as oaq;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:playa_clean/services/database_service.dart';
import 'package:playa_clean/services/sonic_dna_analysis_service.dart';
import 'package:playa_clean/utils/ui_utils.dart';

Uint8List _synchsafe(int value) {
  final b0 = (value >> 21) & 0x7F;
  final b1 = (value >> 14) & 0x7F;
  final b2 = (value >> 7) & 0x7F;
  final b3 = value & 0x7F;
  return Uint8List.fromList([b0, b1, b2, b3]);
}

Uint8List _u32be(int value) {
  return Uint8List.fromList([
    (value >> 24) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  ]);
}

Uint8List _frameV23(String id, String text) {
  final payload = Uint8List.fromList([3, ...text.codeUnits]); // UTF-8
  final header =
      BytesBuilder()
        ..add(id.codeUnits)
        ..add(_u32be(payload.length))
        ..add([0, 0]);
  return Uint8List.fromList([...header.toBytes(), ...payload]);
}

Future<File> _writeTaggedFile(String path, String bpm, String key) async {
  final tbpm = _frameV23('TBPM', bpm);
  final tkey = _frameV23('TKEY', key);
  final frames = Uint8List.fromList([...tbpm, ...tkey]);

  final tagHeader =
      BytesBuilder()
        ..add('ID3'.codeUnits)
        ..add([3, 0])
        ..add([0])
        ..add(_synchsafe(frames.length));

  final bytes = Uint8List.fromList([...tagHeader.toBytes(), ...frames]);
  final file = File(path);
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late File tagFile;
  late File secondFile;

  setUp(() async {
    final db = await databaseFactory.openDatabase(
      'file:sonic_dna_test_${DateTime.now().microsecondsSinceEpoch}?mode=memory&cache=shared',
      options: OpenDatabaseOptions(
        version: 7,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE song_metadata (
              song_id TEXT PRIMARY KEY,
              rating INTEGER,
              lyrics TEXT,
              play_count INTEGER,
              last_played INTEGER,
              bpm REAL,
              key TEXT,
              dna_sig TEXT
            )
          ''');
        },
      ),
    );
    DatabaseService.instance.resetForTest();
    DatabaseService.instance.initForTest(db);

    tempDir = await Directory.systemTemp.createTemp('playa_sonic_dna_svc_');
    tagFile = await _writeTaggedFile('${tempDir.path}/with_tags.mp3', '128', 'F#m');
    secondFile = await _writeTaggedFile('${tempDir.path}/with_tags_2.mp3', '95', 'Am');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  oaq.SongModel songFor(String path, {int id = 1}) => oaq.SongModel({
        '_id': id,
        '_data': path,
        'title': 'Track $id',
      });

  test('analyzes tag-based tracks and persists BPM/key + signature', () async {
    final svc = SonicDnaAnalysisService.instance;
    await svc.startAnalysis(songs: [songFor(tagFile.path)]);

    expect(svc.phase, SonicDnaAnalysisPhase.done);
    expect(svc.total, 1);
    expect(svc.done, 1);
    expect(svc.skipped, 0);
    expect(svc.found, 1);
    expect(svc.lastError, isNull);

    final id = songIdentity(songFor(tagFile.path));
    final meta = await DatabaseService.instance.getSongMetadata(id);
    expect(meta?.bpm, 128.0);
    expect(meta?.key, 'F#m');
    expect(meta?.dnaSignature, isNotNull);
  });

  test('resume run skips tracks with a matching file signature', () async {
    final svc = SonicDnaAnalysisService.instance;
    await svc.startAnalysis(songs: [songFor(tagFile.path)]);
    expect(svc.found, 1);

    await svc.startAnalysis(songs: [songFor(tagFile.path)]);
    expect(svc.phase, SonicDnaAnalysisPhase.done);
    expect(svc.skipped, 1);
    expect(svc.found, 0);
  });

  test('missing files are skipped without error', () async {
    final svc = SonicDnaAnalysisService.instance;
    await svc.startAnalysis(songs: [songFor('${tempDir.path}/missing.mp3')]);

    expect(svc.phase, SonicDnaAnalysisPhase.done);
    expect(svc.skipped, 1);
    expect(svc.found, 0);
    expect(svc.lastError, isNull);
  });

  test('empty library is a no-op', () async {
    final svc = SonicDnaAnalysisService.instance;
    await svc.startAnalysis(songs: const []);

    expect(svc.phase, SonicDnaAnalysisPhase.idle);
  });

  test('cancel stops a running analysis', () async {
    final svc = SonicDnaAnalysisService.instance;
    final fut = svc.startAnalysis(songs: [
      songFor(tagFile.path, id: 1),
      songFor(secondFile.path, id: 2),
    ]);
    svc.cancel();
    await fut;

    expect(svc.phase, SonicDnaAnalysisPhase.idle);
    expect(svc.isRunning, isFalse);
  });
}
