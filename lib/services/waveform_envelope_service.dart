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

  /// Full-file decode above this size is too slow for Now Playing (audiobooks).
  static const int maxNativeExtractBytes = 24 * 1024 * 1024;

  static const Duration _extractTimeout = Duration(seconds: 4);

  final Map<String, List<double>> _memory = {};
  final Map<String, Future<List<double>>> _inFlight = {};
  aw.PlayerController? _extractor;

  bool get _supportsNativeExtract =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

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

      // Desktop / web: skip native extractor — procedural envelope is instant.
      if (!_supportsNativeExtract) {
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
    if (path.isEmpty || path.startsWith('content://')) return const [];

    final file = File(path);
    if (!await file.exists()) {
      debugPrint('[WaveformEnvelope] file missing, using fallback: $path');
      return const [];
    }

    try {
      final size = await file.length();
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

    // audio_waveforms expects a filesystem path; keep a long-lived controller so
    // PlatformStreams are not torn down after every track.
    final raw = await _extractorController
        .extractWaveformData(
          path: path,
          noOfSamples: samples,
        )
        .timeout(
          _extractTimeout,
          onTimeout: () {
            debugPrint('[WaveformEnvelope] extract timed out: $path');
            return <double>[];
          },
        );
    return _normalize(raw);
  }

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

  List<double> _generateProceduralEnvelope(String path, int samples) {
    final rnd = Random(path.hashCode);
    final data = <double>[];

    for (int i = 0; i < samples; i++) {
      final t = i / max(1, samples - 1);
      double envelope = 1.0;
      if (t < 0.08) {
        envelope = t / 0.08;
      } else if (t > 0.92) {
        envelope = (1.0 - t) / 0.08;
      }

      var val = 0.28;
      val += 0.18 * sin(t * 15 + rnd.nextDouble());
      val += 0.10 * sin(t * 40 + rnd.nextDouble());
      val += 0.05 * sin(t * 80 + rnd.nextDouble());
      if (i % 5 == 0) val += 0.12 * rnd.nextDouble();
      if ((t > 0.3 && t < 0.45) || (t > 0.7 && t < 0.85)) {
        val *= 1.35;
      }

      data.add((val * envelope).clamp(0.05, 1.0));
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