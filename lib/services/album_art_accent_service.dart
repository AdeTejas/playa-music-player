import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:on_audio_query/on_audio_query.dart' as oaq;

import '../utils/accent_hue.dart';
import 'artwork_cache_service.dart';
import 'settings_service.dart';

/// Extracts a distinct playback accent from album artwork.
class AlbumArtAccentService extends ChangeNotifier {
  AlbumArtAccentService._();
  static final AlbumArtAccentService instance = AlbumArtAccentService._();

  final Map<String, Color> _cache = {};
  final Map<String, Future<void>> _inFlight = {};

  Color? cachedColorFor(String itemId) => _cache[itemId];

  Iterable<Color> get _hueAvoid {
    final base = Color(SettingsService.instance.accentColor);
    return [
      base,
      ...SettingsService.colorPresets.values.map((v) => Color(v)),
      ..._cache.values,
    ];
  }

  Future<void> prefetch(MediaItem item) async {
    final id = item.id;
    if (_cache.containsKey(id)) return;
    if (_inFlight.containsKey(id)) return _inFlight[id];

    final task = _load(item);
    _inFlight[id] = task;
    try {
      await task;
    } finally {
      _inFlight.remove(id);
    }
  }

  Future<void> _load(MediaItem item) async {
    final bytes = await _loadArtBytes(item);
    Color? extracted;
    if (bytes != null && bytes.isNotEmpty) {
      extracted = await _dominantColor(bytes);
    }

    final base = Color(SettingsService.instance.accentColor);
    final raw = extracted ??
        AccentHue.fallbackForItem(item.id, base);
    final distinct = AccentHue.ensureDistinct(
      raw,
      avoid: _hueAvoid,
    );

    _cache[item.id] = distinct;
    notifyListeners();
    SettingsService.instance.notifyAccentCacheChanged();
  }

  Future<Uint8List?> _loadArtBytes(MediaItem item) async {
    final mediaId = item.extras?['mediaId'];
    if (mediaId is num) {
      return ArtworkCacheService.instance.getArtworkBytes(
        id: mediaId.toInt(),
        type: oaq.ArtworkType.AUDIO,
        size: 128,
      );
    }

    final uri = item.artUri;
    if (uri != null && uri.scheme == 'file') {
      try {
        final file = File(uri.toFilePath());
        if (await file.exists()) return file.readAsBytes();
      } catch (_) {}
    }
    return null;
  }

  Future<Color?> _dominantColor(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 48,
        targetHeight: 48,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      if (data == null) return null;

      double r = 0, g = 0, b = 0, weight = 0;
      for (int i = 0; i < data.lengthInBytes; i += 4) {
        final red = data.getUint8(i);
        final green = data.getUint8(i + 1);
        final blue = data.getUint8(i + 2);
        final alpha = data.getUint8(i + 3);
        if (alpha < 40) continue;

        final lum = (0.299 * red + 0.587 * green + 0.114 * blue) / 255;
        if (lum < 0.08 || lum > 0.94) continue;

        final sat = _saturation(red, green, blue);
        if (sat < 0.12) continue;

        final w = sat * alpha;
        r += red * w;
        g += green * w;
        b += blue * w;
        weight += w;
      }

      if (weight <= 0) return null;
      return Color.fromARGB(
        255,
        (r / weight).round().clamp(0, 255),
        (g / weight).round().clamp(0, 255),
        (b / weight).round().clamp(0, 255),
      );
    } catch (e) {
      debugPrint('[AlbumArtAccent] extract failed: $e');
      return null;
    }
  }

  double _saturation(int r, int g, int b) {
    final rn = r / 255, gn = g / 255, bn = b / 255;
    final max = [rn, gn, bn].reduce((a, c) => a > c ? a : c);
    final min = [rn, gn, bn].reduce((a, c) => a < c ? a : c);
    if (max <= 0) return 0;
    return (max - min) / max;
  }
}