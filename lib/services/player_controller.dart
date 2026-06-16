import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:on_audio_query/on_audio_query.dart' as oaq;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/listening_progress.dart';
import '../repositories/bookmark_repository.dart';
import '../repositories/listening_progress_repository.dart';
import '../repositories/song_repository.dart';
import '../utils/bookmark_key.dart';
import '../utils/content_mode.dart';
import '../utils/replaygain_tag_reader.dart';
import 'database_service.dart';
import '../utils/ui_utils.dart';
import 'analytics_service.dart';
import 'artwork_cache_service.dart';
import 'equalizer_service.dart';
import 'settings_service.dart';

// Runs in a background isolate via `compute`.
// Reads ReplayGain tags for Smart Volume (normalization + limiter).
Future<Map<String, double?>> _readReplayGainForPath(String path) async {
  final info = await ReplayGainTagReader.readFromFilePath(path);
  return <String, double?>{
    'trackGainDb': info.trackGainDb,
    'trackPeak': info.trackPeak,
    'albumGainDb': info.albumGainDb,
    'albumPeak': info.albumPeak,
  };
}

// Runs in a background isolate via `compute`.
// Input/output must be isolate-sendable (primitives + Lists/Maps of primitives).
List<String> _neuralMixRankSongIds(Map<String, dynamic> args) {
  final seedId = (args['seedId'] as String?) ?? '';
  final seedBpm = (args['seedBpm'] as num?)?.toDouble();
  final seedKey = args['seedKey'] as String?;
  final seedArtist = (args['seedArtist'] as String?)?.trim().toLowerCase();
  final count = (args['count'] as int?) ?? 50;
  final randomSeed = (args['randomSeed'] as int?) ?? 0;
  final energyMode = (args['energyMode'] as String?) ?? 'neutral';

  final exclude = <String>{
    for (final v in (args['excludeSongIds'] as List<dynamic>? ?? const []))
      v.toString(),
  };

  final songs = (args['songs'] as List<dynamic>? ?? const [])
      .cast<Map<dynamic, dynamic>>()
      .map(
        (m) => <String, dynamic>{
          'id': m['id']?.toString() ?? '',
          'artist': (m['artist']?.toString() ?? ''),
          'bpm': (m['bpm'] as num?)?.toDouble(),
          'key': m['key']?.toString(),
        },
      )
      .where((m) => (m['id'] as String).isNotEmpty)
      .toList(growable: false);

  ({int pitch, bool minor})? parseKey(String? key) {
    if (key == null) return null;
    final raw = key.trim();
    if (raw.isEmpty) return null;
    final compact = raw.replaceAll(RegExp(r'\s+'), '');
    final lower = compact.toLowerCase();
    final isMinor =
        compact.endsWith('m') ||
        lower.endsWith('min') ||
        lower.endsWith('minor');
    var note = compact;
    if (lower.endsWith('minor')) note = note.substring(0, note.length - 5);
    if (lower.endsWith('min')) note = note.substring(0, note.length - 3);
    if (note.endsWith('m')) note = note.substring(0, note.length - 1);
    if (note.isEmpty) return null;

    final normalized = note[0].toUpperCase() + note.substring(1);
    const map = <String, int>{
      'C': 0,
      'C#': 1,
      'Db': 1,
      'D': 2,
      'D#': 3,
      'Eb': 3,
      'E': 4,
      'F': 5,
      'F#': 6,
      'Gb': 6,
      'G': 7,
      'G#': 8,
      'Ab': 8,
      'A': 9,
      'A#': 10,
      'Bb': 10,
      'B': 11,
    };

    final pitch = map[normalized];
    if (pitch == null) return null;
    return (pitch: pitch, minor: isMinor);
  }

  double tempoScore(double seed, double other) {
    final distances = <double>[
      (seed - other).abs(),
      (seed - (other * 2)).abs(),
      (seed - (other / 2)).abs(),
    ];
    final d = distances.reduce(min);
    const sigma = 8.0;
    return 110.0 * exp(-(d * d) / (2 * sigma * sigma));
  }

  double keyScore(({int pitch, bool minor})? a, ({int pitch, bool minor})? b) {
    if (a == null || b == null) return 0;
    final aPitch = a.pitch;
    final bPitch = b.pitch;
    final aMinor = a.minor;
    final bMinor = b.minor;

    if (aPitch == bPitch && aMinor == bMinor) return 65;
    if (aPitch == bPitch && aMinor != bMinor) return 35;

    if (!aMinor && bMinor && bPitch == (aPitch + 9) % 12) return 45;
    if (aMinor && !bMinor && bPitch == (aPitch + 3) % 12) return 45;

    final semis = (aPitch - bPitch).abs() % 12;
    if (semis == 7 || semis == 5) return 28;

    final aF = (aPitch * 7) % 12;
    final bF = (bPitch * 7) % 12;
    final d = (aF - bF).abs();
    final circle = min(d, 12 - d);
    if (circle == 1) return 16;
    if (circle == 2) return 8;
    return 0;
  }

  final seedParsedKey = parseKey(seedKey);
  final rng = Random(randomSeed);

  final scored = <({String id, String artist, double score})>[];
  for (final s in songs) {
    final id = s['id'] as String;
    if (id == seedId) continue;
    if (exclude.contains(id)) continue;

    final bpm = s['bpm'] as double?;
    final key = s['key'] as String?;
    final artist = (s['artist'] as String).trim().toLowerCase();

    double score = 0;
    if (seedBpm != null && bpm != null && bpm > 0) {
      score += tempoScore(seedBpm, bpm);

      // Energy direction: treat BPM as a proxy.
      // Prefer higher BPM for 'up', lower BPM for 'down'.
      if (energyMode == 'up') {
        score += (bpm - seedBpm) >= 0 ? 14 : -10;
      } else if (energyMode == 'down') {
        score += (bpm - seedBpm) <= 0 ? 14 : -10;
      }
    }
    score += keyScore(seedParsedKey, parseKey(key));

    if (seedArtist != null && seedArtist.isNotEmpty && artist.isNotEmpty) {
      if (artist == seedArtist) score -= 10;
    }
    score += rng.nextDouble() * 8;
    scored.add((id: id, artist: artist, score: score));
  }

  scored.sort((a, b) => b.score.compareTo(a.score));

  final perArtist = <String, int>{};
  final picked = <String>[];
  for (final entry in scored) {
    if (picked.length >= count) break;
    final artist = entry.artist;
    if (artist.isNotEmpty) {
      final n = perArtist[artist] ?? 0;
      if (n >= 3) continue;
      perArtist[artist] = n + 1;
    }
    picked.add(entry.id);
  }
  if (picked.isNotEmpty) return picked;

  final candidates = <String>[];
  for (final s in songs) {
    final id = s['id'] as String;
    if (id == seedId) continue;
    if (exclude.contains(id)) continue;
    candidates.add(id);
  }
  candidates.shuffle(rng);
  if (candidates.length > count) {
    return candidates.take(count).toList(growable: false);
  }
  return candidates;
}

enum NeuralMixEnergyMode { neutral, up, down }

class PlayerController {
  PlayerController._();
  static PlayerController? _i;

  /// Returns the singleton, initializing it if necessary.
  /// Call [ensureInitialized] in main() to guarantee _init() completes
  /// before any playback or bookmark operations.
  static PlayerController ensure() => _i ??= PlayerController._().._init();

  /// Creates (or returns) the singleton and waits for full initialisation
  /// (audio session, stream listeners, etc.) so that bookmark operations
  /// and playback commands are safe.
  static Future<PlayerController> ensureInitialized() async {
    final ctrl = ensure();
    if (!ctrl._initCompleter.isCompleted) {
      await ctrl._initCompleter.future;
    }
    return ctrl;
  }

  /// Whether [ensure] / [_init] has completed.
  bool get isControllerInit => _initCompleter.isCompleted;
  final _initCompleter = Completer<void>();

  int _lastSessionId = 0;

  Object? _lastPlaybackError;
  DateTime? _lastPlaybackErrorAt;

  Object? get lastPlaybackError => _lastPlaybackError;
  DateTime? get lastPlaybackErrorAt => _lastPlaybackErrorAt;

  Timer? _sleepTimer;
  Timer? _sleepPoll;
  bool _sleepFading = false;
  bool _previewFading = false;

  String? _sleepAlbumName;
  String? _sleepQueueContextType;
  String? _sleepQueueContextId;

  // Volume pipeline (user volume * duck * smartGain * fade).
  double _userVolume = 1.0;
  double _duckFactor = 1.0;
  double _smartGain = 1.0;
  double _fadeFactor = 1.0;
  bool _volumeInitialized = false;

  String? _queueContextType;
  String? _queueContextId;

  void setSleepTimer(int minutes, {Duration fadeOut = Duration.zero}) {
    _cancelSleepTimerInternal();
    if (minutes <= 0) return;

    final dur = Duration(minutes: minutes);
    _sleepTimer = Timer(dur, () {
      Future<void>(() async {
        await _fadeAndPause(fadeOut);
        _cancelSleepTimerInternal();
      });
    });
  }

  void setSleepTimerEndOfTrack({Duration fadeOut = Duration.zero}) {
    _cancelSleepTimerInternal();
    _sleepAlbumName = null;
    _sleepQueueContextType = null;
    _sleepQueueContextId = null;
    _sleepPoll = Timer.periodic(const Duration(seconds: 1), (_) {
      Future<void>(() async {
        if (_sleepFading) return;
        final d = player.duration;
        if (d == null) return;
        final remaining = d - player.position;
        if (remaining <= Duration.zero) {
          await _fadeAndPause(fadeOut);
          _cancelSleepTimerInternal();
          return;
        }
        if (fadeOut > Duration.zero && remaining <= fadeOut) {
          await _fadeAndPause(fadeOut);
          _cancelSleepTimerInternal();
        }
      });
    });
  }

  void setSleepTimerEndOfQueue({Duration fadeOut = Duration.zero}) {
    _cancelSleepTimerInternal();
    _sleepAlbumName = null;
    _sleepQueueContextType = null;
    _sleepQueueContextId = null;
    _sleepPoll = Timer.periodic(const Duration(seconds: 1), (_) {
      Future<void>(() async {
        if (_sleepFading) return;
        if (player.hasNext) return;
        final d = player.duration;
        if (d == null) return;
        final remaining = d - player.position;
        if (remaining <= Duration.zero) {
          await _fadeAndPause(fadeOut);
          _cancelSleepTimerInternal();
          return;
        }
        if (fadeOut > Duration.zero && remaining <= fadeOut) {
          await _fadeAndPause(fadeOut);
          _cancelSleepTimerInternal();
        }
      });
    });
  }

  void setSleepTimerEndOfAlbum({Duration fadeOut = Duration.zero}) {
    _cancelSleepTimerInternal();
    final current = currentMediaItem;
    _sleepAlbumName = current?.album;
    _sleepQueueContextType = null;
    _sleepQueueContextId = null;
    if (_sleepAlbumName == null || _sleepAlbumName!.trim().isEmpty) return;

    _sleepPoll = Timer.periodic(const Duration(seconds: 1), (_) {
      Future<void>(() async {
        if (_sleepFading) return;
        final album = _sleepAlbumName;
        if (album == null) return;

        final tag = currentMediaItem;
        if (tag == null) return;

        final idx = player.currentIndex;
        if (idx == null) return;

        if ((tag.album ?? '') != album) return;
        if (_hasLaterAlbumItem(album, idx)) return;

        final d = player.duration;
        if (d == null) return;
        final remaining = d - player.position;
        if (remaining <= Duration.zero) {
          await _fadeAndPause(fadeOut);
          _cancelSleepTimerInternal();
          return;
        }
        if (fadeOut > Duration.zero && remaining <= fadeOut) {
          await _fadeAndPause(fadeOut);
          _cancelSleepTimerInternal();
        }
      });
    });
  }

  void setSleepTimerEndOfPlaylist({Duration fadeOut = Duration.zero}) {
    _cancelSleepTimerInternal();
    _sleepAlbumName = null;
    _sleepQueueContextType = _queueContextType;
    _sleepQueueContextId = _queueContextId;

    if (_sleepQueueContextType == null || _sleepQueueContextId == null) {
      setSleepTimerEndOfQueue(fadeOut: fadeOut);
      return;
    }

    _sleepPoll = Timer.periodic(const Duration(seconds: 1), (_) {
      Future<void>(() async {
        if (_sleepFading) return;
        final type = _sleepQueueContextType;
        final id = _sleepQueueContextId;
        if (type == null || id == null) return;

        final tag = currentMediaItem;
        if (tag == null) return;

        final idx = player.currentIndex;
        if (idx == null) return;

        final ex = tag.extras;
        if (ex == null) return;
        if (ex['queueContextType']?.toString() != type) return;
        if (ex['queueContextId']?.toString() != id) return;
        if (_hasLaterContextItem(type, id, idx)) return;

        final d = player.duration;
        if (d == null) return;
        final remaining = d - player.position;
        if (remaining <= Duration.zero) {
          await _fadeAndPause(fadeOut);
          _cancelSleepTimerInternal();
          return;
        }
        if (fadeOut > Duration.zero && remaining <= fadeOut) {
          await _fadeAndPause(fadeOut);
          _cancelSleepTimerInternal();
        }
      });
    });
  }

  Future<void> previewFadeToSilence(Duration fadeOut) async {
    if (fadeOut <= Duration.zero) return;
    if (_sleepFading || _previewFading) return;
    _previewFading = true;
    final startFade = _fadeFactor;
    try {
      const steps = 20;
      final stepMs = max(40, (fadeOut.inMilliseconds / steps).round());
      final stepDur = Duration(milliseconds: stepMs);

      for (int i = 1; i <= steps; i++) {
        final t = i / steps;
        _fadeFactor = startFade * (1.0 - t);
        _applyEffectiveVolume();
        await Future.delayed(stepDur);
      }

      await Future.delayed(const Duration(milliseconds: 250));

      const restoreSteps = 10;
      const restoreTotal = Duration(milliseconds: 250);
      final restoreStepMs = max(
        20,
        (restoreTotal.inMilliseconds / restoreSteps).round(),
      );
      final restoreStep = Duration(milliseconds: restoreStepMs);
      for (int i = 1; i <= restoreSteps; i++) {
        final t = i / restoreSteps;
        _fadeFactor = startFade * t;
        _applyEffectiveVolume();
        await Future.delayed(restoreStep);
      }

      _fadeFactor = startFade;
      _applyEffectiveVolume();
    } finally {
      _previewFading = false;
    }
  }

  bool _hasLaterAlbumItem(String album, int currentIndex) {
    final seq = player.sequenceState?.sequence;
    if (seq == null) return false;
    for (int i = currentIndex + 1; i < seq.length; i++) {
      final tag = seq[i].tag;
      if (tag is MediaItem && (tag.album ?? '') == album) return true;
    }
    return false;
  }

  bool _hasLaterContextItem(String type, String id, int currentIndex) {
    final seq = player.sequenceState?.sequence;
    if (seq == null) return false;
    for (int i = currentIndex + 1; i < seq.length; i++) {
      final tag = seq[i].tag;
      if (tag is! MediaItem) continue;
      final ex = tag.extras;
      if (ex == null) continue;
      if (ex['queueContextType']?.toString() == type &&
          ex['queueContextId']?.toString() == id) {
        return true;
      }
    }
    return false;
  }

  void cancelSleepTimer() {
    _cancelSleepTimerInternal();
  }

  void _cancelSleepTimerInternal() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepPoll?.cancel();
    _sleepPoll = null;
  }

  Future<void> _fadeAndPause(Duration fadeOut) async {
    if (_sleepFading) return;
    _sleepFading = true;
    try {
      if (fadeOut <= Duration.zero) {
        await player.pause();
        return;
      }

      final startFade = _fadeFactor;
      const steps = 20;
      final stepMs = max(40, (fadeOut.inMilliseconds / steps).round());
      final stepDur = Duration(milliseconds: stepMs);

      for (int i = 1; i <= steps; i++) {
        final t = i / steps;
        _fadeFactor = startFade * (1.0 - t);
        _applyEffectiveVolume();
        await Future.delayed(stepDur);
      }

      await player.pause();

      _fadeFactor = startFade;
      _applyEffectiveVolume();
    } finally {
      _sleepFading = false;
    }
  }

  Future<void> toggleShuffle() async {
    final enable = !player.shuffleModeEnabled;
    if (enable) {
      await player.shuffle();
    }
    await player.setShuffleModeEnabled(enable);
  }

  Future<void> toggleLoopMode() async {
    final modes = [LoopMode.off, LoopMode.all, LoopMode.one];
    final current = player.loopMode;
    final next = modes[(modes.indexOf(current) + 1) % modes.length];
    await player.setLoopMode(next);
  }

  final player = AudioPlayer();
  final List<UriAudioSource> _sources = [];
  int currentIndex = 0;

  bool _neuralMixActive = false;
  final ValueNotifier<bool> neuralMixActiveNotifier = ValueNotifier(false);

  NeuralMixEnergyMode _neuralMixEnergyMode = NeuralMixEnergyMode.neutral;
  final ValueNotifier<NeuralMixEnergyMode> neuralMixEnergyModeNotifier =
      ValueNotifier(NeuralMixEnergyMode.neutral);

  // Library Cache for Quick Access
  List<oaq.SongModel> librarySongs = [];

  final ValueNotifier<bool> neuralMixBusy = ValueNotifier(false);

  void _setNeuralMixActive(bool value) {
    if (_neuralMixActive == value) return;
    _neuralMixActive = value;
    neuralMixActiveNotifier.value = value;
  }

  void cycleNeuralMixEnergyMode() {
    const modes = NeuralMixEnergyMode.values;
    final next =
        modes[(modes.indexOf(_neuralMixEnergyMode) + 1) % modes.length];
    _neuralMixEnergyMode = next;
    neuralMixEnergyModeNotifier.value = next;
    AnalyticsService.logEvent('neural_mix_mode', {'mode': next.name});
    developer.log('Neural mix energy mode -> $next', name: 'player.controller');
  }

  String _neuralMixEnergyModeArg() {
    switch (_neuralMixEnergyMode) {
      case NeuralMixEnergyMode.up:
        return 'up';
      case NeuralMixEnergyMode.down:
        return 'down';
      case NeuralMixEnergyMode.neutral:
        return 'neutral';
    }
  }

  String? _neuralMixWhy({
    required double? seedBpm,
    required String? seedKey,
    required String? seedArtist,
    required double? bpm,
    required String? key,
    required String? artist,
  }) {
    final parts = <String>[];

    if (seedBpm != null && bpm != null && seedBpm > 0 && bpm > 0) {
      final diff = (bpm - seedBpm).round();
      if (_neuralMixEnergyMode == NeuralMixEnergyMode.up && diff > 0) {
        parts.add('Energy ↑ $diff BPM');
      } else if (_neuralMixEnergyMode == NeuralMixEnergyMode.down && diff < 0) {
        parts.add('Energy ↓ ${diff.abs()} BPM');
      } else if (diff.abs() <= 4) {
        parts.add('Tempo match');
      }
    }

    if (seedKey != null &&
        seedKey.trim().isNotEmpty &&
        key != null &&
        key.trim().isNotEmpty) {
      if (seedKey.trim().toLowerCase() == key.trim().toLowerCase()) {
        parts.add('Key match');
      } else {
        parts.add('Harmonic');
      }
    }

    if (seedArtist != null &&
        seedArtist.trim().isNotEmpty &&
        artist != null &&
        artist.trim().isNotEmpty) {
      if (seedArtist.trim().toLowerCase() != artist.trim().toLowerCase()) {
        parts.add('Artist variety');
      }
    }

    if (parts.isEmpty) return null;
    return parts.take(3).join(' • ');
  }

  void updateLibrary(List<oaq.SongModel> songs) {
    librarySongs = _dedupeSongsByData(songs);
  }

  List<oaq.SongModel> _dedupeSongsByData(List<oaq.SongModel> songs) {
    if (songs.isEmpty) return const <oaq.SongModel>[];
    final out = <oaq.SongModel>[];
    final seen = HashSet<String>();
    for (final s in songs) {
      final key = songIdentity(s);
      if (key.isEmpty) continue;
      if (seen.add(key)) out.add(s);
    }
    return out;
  }

  Future<void> addToQueue(oaq.SongModel song) async {
    final extra =
        (_queueContextType != null &&
                _queueContextId != null &&
                !_neuralMixActive)
            ? <String, Object?>{
              'queueContextType': _queueContextType!,
              'queueContextId': _queueContextId!,
            }
            : null;

    final source = await _buildSource(song, extraExtras: extra);
    if (source == null) return;

    final audioSource = player.audioSource;
    if (audioSource is ConcatenatingAudioSource) {
      try {
        await audioSource.add(source);
        _sources.add(source);
      } catch (e) {
        debugPrint("Error adding to queue: $e");
      }
    } else {
      await replaceQueue([song]);
    }
  }

  Future<void> playNext(oaq.SongModel song) async {
    await insertNext(song);
  }

  final bookmarks = <Map<String, dynamic>>[];
  final ValueNotifier<List<Map<String, dynamic>>> bookmarksNotifier =
      ValueNotifier(const []);
  String currentId = '';

  // === Simplified bookmark key management ===
  // We maintain ONE stable key for the currently playing track.
  // It is set once when the track is loaded (from the MediaItem we created ourselves
  // which already contains the planted 'bookmarkKey'). This eliminates the previous
  // fragile re-resolution from sequenceState / _sources on every add/load, which
  // was the root cause of "save succeeds but bookmark never appears".
  String _currentBookmarkKey = '';
  bool _bookmarksPrefsMigrated = false;
  String _lastBookmarkLogKey = '';
  int _lastBookmarkLogCount = -1;
  String _lastBookmarkError = '';

  String get activeBookmarkKey => _currentBookmarkKey;
  String get lastBookmarkError => _lastBookmarkError;

  // Back-compat alias for any external code that was reading the old name
  @Deprecated('Use activeBookmarkKey')
  String get _activeBookmarkKey => _currentBookmarkKey;

  bool get hasQueue => player.sequenceState?.sequence.isNotEmpty ?? false;
  bool get isReady => hasQueue;

  MediaItem? get currentMediaItem {
    final seq = player.sequenceState;
    if (seq == null || seq.sequence.isEmpty) return null;
    final i = player.currentIndex ?? 0;
    final clamped = i.clamp(0, seq.sequence.length - 1);
    final src = seq.sequence[clamped];
    final tag = src.tag;
    return tag is MediaItem ? tag : null;
  }

  ContentMode get currentContentMode =>
      ContentModeDetector.detectFromMediaItem(currentMediaItem);

  String get currentSeriesKey =>
      ContentModeDetector.seriesKeyForMediaItem(currentMediaItem);

  int get skipIntervalSeconds => SettingsService.instance.seekSkipSeconds;

  Future<void> skipBackward() async {
    if (!isReady) return;
    final pos = player.position;
    final delta = Duration(seconds: skipIntervalSeconds);
    final newPos = pos - delta;
    await player.seek(newPos.isNegative ? Duration.zero : newPos);
  }

  Future<void> skipForward() async {
    if (!isReady) return;
    await player.seek(player.position + Duration(seconds: skipIntervalSeconds));
  }

  Future<void> setPlaybackSpeed(double speed) async {
    await setSpeed(speed.clamp(0.5, 3.0));
  }

  List<oaq.SongModel> songsInSeries(
    String seriesKey,
    List<oaq.SongModel> library,
  ) {
    if (seriesKey.isEmpty) return const [];
    final matches =
        library
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

  Future<void> resumeListeningProgress(
    ListeningProgress progress,
    List<oaq.SongModel> library, {
    bool autoPlay = true,
  }) async {
    final seriesSongs = songsInSeries(progress.seriesKey, library);
    oaq.SongModel? target;

    if (seriesSongs.length > 1) {
      final index = ListeningProgressRepository.resolveSeriesIndex(
        seriesSongs,
        progress,
      );
      await replaceQueue(seriesSongs, initialIndex: index, autoPlay: autoPlay);
    } else {
      target = ListeningProgressRepository.resolveSingleTrack(library, progress);
      if (target == null) return;
      await replaceQueue([target], autoPlay: autoPlay);
    }

    if (progress.positionMs > 0) {
      await player.seek(Duration(milliseconds: progress.positionMs));
    }
  }

  Future<List<ListeningProgress>> getRecentListening() =>
      ListeningProgressRepository.instance.getRecent();

  Future<void> dismissListeningProgress(String seriesKey) async {
    if (seriesKey.isEmpty) return;
    await ListeningProgressRepository.instance.delete(seriesKey);
  }

  void _prefetchNeighborArtwork() {
    // Artwork cache is Android-only (MediaStore).
    if (!Platform.isAndroid) return;
    final seq = player.sequenceState;
    if (seq == null || seq.sequence.isEmpty) return;
    final i = player.currentIndex;
    if (i == null) return;

    void prefetchAt(int index) {
      if (index < 0 || index >= seq.sequence.length) return;
      final tag = seq.sequence[index].tag;
      if (tag is! MediaItem) return;
      final mediaId = tag.extras?['mediaId'];
      if (mediaId is! int) return;
      ArtworkCacheService.instance
          .prefetchArtwork(id: mediaId, type: oaq.ArtworkType.AUDIO, size: 600)
          .catchError((_) {});
    }

    prefetchAt(i - 1);
    prefetchAt(i + 1);
  }

  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    session.interruptionEventStream.listen((event) {
      final mode = SettingsService.instance.audioFocusMode;
      if (mode == 'none') return;

      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
            if (mode == 'duck') {
              _duckFactor = 0.3;
              _applyEffectiveVolume();
            }
            break;
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            break;
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            _duckFactor = 1.0;
            _applyEffectiveVolume();
            break;
          case AudioInterruptionType.pause:
            break;
          case AudioInterruptionType.unknown:
            break;
        }
      }
    });
  }

  Future<void> _init() async {
    await _initAudioSession();
    await _loadFavorites();

    if (!_volumeInitialized) {
      _volumeInitialized = true;
      try {
        final prefs = await SharedPreferences.getInstance();
        _userVolume = (prefs.getDouble('user_volume') ?? 1.0).clamp(0.0, 1.0);
      } catch (_) {}
      _applyEffectiveVolume();
    }

    // Listen for track completion to update play counts
    player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        final item = currentMediaItem;
        if (item != null) {
          final songId = item.extras?['songId']?.toString();
          if (songId != null) {
            SongRepository.instance.incrementPlayCount(songId);
          }
        }

        // If Neural Mix is active, try to extend the queue and continue.
        if (_neuralMixActive) {
          Future<void>(() async {
            await _maybeExtendNeuralMix(force: true);
          });
        }
      }
    });

    player.currentIndexStream.listen((index) async {
      final tag = currentMediaItem;
      final idx = index ?? player.currentIndex ?? 0;

      // Only update the bookmark key when we have a real MediaItem.
      // We set a stable key once per track instead of re-resolving constantly.
      var keyResolved = false;
      if (tag != null) {
        _setCurrentBookmarkKey(tag);
        keyResolved = true;
      } else if (idx >= 0 && idx < _sources.length) {
        final src = _sources[idx];
        if (src.tag is MediaItem) {
          _setCurrentBookmarkKey(src.tag as MediaItem);
          keyResolved = true;
        } else if (src.uri.scheme == 'file') {
          _setCurrentBookmarkKey(null, fallbackUri: src.uri.toFilePath());
          keyResolved = true;
        }
      }

      _prefetchNeighborArtwork();

      // Update Last Played
      final songId = tag?.extras?['songId']?.toString();
      if (songId != null) {
        SongRepository.instance.updateLastPlayed(songId).catchError((_) {});
      }

      if (keyResolved) {
        await _loadBookmarks();
      }
      _saveState();

      // Smart Volume (ReplayGain + limiter) per-track.
      Future<void>(() async {
        await _updateSmartGainForCurrent();
      });

      // Keep Neural Mix going by ensuring there's always more queued.
      if (_neuralMixActive) {
        await _maybeExtendNeuralMix();
      }
    });

    player.playerStateStream.listen((state) {
      if (!state.playing) {
        _saveState();
      }
    });

    await player.setSkipSilenceEnabled(true);
    await player.setLoopMode(LoopMode.off); // Ensure stop at end

    // Crossfade (0 = gapless). Keep in sync with settings.
    _applyCrossfadeFromSettings();
    SettingsService.instance.addListener(_applyCrossfadeFromSettings);

    try {
      final sid = player.androidAudioSessionId ?? 0;
      if (sid != 0) {
        _lastSessionId = sid;
        await EqualizerService.initializeEqualizer(sid);
      }
    } catch (_) {}

    player.playbackEventStream.listen(
      (_) {
        try {
          final cur = player.androidAudioSessionId ?? 0;
          if (cur != 0 && cur != _lastSessionId) {
            _lastSessionId = cur;
            EqualizerService.initializeEqualizer(cur).catchError((_) {});
          }
        } catch (_) {}
      },
      onError: (Object e, StackTrace st) {
        debugPrint('Playback error: $e');
        _lastPlaybackError = e;
        _lastPlaybackErrorAt = DateTime.now();
        // Attempt to skip to next track on error
        if (player.hasNext) {
          debugPrint('Skipping to next track due to error...');
          player.seekToNext();
          player.play();
        }
      },
    );

    _initCompleter.complete();
  }

  Future<void> _saveState() async {
    final tag = currentMediaItem;
    if (tag == null) return;
    final prefs = await SharedPreferences.getInstance();
    final mediaId = tag.extras?['mediaId'];
    if (mediaId is int) {
      await prefs.setInt('last_song_original_id', mediaId);
    }
    final positionMs = player.position.inMilliseconds;
    await prefs.setInt('last_position_ms', positionMs);

    final mode = ContentModeDetector.detectFromMediaItem(tag);
    final seriesKey = ContentModeDetector.seriesKeyForMediaItem(tag);
    if (seriesKey.isEmpty) return;

    final path = (tag.extras?['path'] as String?) ?? tag.id;
    await ListeningProgressRepository.instance.recordFromPlayback(
      seriesKey: seriesKey,
      title: ContentModeDetector.displayTitleForSeries(tag),
      artist: tag.artist,
      songPath: path,
      mediaId: mediaId is int ? mediaId : null,
      positionMs: positionMs,
      contentMode: mode,
    );
  }

  Future<void> restoreState(List<oaq.SongModel> allSongs) async {
    if (hasQueue) return; // Don't restore if already playing (e.g. hot reload)

    final recent = await ListeningProgressRepository.instance.getRecent(limit: 1);
    if (recent.isNotEmpty) {
      try {
        await resumeListeningProgress(recent.first, allSongs, autoPlay: false);
        return;
      } catch (_) {
        // Fall through to legacy restore.
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final lastId = prefs.getInt('last_song_original_id');
    final lastPos = prefs.getInt('last_position_ms') ?? 0;

    if (lastId != null) {
      try {
        final song = allSongs.firstWhere((s) => s.id == lastId);
        await replaceQueue([song], autoPlay: false);
        await player.seek(Duration(milliseconds: lastPos));
      } catch (e) {
        // Song not found in current library
      }
    }
  }

  Future<void> replaceQueue(
    List<oaq.SongModel> songs, {
    int initialIndex = 0,
    bool autoPlay = true,
    String? queueContextType,
    String? queueContextId,
  }) async {
    _setNeuralMixActive(false);
    _sources.clear();

    _queueContextType = queueContextType;
    _queueContextId = queueContextId;

    final extra =
        (queueContextType != null && queueContextId != null)
            ? <String, Object?>{
              'queueContextType': queueContextType,
              'queueContextId': queueContextId,
            }
            : null;

    // Parallel processing for speed
    final sources = await Future.wait(
      songs.map((s) => _buildSource(s, extraExtras: extra)),
    );

    int adjustedIndex = 0;
    int validCount = 0;

    for (int i = 0; i < sources.length; i++) {
      final source = sources[i];
      if (source != null) {
        _sources.add(source);
        if (i == initialIndex) adjustedIndex = validCount;
        validCount++;
      } else if (i == initialIndex) {
        adjustedIndex = validCount;
      }
    }

    if (adjustedIndex >= _sources.length) {
      adjustedIndex = max(0, _sources.length - 1);
    }

    if (_sources.isEmpty) return;

    try {
      await player.setAudioSources(
        _sources,
        initialIndex: adjustedIndex,
        initialPosition: Duration.zero,
        preload: true,
      );
      if (autoPlay) {
        await player.play();
      }

      final media = currentMediaItem;
      _setCurrentBookmarkKey(media);
      await _loadBookmarks();
    } catch (e) {
      debugPrint("Error setting audio source: $e");
    }
  }

  Future<void> insertNext(oaq.SongModel song) async {
    if (!hasQueue) {
      await replaceQueue([song]);
      return;
    }

    final extra =
        (_queueContextType != null &&
                _queueContextId != null &&
                !_neuralMixActive)
            ? <String, Object?>{
              'queueContextType': _queueContextType!,
              'queueContextId': _queueContextId!,
            }
            : null;

    final source = await _buildSource(song, extraExtras: extra);
    if (source == null) return;

    final audioSource = player.audioSource;
    if (audioSource is ConcatenatingAudioSource) {
      final current = player.currentIndex ?? 0;
      final insertAt = (current + 1).clamp(0, audioSource.length);

      try {
        await audioSource.insert(insertAt, source);
        _sources.insert(insertAt, source);
      } catch (e) {
        debugPrint("Error inserting next: $e");
      }
    }
  }

  void _applyCrossfadeFromSettings() {
    final sec = SettingsService.instance.crossfadeSeconds.clamp(0, 12);
    try {
      // ignore: avoid_dynamic_calls
      (player as dynamic).setCrossFadeEnabled(sec > 0);
      // ignore: avoid_dynamic_calls
      (player as dynamic).setCrossFadeDuration(Duration(seconds: sec));
    } catch (_) {}
  }

  Future<void> setUserVolume(double volume) async {
    _userVolume = volume.clamp(0.0, 1.0);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('user_volume', _userVolume);
    } catch (_) {}
    _applyEffectiveVolume();
  }

  void _applyEffectiveVolume() {
    final v = (_userVolume * _duckFactor * _smartGain * _fadeFactor).clamp(
      0.0,
      1.0,
    );
    try {
      player.setVolume(v);
    } catch (_) {}
  }

  Future<void> _updateSmartGainForCurrent() async {
    final settings = SettingsService.instance;
    if (!settings.replayGainEnabled && !settings.smartVolumeLimiterEnabled) {
      if (_smartGain != 1.0) {
        _smartGain = 1.0;
        _applyEffectiveVolume();
      }
      return;
    }

    final item = currentMediaItem;
    final path = item?.extras?['path']?.toString();
    if (path == null || path.isEmpty) return;

    Map<String, double?> rg;
    try {
      rg = await compute(_readReplayGainForPath, path);
    } catch (_) {
      return;
    }

    final trackGainDb = rg['trackGainDb'];
    final trackPeak = rg['trackPeak'];

    double gain = 1.0;
    if (settings.replayGainEnabled && trackGainDb != null) {
      gain *= pow(10.0, trackGainDb / 20.0).toDouble();
    }
    if (settings.smartVolumeLimiterEnabled &&
        trackPeak != null &&
        trackPeak > 0) {
      final limiter = (0.98 / trackPeak).clamp(0.0, 1.0);
      gain *= limiter;
    }

    gain = gain.clamp(0.25, 1.80);
    if ((gain - _smartGain).abs() < 0.01) return;
    _smartGain = gain;
    _applyEffectiveVolume();
  }

  Future<void> playAt(int index) async {
    if (!isReady) return;
    await player.seek(Duration.zero, index: index);
    await player.play();
  }

  Future<UriAudioSource?> _buildSource(
    oaq.SongModel s, {
    Map<String, Object?>? extraExtras,
  }) async {
    if (s.data.isEmpty) return null;

    Uri uri;
    if (Platform.isAndroid) {
      uri = Uri.parse("content://media/external/audio/media/${s.id}");
    } else {
      // Use Uri.file to handle Windows paths correctly
      uri = Uri.file(s.data);
    }

    // Check if file exists for Windows
    if (!Platform.isAndroid) {
      if (!await File(s.data).exists()) {
        debugPrint("File not found: ${s.data}");
        return null;
      }
    }

    Uri artUri;
    if (Platform.isAndroid) {
      artUri = Uri.parse(
        "content://media/external/audio/media/${s.id}/albumart",
      );
    } else {
      // Use Uri.file for artwork path too
      artUri = Uri.file(s.data);
    }

    return AudioSource.uri(
      uri,
      tag: MediaItem(
        id: s.data, // Using data (path) as ID for background service consistency
        album: s.album ?? "Unknown Album",
        title: s.title,
        artist: s.artist ?? "Unknown Artist",
        duration: Duration(milliseconds: s.duration ?? 0),
        artUri: artUri,
        extras: {
          'path': s.data,
          'songId': s.data, // canonical key (file path) for metadata, favorites, Neural Mix etc.
          'bookmarkKey': BookmarkKey.canonical(s.data),
          'mediaId': s.id, // Store original MediaStore ID as int
          if (extraExtras != null) ...extraExtras,
        },
      ),
    );
  }

  List<String> _bookmarkAliasesFor(MediaItem? media) {
    if (media == null) {
      return _currentBookmarkKey.isEmpty
          ? const []
          : [_currentBookmarkKey];
    }

    final mediaId = media.extras?['mediaId'];
    return BookmarkKey.aliasesForTrack(
      bookmarkKey: media.extras?['bookmarkKey']?.toString(),
      path: media.extras?['path']?.toString() ?? media.id,
      mediaId: mediaId is int ? mediaId : int.tryParse('$mediaId'),
      itemId: media.id,
    );
  }

  /// Sets (or updates) the stable bookmark key for whatever is currently playing.
  /// We prefer the 'bookmarkKey' we ourselves planted in the MediaItem at enqueue time
  /// (see _buildSource and playExternalFile). This is the only reliable way to have
  /// the same key at save time and at list-view/reload time.
  /// Attempts to set the bookmark key from the current media item.
  /// If no valid key can be resolved (transient null state during track
  /// transitions) the old key is left in place so that existing bookmarks
  /// are NOT wiped by a brief window where the player hasn't settled yet.
  void _setCurrentBookmarkKey(MediaItem? media, {String? fallbackUri}) {
    String? candidate;

    if (media != null) {
      // Best case: the key we planted ourselves when we built the AudioSource
      candidate = media.extras?['bookmarkKey']?.toString();
      if (candidate == null || candidate.isEmpty) {
        candidate = media.extras?['path']?.toString();
      }
      if (candidate == null || candidate.isEmpty) {
        candidate = media.id;
      }
    }

    if ((candidate == null || candidate.isEmpty) && fallbackUri != null) {
      candidate = fallbackUri;
    }

    final newKey = BookmarkKey.canonical(candidate ?? '');
    // If we can't resolve a key right now (transient null) do NOT clear the
    // existing key — the previous track's bookmarks should remain visible
    // until the new track has definitively resolved.
    if (newKey.isEmpty) return;

    if (newKey != _currentBookmarkKey) {
      _currentBookmarkKey = newKey;
      currentId = newKey;
      if (kDebugMode) {
        debugPrint('[BOOKMARKS] current key set to $newKey');
      }
    }
  }

  int _bookmarkPos(Map<String, dynamic> bookmark) =>
      (bookmark['pos'] as num?)?.toInt() ?? 0;

  Map<String, dynamic>? _parseBookmarkEntry(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final pos = (map['pos'] as num?)?.toInt();
      if (pos == null) return null;
      return {'pos': pos, 'note': (map['note'] as String?) ?? ''};
    } catch (_) {
      final ms = int.tryParse(raw);
      if (ms == null) return null;
      return {'pos': ms, 'note': ''};
    }
  }

  Future<void> _migrateBookmarksFromPrefsIfNeeded() async {
    if (_bookmarksPrefsMigrated) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('bookmarks_db_migrated') == true) {
        _bookmarksPrefsMigrated = true;
        return;
      }

      for (final prefKey in prefs.getKeys()) {
        if (!prefKey.startsWith('bookmarks_')) continue;
        final rawTrackKey = prefKey.substring('bookmarks_'.length);
        final trackKey = BookmarkKey.canonical(rawTrackKey);
        if (trackKey.isEmpty) continue;

        final entries = prefs.getStringList(prefKey) ?? [];
        for (final entry in entries) {
          final parsed = _parseBookmarkEntry(entry);
          if (parsed == null) continue;
          await DatabaseService.instance.upsertBookmark(
            trackKey: trackKey,
            positionMs: _bookmarkPos(parsed),
            note: (parsed['note'] as String?) ?? '',
          );
        }
      }

      await prefs.setBool('bookmarks_db_migrated', true);
      _bookmarksPrefsMigrated = true;
    } catch (e) {
      _lastBookmarkError = 'migration failed: $e';
      if (kDebugMode) {
        debugPrint('[BOOKMARKS] $_lastBookmarkError');
      }
      _bookmarksPrefsMigrated = true;
    }
  }

  void _publishBookmarks(List<Map<String, dynamic>> rows) {
    bookmarks
      ..clear()
      ..addAll(rows);
    bookmarksNotifier.value = List<Map<String, dynamic>>.unmodifiable(bookmarks);
  }

  /// Loads bookmarks for whatever track is currently considered "the one".
  /// Uses the single stable _currentBookmarkKey we set when the track started playing.
  Future<void> _loadBookmarks({bool forceLog = false}) async {
    // Wait for the controller to finish initialising so that the
    // currentIndexStream listener and audio session are ready.
    if (!_initCompleter.isCompleted) {
      await _initCompleter.future;
    }

    await _migrateBookmarksFromPrefsIfNeeded();

    if (_currentBookmarkKey.isEmpty) {
      // Don't wipe existing bookmarks during transient null-key windows
      // (e.g. track transition where _setCurrentBookmarkKey hasn't resolved yet).
      if (bookmarks.isNotEmpty) {
        return;
      }
      _publishBookmarks(const []);
      if (kDebugMode) {
        debugPrint('[BOOKMARKS] load skipped: no current bookmark key');
      }
      return;
    }

    final media = currentMediaItem;
    final aliases = _bookmarkAliasesFor(media);
    final rows = await BookmarkRepository.instance.loadForTrack(
      _currentBookmarkKey,
      aliases: aliases,
    );

    // Keep optimistic entries if storage hasn't caught up yet (common right
    // after save while prefs/async DB settle).
    if (rows.isEmpty && bookmarks.isNotEmpty) {
      final hasFreshLocal = bookmarks.any(
        (b) => b['source'] == 'just-added',
      );
      if (hasFreshLocal) return;
    }

    _publishBookmarks(rows);

    if (kDebugMode &&
        (forceLog ||
            _currentBookmarkKey != _lastBookmarkLogKey ||
            rows.length != _lastBookmarkLogCount)) {
      _lastBookmarkLogKey = _currentBookmarkKey;
      _lastBookmarkLogCount = rows.length;
      debugPrint('[BOOKMARKS] track=$_currentBookmarkKey count=${rows.length}');
    }
  }

  Future<bool> addBookmark({String note = ''}) async {
    _lastBookmarkError = '';
    if (!_initCompleter.isCompleted) {
      await _initCompleter.future;
    }
    if (!isReady) {
      _lastBookmarkError = 'nothing playing';
      return false;
    }

    // Re-sync from the live MediaItem every time — audiobook dialogs can open
    // across layout/keyboard transitions where the cached key was never set.
    _setCurrentBookmarkKey(currentMediaItem);
    if (_currentBookmarkKey.isEmpty) {
      final idx = player.currentIndex ?? 0;
      if (idx >= 0 && idx < _sources.length) {
        final src = _sources[idx];
        if (src.tag is MediaItem) {
          _setCurrentBookmarkKey(src.tag as MediaItem);
        } else if (src.uri.scheme == 'file') {
          _setCurrentBookmarkKey(null, fallbackUri: src.uri.toFilePath());
        }
      }
    }
    final key = _currentBookmarkKey;

    if (key.isEmpty) {
      _lastBookmarkError = 'could not resolve track key';
      if (kDebugMode) {
        debugPrint('[BOOKMARKS] add failed: no current bookmark key');
      }
      return false;
    }

    final pos = player.position.inMilliseconds;
    final trimmedNote = note.trim();

    try {
      final saved = await BookmarkRepository.instance.add(
        trackKey: key,
        positionMs: pos,
        note: trimmedNote,
      );

      if (!saved) {
        _lastBookmarkError = 'storage write failed';
        if (kDebugMode) {
          debugPrint('[BOOKMARKS] add failed: repo returned false key=$key pos=$pos');
        }
        return false;
      }

      // === Optimistic update so the user sees it immediately ===
      final newBookmark = <String, dynamic>{
        'id': -pos, // negative = prefs-backed until we reload from DB
        'pos': pos,
        'note': trimmedNote,
        'source': 'just-added',
      };

      // Replace if there was already one at exactly this position
      bookmarks.removeWhere((b) => _bookmarkPos(b) == pos);
      bookmarks.add(newBookmark);
      bookmarks.sort((a, b) => _bookmarkPos(a).compareTo(_bookmarkPos(b)));
      bookmarksNotifier.value = List<Map<String, dynamic>>.unmodifiable(bookmarks);

      // Reconcile with storage (DB ids, legacy keys, media-id aliases).
      await _loadBookmarks(forceLog: true);

      if (kDebugMode) {
        debugPrint('[BOOKMARKS] add success: key=$key pos=$pos (optimistic publish done)');
      }
      return true;
    } catch (e) {
      _lastBookmarkError = '$e';
      if (kDebugMode) {
        debugPrint('[BOOKMARKS] add failed: $e');
      }
      return false;
    }
  }

  Future<void> updateBookmarkNote(int index, String note) async {
    if (!_initCompleter.isCompleted) {
      await _initCompleter.future;
    }
    if (index < 0 || index >= bookmarks.length) return;
    if (_currentBookmarkKey.isEmpty) return;

    await BookmarkRepository.instance.updateNote(
      trackKey: _currentBookmarkKey,
      bookmark: bookmarks[index],
      note: note,
    );
    await _loadBookmarks();
  }

  Future<void> removeBookmark(int i) async {
    if (!_initCompleter.isCompleted) {
      await _initCompleter.future;
    }
    if (i < 0 || i >= bookmarks.length) return;
    if (_currentBookmarkKey.isEmpty) return;

    await BookmarkRepository.instance.remove(
      trackKey: _currentBookmarkKey,
      bookmark: bookmarks[i],
    );
    await _loadBookmarks();
  }

  Future<void> reloadBookmarks() async {
    await _loadBookmarks();
  }

  Future<void> play() async {
    // After natural end of last track (completed, no more queued), reset to start
    // so that the main play button reliably replays the current track.
    if (player.processingState == ProcessingState.completed) {
      try {
        await player.seek(Duration.zero);
      } catch (_) {}
    }
    await player.play();
  }

  Future<void> pause() async {
    await player.pause();
  }

  Future<void> stop() async {
    await player.stop();
  }

  Future<void> jumpTo(int ms) async {
    if (!isReady) return;
    await player.seek(Duration(milliseconds: ms));
  }

  Future<void> smartShuffle() async {
    if (!isReady) return;
    if (neuralMixBusy.value) return;

    final seedItem = currentMediaItem;
    if (seedItem == null) return;
    final seedId = seedItem.extras?['songId']?.toString();
    if (seedId == null) return;

    neuralMixBusy.value = true;
    try {
      _setNeuralMixActive(true);

      final repo = SongRepository.instance;
      final seedMeta = await repo.getMetadata(seedId);

      if (librarySongs.isEmpty) {
        try {
          librarySongs = await oaq.OnAudioQuery().querySongs(
            sortType: oaq.SongSortType.DATE_ADDED,
            orderType: oaq.OrderType.DESC_OR_GREATER,
            uriType: oaq.UriType.EXTERNAL,
          );
          librarySongs = _dedupeSongsByData(librarySongs);
        } catch (e) {
          debugPrint("Error fetching library for Smart Shuffle: $e");
        }
      }

      final seedBpm = seedMeta?.bpm;
      final seedKey = seedMeta?.key;
      if (seedBpm == null && (seedKey == null || seedKey.trim().isEmpty)) {
        debugPrint(
          "Neural Mix: No DNA found for seed song. Generating random mix.",
        );
      }

      final allMeta = await repo.getAllMetadata();
      final metaMap = {for (final m in allMeta) m.id: m};

      final songById = <String, oaq.SongModel>{
        for (final s in librarySongs) songIdentity(s): s,
      };
      final seedSong = songById[seedId];
      final seedArtist = seedSong?.artist?.trim().toLowerCase();

      final songRows = <Map<String, dynamic>>[];
      for (final song in librarySongs) {
        final id = songIdentity(song);
        final meta = metaMap[id] ?? metaMap[song.id.toString()]; // fallback for legacy DB keys
        songRows.add({
          'id': id,
          'artist': song.artist ?? '',
          'bpm': meta?.bpm,
          'key': meta?.key,
        });
      }

      final exclude = <String>{};
      final seq = player.sequenceState;
      if (seq != null) {
        for (final src in seq.sequence) {
          final tag = src.tag;
          if (tag is MediaItem) {
            final id = tag.extras?['songId']?.toString();
            if (id != null && id.isNotEmpty) exclude.add(id);
          }
        }
      }

      final pickedIds = await compute(_neuralMixRankSongIds, {
        'seedId': seedId,
        'seedBpm': seedBpm,
        'seedKey': seedKey,
        'seedArtist': seedArtist,
        'count': 50,
        'excludeSongIds': exclude.toList(growable: false),
        'songs': songRows,
        'energyMode': _neuralMixEnergyModeArg(),
        'randomSeed': DateTime.now().microsecondsSinceEpoch,
      });

      final mix = <oaq.SongModel>[];
      for (final id in pickedIds) {
        final s = songById[id];
        if (s != null) mix.add(s);
      }

      if (mix.isEmpty) {
        debugPrint("Neural Mix: Library is empty. Cannot generate mix.");
        _setNeuralMixActive(false);
        return;
      }

      final mixSources = <UriAudioSource>[];
      for (final s in mix) {
        final id = songIdentity(s);
        final meta = metaMap[id] ?? metaMap[s.id.toString()];
        final why = _neuralMixWhy(
          seedBpm: seedBpm,
          seedKey: seedKey,
          seedArtist: seedArtist,
          bpm: meta?.bpm,
          key: meta?.key,
          artist: s.artist,
        );
        final extra =
            why == null ? null : <String, Object?>{'neuralMixWhy': why};
        final source = await _buildSource(s, extraExtras: extra);
        if (source != null) mixSources.add(source);
      }

      debugPrint("Neural Mix: Generated ${mixSources.length} tracks.");

      if (mixSources.isEmpty) {
        _setNeuralMixActive(false);
        return;
      }

      // Prefer inserting into existing playlist to avoid disrupting playback.
      final audioSource = player.audioSource;
      if (audioSource is ConcatenatingAudioSource) {
        final insertIndex = (player.currentIndex ?? 0) + 1;
        try {
          await audioSource.insertAll(insertIndex, mixSources);
          final safeIndex = insertIndex.clamp(0, _sources.length);
          _sources.insertAll(safeIndex, mixSources);
        } catch (e) {
          debugPrint("Neural Mix Error (insertAll): $e");
        }
      } else {
        // Fallback: rebuild sources (may restart playback).
        final seq = player.sequenceState?.sequence ?? [];

        _sources.clear();
        if (seq.isNotEmpty) {
          final currentIndex = player.currentIndex ?? 0;
          if (currentIndex < seq.length) {
            final currentSource = seq[currentIndex];
            if (currentSource is UriAudioSource) {
              _sources.add(currentSource);
            }
          }
        }
        _sources.addAll(mixSources);

        try {
          final wasPlaying = player.playing;
          await player.setAudioSources(
            _sources,
            initialIndex: 0,
            initialPosition: player.position,
          );
          if (wasPlaying) await player.play();
        } catch (e) {
          debugPrint("Neural Mix Error: $e");
        }
      }

      await player.setShuffleModeEnabled(false);
    } catch (e) {
      debugPrint("Neural Mix Error: $e");
      _setNeuralMixActive(false);
    } finally {
      neuralMixBusy.value = false;
    }
  }

  Future<void> _maybeExtendNeuralMix({bool force = false}) async {
    if (!_neuralMixActive) return;
    if (neuralMixBusy.value) return;

    final audioSource = player.audioSource;
    if (audioSource is! ConcatenatingAudioSource) return;

    final cur = player.currentIndex ?? 0;
    final remaining = audioSource.length - cur - 1;
    if (!force && remaining >= 8) return;

    final seedItem = currentMediaItem;
    final seedId = seedItem?.extras?['songId']?.toString();
    if (seedId == null) return;

    neuralMixBusy.value = true;
    try {
      final exclude = <String>{};
      final seq = player.sequenceState;
      if (seq != null) {
        for (final src in seq.sequence) {
          final tag = src.tag;
          if (tag is MediaItem) {
            final id = tag.extras?['songId']?.toString();
            if (id != null && id.isNotEmpty) exclude.add(id);
          }
        }
      }

      final newSources = await _generateNeuralMixSources(
        seedId: seedId,
        count: 25,
        excludeSongIds: exclude,
      );

      if (newSources.isEmpty) return;

      final insertAt = audioSource.length;
      try {
        await audioSource.insertAll(insertAt, newSources);
        _sources.addAll(newSources);
      } catch (e) {
        debugPrint('Neural Mix Error (auto extend): $e');
        return;
      }

      // If we had already reached "completed", jump into the newly added track.
      if (player.processingState == ProcessingState.completed) {
        final nextIndex = (player.currentIndex ?? 0) + 1;
        if (nextIndex < audioSource.length) {
          try {
            await player.seek(Duration.zero, index: nextIndex);
            await player.play();
          } catch (_) {}
        }
      }
    } finally {
      neuralMixBusy.value = false;
    }
  }

  Future<List<UriAudioSource>> _generateNeuralMixSources({
    required String seedId,
    required int count,
    required Set<String> excludeSongIds,
  }) async {
    final repo = SongRepository.instance;
    final seedMeta = await repo.getMetadata(seedId);

    if (librarySongs.isEmpty) {
      try {
        librarySongs = await oaq.OnAudioQuery().querySongs(
          sortType: oaq.SongSortType.DATE_ADDED,
          orderType: oaq.OrderType.DESC_OR_GREATER,
          uriType: oaq.UriType.EXTERNAL,
        );
        librarySongs = _dedupeSongsByData(librarySongs);
      } catch (e) {
        debugPrint('Error fetching library for Neural Mix: $e');
      }
    }

    if (librarySongs.isEmpty) return const <UriAudioSource>[];

    final seedBpm = seedMeta?.bpm;
    final seedKey = seedMeta?.key;

    final allMeta = await repo.getAllMetadata();
    final metaMap = {for (final m in allMeta) m.id: m};

    final songById = <String, oaq.SongModel>{
      for (final s in librarySongs) songIdentity(s): s,
    };
    final seedArtist = songById[seedId]?.artist?.trim().toLowerCase();

    final songRows = <Map<String, dynamic>>[];
    for (final song in librarySongs) {
      final id = songIdentity(song);
      final meta = metaMap[id] ?? metaMap[song.id.toString()]; // fallback for legacy DB keys
      songRows.add({
        'id': id,
        'artist': song.artist ?? '',
        'bpm': meta?.bpm,
        'key': meta?.key,
      });
    }

    final pickedIds = await compute(_neuralMixRankSongIds, {
      'seedId': seedId,
      'seedBpm': seedBpm,
      'seedKey': seedKey,
      'seedArtist': seedArtist,
      'count': count,
      'excludeSongIds': excludeSongIds.toList(growable: false),
      'songs': songRows,
      'energyMode': _neuralMixEnergyModeArg(),
      'randomSeed': DateTime.now().microsecondsSinceEpoch,
    });

    final picked = <oaq.SongModel>[];
    for (final id in pickedIds) {
      final s = songById[id];
      if (s != null) picked.add(s);
    }

    if (picked.isEmpty) return const <UriAudioSource>[];

    final mixSources = <UriAudioSource>[];
    for (final s in picked) {
      final id = songIdentity(s);
      final meta = metaMap[id] ?? metaMap[s.id.toString()];
      final why = _neuralMixWhy(
        seedBpm: seedBpm,
        seedKey: seedKey,
        seedArtist: seedArtist,
        bpm: meta?.bpm,
        key: meta?.key,
        artist: s.artist,
      );
      final extra = why == null ? null : <String, Object?>{'neuralMixWhy': why};
      final source = await _buildSource(s, extraExtras: extra);
      if (source != null) mixSources.add(source);
    }
    return mixSources;
  }

  Future<void> setSpeed(double speed) async {
    await player.setSpeed(speed);
  }

  Future<void> removeFromQueue(int index) async {
    final audioSource = player.audioSource;
    if (audioSource is ConcatenatingAudioSource) {
      if (index >= 0 && index < audioSource.length) {
        try {
          await audioSource.removeAt(index);
          if (index < _sources.length) {
            _sources.removeAt(index);
          }
        } catch (e) {
          debugPrint("Error removing from queue: $e");
        }
      }
    }
  }

  /// Reorder the current playback queue (supports drag-to-reorder in Now Playing list).
  /// Keeps both the ConcatenatingAudioSource and our _sources list in sync.
  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    final audioSource = player.audioSource;
    if (audioSource is! ConcatenatingAudioSource) return;
    if (oldIndex < 0 || oldIndex >= audioSource.length) return;
    // Caller (ReorderableListView) conventionally does: if (old < new) new--;
    // Clamp newIndex just in case.
    newIndex = newIndex.clamp(0, audioSource.length - 1);
    if (oldIndex == newIndex) return;
    try {
      await audioSource.move(oldIndex, newIndex);
      if (oldIndex < _sources.length && newIndex < _sources.length) {
        final item = _sources.removeAt(oldIndex);
        _sources.insert(newIndex, item);
      }
    } catch (e) {
      debugPrint("Error reordering queue: $e");
    }
  }

  // External file playback (e.g., Android "Open with")
  Future<void> playExternalFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('External file not found: $filePath');
        return;
      }

      final canonicalPath = BookmarkKey.canonical(filePath);
      final uri = Uri.file(filePath);
      final source = AudioSource.uri(
        uri,
        tag: MediaItem(
          id: canonicalPath,
          title: file.uri.pathSegments.isNotEmpty
              ? file.uri.pathSegments.last
              : 'External audio',
          artist: 'External',
          extras: {
            'path': canonicalPath,
            'songId': canonicalPath,
            'bookmarkKey': canonicalPath,
          },
        ),
      );

      _sources
        ..clear()
        ..add(source);
      await player.setAudioSources([source]);
      _setCurrentBookmarkKey(currentMediaItem, fallbackUri: filePath);
      await _loadBookmarks();
      await player.play();
    } catch (e) {
      debugPrint('Error playing external file: $e');
    }
  }

  // Favorites
  final ValueNotifier<List<String>> favoritesNotifier = ValueNotifier([]);

  bool isFavorite(String id) => favoritesNotifier.value.contains(id);

  Future<void> toggleFavorite(String id) async {
    final list = List<String>.from(favoritesNotifier.value);
    if (list.contains(id)) {
      list.remove(id);
    } else {
      list.add(id);
    }
    favoritesNotifier.value = list;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorites', list);
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('favorites') ?? [];
    favoritesNotifier.value = list;
  }
}
