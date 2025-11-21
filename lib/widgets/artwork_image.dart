import 'dart:io';
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';

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

    return QueryArtworkWidget(
      id: id,
      type: type,
      nullArtworkWidget: nullArtworkWidget,
      artworkBorder: artworkBorder,
      artworkFit: artworkFit ?? BoxFit.cover,
      artworkWidth: width ?? 50,
      artworkHeight: height ?? 50,
    );
  }
}
