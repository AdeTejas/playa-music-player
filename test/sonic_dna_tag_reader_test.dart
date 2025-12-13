import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:playa_clean/utils/sonic_dna_tag_reader.dart';

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

void main() {
  test('SonicDnaTagReader reads TBPM/TKEY from ID3v2.3', () async {
    final tbpm = _frameV23('TBPM', '128');
    final tkey = _frameV23('TKEY', 'F#m');
    final frames = Uint8List.fromList([...tbpm, ...tkey]);

    final tagHeader =
        BytesBuilder()
          ..add('ID3'.codeUnits)
          ..add([3, 0]) // v2.3.0
          ..add([0]) // flags
          ..add(_synchsafe(frames.length));

    final fileBytes = Uint8List.fromList([...tagHeader.toBytes(), ...frames]);

    final dir = await Directory.systemTemp.createTemp('playa_sonic_dna_');
    final file = File('${dir.path}/test.mp3');
    await file.writeAsBytes(fileBytes, flush: true);

    try {
      final dna = await SonicDnaTagReader.readFromFilePath(file.path);
      expect(dna.bpm, 128);
      expect(dna.key, 'F#m');
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
