import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

import '../services/artwork_cache_service.dart';

class ArtworkImage extends StatelessWidget {
  final int id;
  final ArtworkType type;
  final Widget? nullArtworkWidget;
  final BorderRadius? artworkBorder;
  final BoxFit? artworkFit;
  final double? width;
  final double? height;

  const ArtworkImage({
    super.key,
    required this.id,
    this.type = ArtworkType.AUDIO,
    this.nullArtworkWidget,
    this.artworkBorder,
    this.artworkFit,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    // On Windows, QueryArtworkWidget is not fully supported and can cause crashes
    // if it tries to load the audio file as an image.
    if (Platform.isWindows || Platform.isLinux) {
      return SizedBox(
        width: width,
        height: height,
        child: ClipRRect(
          borderRadius: artworkBorder ?? BorderRadius.zero,
          child: nullArtworkWidget ?? const Icon(Icons.music_note),
        ),
      );
    }

    final w = width ?? 50;
    final h = height ?? 50;
    final requestSize = (w > h ? w : h).ceil().clamp(64, 1200);

    return FutureBuilder<Uint8List?>(
      future: ArtworkCacheService.instance.getArtworkBytes(
        id: id,
        type: type,
        size: requestSize,
      ),
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null || bytes.isEmpty) {
          return SizedBox(
            width: w,
            height: h,
            child: ClipRRect(
              borderRadius: artworkBorder ?? BorderRadius.zero,
              child: nullArtworkWidget ?? const Icon(Icons.music_note),
            ),
          );
        }

        return SizedBox(
          width: w,
          height: h,
          child: ClipRRect(
            borderRadius: artworkBorder ?? BorderRadius.zero,
            child: Image.memory(
              bytes,
              fit: artworkFit ?? BoxFit.cover,
              gaplessPlayback: true,
              cacheWidth: w.ceil(),
              cacheHeight: h.ceil(),
            ),
          ),
        );
      },
    );
  }
}
