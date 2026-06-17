import 'dart:io';

import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart' as oaq;

import '../design/design_system.dart';

void showToast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        msg,
        style: const TextStyle(color: PlayaColors.onSurface),
      ),
      backgroundColor: PlayaColors.glassStrong,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PlayaRadii.sm),
        side: const BorderSide(color: PlayaColors.borderSubtle),
      ),
      duration: const Duration(seconds: 2),
    ),
  );
}

String formatDuration(Duration? duration) {
  if (duration == null) return '--:--';
  final h = duration.inHours;
  final m = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) {
    return '$h:$m:$s';
  }
  return '$m:$s';
}

/// Stable song identifier used for metadata, favorites, Neural Mix, etc.
/// Prefers the absolute file path (`data`). Case-insensitive on Windows.
String songIdentity(oaq.SongModel s) {
  final p = s.data.trim();
  return Platform.isWindows ? p.toLowerCase() : p;
}