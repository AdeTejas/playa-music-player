import 'package:on_audio_query/on_audio_query.dart' as oaq;

import '../models/listening_progress.dart';
import '../repositories/listening_progress_repository.dart';
import '../services/player_controller.dart';
import '../utils/bookmark_key.dart';
import '../utils/content_mode.dart';

/// Result of resume soak validation (synthetic + optional live library checks).
class ResumeSoakReport {
  final List<String> lines;
  final int passed;
  final int failed;

  const ResumeSoakReport({
    required this.lines,
    required this.passed,
    required this.failed,
  });

  bool get ok => failed == 0;

  String get summary => lines.join('\n');
}

class ResumeSoakCheck {
  const ResumeSoakCheck._();

  static ResumeSoakReport runSyntheticChecks() {
    final lines = <String>[];
    var passed = 0;
    var failed = 0;

    void check(String name, bool condition, {String? detail}) {
      if (condition) {
        passed++;
        lines.add('PASS  $name');
      } else {
        failed++;
        lines.add('FAIL  $name${detail == null ? '' : ' — $detail'}');
      }
    }

    final ch1 = _fixtureSong(
      id: 1,
      title: 'Chapter 1',
      path: r'C:\Audiobooks\Saga\01.mp3',
      album: 'Saga',
      artist: 'Author',
      track: 1,
    );
    final ch2 = _fixtureSong(
      id: 2,
      title: 'Chapter 2',
      path: r'C:\Audiobooks\Saga\02.mp3',
      album: 'Saga',
      artist: 'Author',
      track: 2,
    );
    final seriesKey = ContentModeDetector.seriesKeyForSong(ch1);
    check(
      'series key matches across chapters',
      ContentModeDetector.seriesKeyForSong(ch2) == seriesKey,
      detail: seriesKey,
    );

    final progress = ListeningProgress(
      seriesKey: seriesKey,
      title: 'Saga',
      artist: 'Author',
      lastSongPath: r'c:\audiobooks\saga\02.mp3',
      lastMediaId: 2,
      positionMs: 120000,
      updatedAt: DateTime.now(),
      contentMode: ContentMode.audiobook,
    );
    check(
      'resolveSeriesIndex (path casing)',
      ListeningProgressRepository.resolveSeriesIndex([ch1, ch2], progress) == 1,
    );

    final moved = ListeningProgress(
      seriesKey: 'host::podcast',
      title: 'Podcast',
      artist: 'Host',
      lastSongPath: '/old/path/ep04.mp3',
      lastMediaId: 11,
      positionMs: 5000,
      updatedAt: DateTime.now(),
      contentMode: ContentMode.audiobook,
    );
    final movedSongs = [
      _fixtureSong(id: 10, title: 'Ep 3', path: '/new/path/ep03.mp3'),
      _fixtureSong(id: 11, title: 'Ep 4', path: '/new/path/ep04.mp3'),
    ];
    check(
      'resolveSeriesIndex (media id fallback)',
      ListeningProgressRepository.resolveSeriesIndex(movedSongs, moved) == 1,
    );

    final single = ListeningProgressRepository.resolveSingleTrack(
      [ch1, ch2],
      progress,
    );
    check(
      'resolveSingleTrack finds chapter',
      single?.id == 2,
    );

    final duration = ListeningProgressRepository.durationMsForProgress(
      progress,
      [ch1, ch2],
    );
    check(
      'durationMsForProgress resolves chapter duration',
      duration == ch2.duration,
    );

    return ResumeSoakReport(lines: lines, passed: passed, failed: failed);
  }

  /// Validates recent listening entries against the on-device library.
  static ResumeSoakReport runLiveChecks({
    required List<oaq.SongModel> library,
    required List<ListeningProgress> recent,
  }) {
    final lines = <String>[];
    var passed = 0;
    var failed = 0;

    void check(String name, bool condition, {String? detail}) {
      if (condition) {
        passed++;
        lines.add('PASS  $name');
      } else {
        failed++;
        lines.add('FAIL  $name${detail == null ? '' : ' — $detail'}');
      }
    }

    if (recent.isEmpty) {
      lines.add('INFO  no recent listening rows to validate');
      return ResumeSoakReport(lines: lines, passed: passed, failed: failed);
    }

    for (final item in recent.take(6)) {
      final label = item.title.length > 32
          ? '${item.title.substring(0, 32)}…'
          : item.title;
      final series = _songsInSeries(item.seriesKey, library);

      if (series.length > 1) {
        final index = ListeningProgressRepository.resolveSeriesIndex(
          series,
          item,
        );
        check(
          'multi-chapter "$label" index in range',
          index >= 0 && index < series.length,
          detail: 'index=$index count=${series.length}',
        );
        final target = series[index];
        check(
          'multi-chapter "$label" target resolvable',
          BookmarkKey.canonical(target.data).isNotEmpty,
          detail: target.data,
        );
      } else {
        final track = ListeningProgressRepository.resolveSingleTrack(
          library,
          item,
        );
        check(
          'single-track "$label" resolvable',
          track != null,
          detail: item.lastSongPath,
        );
      }
    }

    return ResumeSoakReport(lines: lines, passed: passed, failed: failed);
  }

  static Future<ResumeSoakReport> runAll({
    required PlayerController ctrl,
    required List<oaq.SongModel> library,
  }) async {
    final synthetic = runSyntheticChecks();
    final recent = await ctrl.getRecentListening();
    final live = runLiveChecks(library: library, recent: recent);

    return ResumeSoakReport(
      passed: synthetic.passed + live.passed,
      failed: synthetic.failed + live.failed,
      lines: [
        '--- Synthetic ---',
        ...synthetic.lines,
        '--- Live library ---',
        ...live.lines,
        '',
        'Result: ${synthetic.failed + live.failed == 0 ? 'OK' : 'ISSUES'} '
            '(${synthetic.passed + live.passed} passed, '
            '${synthetic.failed + live.failed} failed)',
      ],
    );
  }

  static List<oaq.SongModel> _songsInSeries(
    String seriesKey,
    List<oaq.SongModel> library,
  ) {
    if (seriesKey.isEmpty) return const [];
    final matches = library
        .where(
          (s) => ContentModeDetector.seriesKeyForSong(s) == seriesKey,
        )
        .toList();
    matches.sort((a, b) {
      final ta = a.track ?? 0;
      final tb = b.track ?? 0;
      if (ta != tb) return ta.compareTo(tb);
      return a.title.compareTo(b.title);
    });
    return matches;
  }

  static oaq.SongModel _fixtureSong({
    required int id,
    required String title,
    required String path,
    String? album,
    String? artist,
    int? track,
    int durationMs = 180000,
  }) {
    return oaq.SongModel({
      '_id': id,
      '_data': path,
      'title': title,
      'album': album ?? 'Album',
      'artist': artist ?? 'Artist',
      'duration': durationMs,
      'track': track ?? 0,
    });
  }
}