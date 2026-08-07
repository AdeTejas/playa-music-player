import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:playa_clean/services/waveform_envelope_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('waveform_error_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('loadEnvelope handles non-existent file gracefully', () async {
    final path = '${tempDir.path}/non_existent.wav';
    
    // Should not throw, but return procedural fallback
    final envelope = await WaveformEnvelopeService.instance.loadEnvelope(
      path,
      samples: 100,
    );

    final fallback = WaveformEnvelopeService.instance.proceduralFallback(path, samples: 100);
    expect(envelope, fallback);
  });

  test('loadEnvelope handles empty file gracefully', () async {
    final path = '${tempDir.path}/empty.wav';
    File(path).writeAsBytesSync([]);

    final envelope = await WaveformEnvelopeService.instance.loadEnvelope(
      path,
      samples: 100,
    );

    final fallback = WaveformEnvelopeService.instance.proceduralFallback(path, samples: 100);
    expect(envelope, fallback);
  });

  test('loadEnvelope handles malformed WAV header gracefully', () async {
    final path = '${tempDir.path}/malformed.wav';
    // Just "RIFF" and some junk
    File(path).writeAsBytesSync(Uint8List.fromList([82, 73, 70, 70, 0, 0, 0, 0, 0, 0, 0, 0]));

    final envelope = await WaveformEnvelopeService.instance.loadEnvelope(
      path,
      samples: 100,
    );

    final fallback = WaveformEnvelopeService.instance.proceduralFallback(path, samples: 100);
    expect(envelope, fallback);
  });
}
