import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audio_waveforms/audio_waveforms.dart' as aw;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Extracts and caches per-track RMS amplitude envelopes for the torch ship.
class WaveformEnvelopeService {
  WaveformEnvelopeService._();
  static final WaveformEnvelopeService instance = WaveformEnvelopeService._();

  static const int defaultSamples = 300;

  /// Full-file decode above this size stays on the fast procedural path (calm
  /// scrubber). 400MB covers typical audiobook chapters (2-6h); only the
  /// longest books fall through.
  static const int maxNativeExtractBytes = 400 * 1024 * 1024;

  /// Native RMS extraction currently ships on Android via a fast in-app method
  /// channel ([_extractFast], background-thread MediaCodec decode — ~14x
  /// realtime, one result, no per-bucket main-thread traffic) and on iOS via
  /// audio_waveforms (~14x realtime, per-bucket stream — fine for short tracks,
  /// too slow for audiobooks). Desktop (Windows/Linux) extraction is deferred:
  /// it needs a native decoder (audio_decoder requires Dart >=3.10.8; this
  /// project is on Dart 3.7). Uncompressed WAV/PCM files get real envelopes on
  /// all platforms via [_extractWavEnvelope] (pure Dart, no plugins).
  bool get _supportsNativeExtract =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Android only: the fast channel decodes on a background thread and returns
  /// once. It also accepts content:// (MediaStore) URIs natively.
  bool get _supportsFastExtract => !kIsWeb && Platform.isAndroid;

  static const MethodChannel _fastExtractChannel =
      MethodChannel('com.paxpiece.playa/fast_waveform');

  /// Outer safety cap for the fast Android extractor. Decode cost scales with
  /// audio DURATION (~14x realtime on this device), so the extractor
  /// self-limits from the file's container duration (`duration/8 + 45s`,
  /// ceiling 900s) — this Dart cap is only a parachute and must never
  /// truncate a legitimate extraction early.
  static const Duration fastExtractCap = Duration(seconds: 900);

  /// Decode time scales with file size (large files = long books). Floor of
  /// 8s, ceiling of 90s; a 125MB chapter gets ~15s, a 400MB book ~28s.
  static Duration extractTimeoutFor(int sizeBytes) {
    final seconds = 8 + (sizeBytes / (20 * 1024 * 1024)).ceil();
    return Duration(seconds: seconds.clamp(8, 90));
  }

  final Map<String, List<double>> _memory = {};
  final Map<String, Future<List<double>>> _inFlight = {};
  aw.PlayerController? _extractor;

  aw.PlayerController get _extractorController {
    _extractor ??= aw.PlayerController();
    return _extractor!;
  }

  Future<List<double>> loadEnvelope(
    String path, {
    int samples = defaultSamples,
  }) async {
    final normalizedPath = _normalizePath(path);
    if (normalizedPath.isEmpty) {
      return _generateProceduralEnvelope('unknown', samples);
    }

    try {
      final key = await _cacheKey(normalizedPath, samples);
      final cached = _memory[key];
      if (cached != null && cached.isNotEmpty) return cached;

      final disk = await _readDisk(key);
      if (disk != null && disk.isNotEmpty) {
        _memory[key] = disk;
        return disk;
      }

      // Desktop / web: try real WAV/PCM extraction (pure Dart), else the
      // procedural envelope — instant, works for all other formats on Dart 3.7.
      if (!_supportsNativeExtract) {
        final wav = await _extractWavEnvelope(normalizedPath, samples);
        if (wav.isNotEmpty) {
          _memory[key] = wav;
          unawaited(_writeDisk(key, wav));
          return wav;
        }
        final fallback = _generateProceduralEnvelope(normalizedPath, samples);
        _memory[key] = fallback;
        unawaited(_writeDisk(key, fallback));
        return fallback;
      }

      return _inFlight.putIfAbsent(
        key,
        () => _loadEnvelopeMobile(key, normalizedPath, samples),
      );
    } catch (e, st) {
      debugPrint('[WaveformEnvelope] loadEnvelope failed for $normalizedPath: $e\n$st');
      return _generateProceduralEnvelope(normalizedPath, samples);
    }
  }

  Future<List<double>> _loadEnvelopeMobile(
    String key,
    String normalizedPath,
    int samples,
  ) async {
    debugPrint('[WaveformEnvelope] extracting path=$normalizedPath');
    try {
      final extracted = await _extractFromFile(normalizedPath, samples);
      if (extracted.isNotEmpty) {
        debugPrint(
          '[WaveformEnvelope] native ok samples=${extracted.length} path=$normalizedPath',
        );
        _memory[key] = extracted;
        await _writeDisk(key, extracted);
        return extracted;
      }
      debugPrint('[WaveformEnvelope] native empty, using procedural: $normalizedPath');
    } on PlatformException catch (e, st) {
      debugPrint(
        '[WaveformEnvelope] platform extract failed code=${e.code} '
        'message=${e.message} path=$normalizedPath\n$st',
      );
    } on MissingPluginException catch (e, st) {
      debugPrint(
        '[WaveformEnvelope] native extractor unavailable: $e\n$st',
      );
    } catch (e, st) {
      debugPrint('[WaveformEnvelope] extract failed for $normalizedPath: $e\n$st');
    } finally {
      _inFlight.remove(key);
    }

    final fallback = _generateProceduralEnvelope(normalizedPath, samples);
    _memory[key] = fallback;
    return fallback;
  }

  List<double> proceduralFallback(String path, {int samples = defaultSamples}) {
    return _generateProceduralEnvelope(_normalizePath(path), samples);
  }

  Future<List<double>> _extractFromFile(String path, int samples) async {
    if (!_supportsNativeExtract) return const [];
    if (path.isEmpty) return const [];

    final isContentUri = path.startsWith('content://');

    int? size;
    if (!isContentUri) {
      final file = File(path);
      if (!await file.exists()) {
        debugPrint('[WaveformEnvelope] file missing, using fallback: $path');
        return const [];
      }
      try {
        size = await file.length();
        if (size > maxNativeExtractBytes) {
          debugPrint(
            '[WaveformEnvelope] skip native extract (${size ~/ (1024 * 1024)}MB): $path',
          );
          return const [];
        }
      } catch (e) {
        debugPrint('[WaveformEnvelope] stat failed for $path: $e');
        return const [];
      }
    }

    if (_supportsFastExtract) {
      return _extractFast(path, samples);
    }

    // iOS: audio_waveforms expects a filesystem path; content:// isn't
    // supported there and stays on the procedural path.
    if (isContentUri) return const [];

    // audio_waveforms expects a filesystem path; keep a long-lived controller so
    // PlatformStreams are not torn down after every track.
    final raw = await _extractorController
        .extractWaveformData(
          path: path,
          noOfSamples: samples,
        )
        .timeout(
          WaveformEnvelopeService.extractTimeoutFor(size ?? 0),
          onTimeout: () {
            debugPrint('[WaveformEnvelope] extract timed out: $path');
            return <double>[];
          },
        );
    return _normalize(raw);
  }

  /// Fast Android extraction via the in-app background-thread channel. Decodes
  /// the full file once off the main thread and returns a single list of RMS
  /// buckets (no per-bucket stream traffic), so real envelopes work for whole
  /// audiobooks in minutes instead of being impossible.
  Future<List<double>> _extractFast(String path, int samples) async {
    final sw = Stopwatch()..start();
    try {
      final raw = await _fastExtractChannel
          .invokeMethod<List<dynamic>>(
            'extractWaveform',
            {
              'path': path,
              'samples': samples,
              'maxMillis': fastExtractCap.inMilliseconds,
            },
          )
          .timeout(fastExtractCap, onTimeout: () => null);
      final elapsedMs = sw.elapsedMilliseconds;
      if (raw == null || raw.isEmpty) {
        debugPrint(
          '[WaveformEnvelope] fast extract empty after ${elapsedMs}ms '
          '(cap ${fastExtractCap.inSeconds}s): $path',
        );
        return const [];
      }
      final values = raw.map((e) => (e as num).toDouble()).toList(growable: false);
      debugPrint(
        '[WaveformEnvelope] fast ok samples=${values.length} in ${elapsedMs}ms: $path',
      );
      return _normalize(values);
    } on PlatformException catch (e, st) {
      debugPrint(
        '[WaveformEnvelope] fast extract failed code=${e.code} '
        'message=${e.message} in ${sw.elapsedMilliseconds}ms: $path\n$st',
      );
      return const [];
    } on MissingPluginException catch (e, st) {
      debugPrint('[WaveformEnvelope] fast extractor unavailable: $e\n$st');
      return const [];
    }
  }

  /// Pure-Dart RMS envelope for uncompressed WAV files (PCM integer or IEEE
  /// float). Works on every platform with no plugins, so real waveforms are
  /// available on desktop/web for WAV today; MP3/FLAC/etc. still need the
  /// native decoder path (Dart >=3.10.8) and fall back to procedural.
  /// Returns an empty list when the file is not a decodable WAV.
  Future<List<double>> _extractWavEnvelope(String path, int samples) async {
    if (kIsWeb) return const [];
    if (path.isEmpty || path.startsWith('content://')) return const [];

    final file = File(path);
    if (!await file.exists()) return const [];
    try {
      if (await file.length() > maxNativeExtractBytes) return const [];
    } catch (_) {
      return const [];
    }

    final raf = await file.open();
    try {
      final header = await raf.read(12);
      if (header.length < 12 ||
          String.fromCharCodes(header.sublist(0, 4)) != 'RIFF' ||
          String.fromCharCodes(header.sublist(8, 12)) != 'WAVE') {
        return const [];
      }

      var fmtOffset = -1;
      var dataOffset = -1;
      var dataLen = 0;
      var fmtSize = 0;
      while (true) {
        final chunk = await raf.read(8);
        if (chunk.length < 8) break;
        final id = String.fromCharCodes(chunk.sublist(0, 4));
        final size = _le32(chunk.sublist(4));
        if (id == 'fmt ') {
          fmtOffset = await raf.position();
          fmtSize = size;
          await raf.setPosition(await raf.position() + size + (size & 1));
        } else if (id == 'data') {
          dataOffset = await raf.position();
          dataLen = size;
          break;
        } else {
          await raf.setPosition(await raf.position() + size + (size & 1));
        }
      }
      if (fmtOffset < 0 || dataOffset < 0 || dataLen <= 0 || fmtSize < 16) {
        return const [];
      }

      await raf.setPosition(fmtOffset);
      final fmt = await raf.read(16);
      if (fmt.length < 16) return const [];
      final audioFormat = _le16(fmt.sublist(0));
      final channels = _le16(fmt.sublist(2));
      final bitsPerSample = _le16(fmt.sublist(14));
      final isFloat = audioFormat == 3;
      if (channels <= 0 || bitsPerSample <= 0 || (!isFloat && audioFormat != 1)) {
        return const [];
      }
      final bytesPerSample = (bitsPerSample / 8).ceil();
      final frameSize = bytesPerSample * channels;
      if (frameSize <= 0) return const [];

      final frames = dataLen ~/ frameSize;
      if (frames <= 0) return const [];
      final bucketCount = min(samples, frames);
      final bucketFrames = frames / bucketCount;
      final sumSq = List<double>.filled(bucketCount, 0);
      final counts = List<int>.filled(bucketCount, 0);

      await raf.setPosition(dataOffset);
      const chunkFrames = 4096;
      final buffer = Uint8List(chunkFrames * frameSize);
      final bd = ByteData.sublistView(buffer);
      var readFrames = 0;
      while (readFrames < frames) {
        final n = min(chunkFrames, frames - readFrames);
        final bytes = await raf.read(n * frameSize);
        if (bytes.length < n * frameSize) break;
        buffer.setRange(0, bytes.length, bytes);
        for (var f = 0; f < n; f++) {
          final off = f * frameSize;
          final v = _wavSampleValue(
            bd,
            off,
            isFloat: isFloat,
            bitsPerSample: bitsPerSample,
            bytesPerSample: bytesPerSample,
          );
          if (v.isNaN) continue;
          final bucket = (f + readFrames) ~/ bucketFrames;
          if (bucket < 0 || bucket >= bucketCount) continue;
          sumSq[bucket] += v * v;
          counts[bucket]++;
        }
        readFrames += n;
      }

      if (counts.every((c) => c == 0)) return const [];
      final raw = List<double>.generate(
        bucketCount,
        (i) => counts[i] == 0 ? 0.0 : sqrt(sumSq[i] / counts[i]),
        growable: false,
      );
      return _normalize(raw);
    } finally {
      await raf.close();
    }
  }

  double _wavSampleValue(
    ByteData bd,
    int off, {
    required bool isFloat,
    required int bitsPerSample,
    required int bytesPerSample,
  }) {
    if (isFloat) {
      if (bytesPerSample == 4) return bd.getFloat32(off, Endian.little);
      if (bytesPerSample == 8) return bd.getFloat64(off, Endian.little);
      return double.nan;
    }
    switch (bytesPerSample) {
      case 1:
        return (bd.getUint8(off) - 128) / 128.0;
      case 2:
        return bd.getInt16(off, Endian.little) / 32768.0;
      case 4:
        return bd.getInt32(off, Endian.little) / 2147483648.0;
      case 3:
        var v = 0;
        for (var i = 2; i >= 0; i--) {
          v = (v << 8) | bd.getUint8(off + i);
        }
        if ((v & 0x800000) != 0) v -= 0x1000000;
        return v / 8388608.0;
      default:
        return double.nan;
    }
  }

  int _le16(List<int> bytes) => bytes[0] | (bytes[1] << 8);

  int _le32(List<int> bytes) =>
      bytes[0] |
      (bytes[1] << 8) |
      (bytes[2] << 16) |
      (bytes[3] << 24);

  String _normalizePath(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;
    if (trimmed.startsWith('content://')) return trimmed;
    if (trimmed.startsWith('file://')) {
      return Uri.parse(trimmed).toFilePath();
    }
    return trimmed;
  }

  List<double> _normalize(List<double> raw) {
    if (raw.isEmpty) return raw;
    var maxVal = 0.0;
    for (final v in raw) {
      if (v > maxVal) maxVal = v;
    }
    if (maxVal <= 0) return List<double>.filled(raw.length, 0.2);
    return raw
        .map((v) => (v / maxVal).clamp(0.05, 1.0))
        .toList(growable: false);
  }

  /// Music-shaped procedural envelope: intro ramp, alternating verse/chorus
  /// energy sections, percussive kicks, breathing gaps and an outro fade.
  /// Deterministic per path so the same track always renders identically.
  List<double> _generateProceduralEnvelope(String path, int samples) {
    final rnd = Random(path.hashCode);

    final introEnd = 0.04 + 0.02 * rnd.nextDouble();
    final outroStart = 0.84 + 0.05 * rnd.nextDouble();
    final sectionCount = 3 + rnd.nextInt(3);
    final sectionEnergy = List<double>.generate(
      sectionCount,
      (_) => 0.72 + 0.55 * rnd.nextDouble(),
    );

    // "Tempo" — kick spacing in sample units (roughly 140–260 bpm feel).
    final kickEvery = max(
      3,
      (samples / (140 + rnd.nextInt(120))).round(),
    );
    final gapEvery = max(4, samples ~/ (8 + rnd.nextInt(5)));

    final data = <double>[];
    for (int i = 0; i < samples; i++) {
      final t = i / max(1, samples - 1);

      final bodyT = ((t - introEnd) / (outroStart - introEnd)).clamp(0.0, 1.0);
      final section = (bodyT * sectionCount).floor().clamp(0, sectionCount - 1);
      final energy = sectionEnergy[section];

      var envelope = 1.0;
      if (t < introEnd) {
        envelope = t / introEnd;
      } else if (t > outroStart) {
        envelope = max(0.0, (1.0 - t) / (1.0 - outroStart));
      }

      var val = 0.22;
      val += 0.16 * sin(t * 9.0 + rnd.nextDouble() * 6.2832);
      val += 0.10 * sin(t * 31.0 + rnd.nextDouble() * 6.2832);
      val += 0.06 * sin(t * 77.0 + rnd.nextDouble() * 6.2832);

      final kickPos = i % kickEvery;
      if (kickPos < 2) {
        val += 0.20 * (1.0 - kickPos / 2.0);
      }
      if (rnd.nextDouble() < 0.015) {
        val += 0.24;
      }
      if (i % gapEvery == 0) {
        val *= 0.35;
      }

      data.add((val * energy * envelope).clamp(0.05, 1.0));
    }
    return data;
  }

  Future<String> _cacheKey(String path, int samples) async {
    if (kIsWeb) return '${path.hashCode}_$samples';

    try {
      final file = File(path);
      if (await file.exists()) {
        final stat = await file.stat();
        return '${path.hashCode}_${stat.size}_${stat.modified.millisecondsSinceEpoch}_$samples';
      }
    } catch (_) {}
    return '${path.hashCode}_$samples';
  }

  Future<File> _cacheFile(String key) async {
    final dir = await getTemporaryDirectory();
    final folder = Directory('${dir.path}/waveform_cache');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    final safeName = key.hashCode.toUnsigned(32).toRadixString(16);
    return File('${folder.path}/$safeName.json');
  }

  Future<List<double>?> _readDisk(String key) async {
    if (kIsWeb) return null;
    try {
      final file = await _cacheFile(key);
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return null;
      return decoded
          .map((e) => (e as num).toDouble())
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeDisk(String key, List<double> data) async {
    if (kIsWeb) return;
    try {
      final file = await _cacheFile(key);
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('[WaveformEnvelope] cache write failed: $e');
    }
  }
}