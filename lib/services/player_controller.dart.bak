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

import '../repositories/song_repository.dart';
import '../utils/replaygain_tag_reader.dart';
import 'analytics_service.dart';
import 'artwork_cache_service.dart';
import 'equalizer_service.dart';
import 'logger_service.dart';
import 'settings_service.dart';
import 'telemetry_service.dart';

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
  static PlayerController ensure() => _i ??= PlayerController._().._init();

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
    final seq = player.sequenceState.sequence;
    for (int i = currentIndex + 1; i < seq.length; i++) {
      final tag = seq[i].tag;
      if (tag is MediaItem && (tag.album ?? '') == album) return true;
    }
    return false;
  }

  bool _hasLaterContextItem(String type, String id, int currentIndex) {
    final seq = player.sequenceState.sequence;
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
      final data = s.data;
      if (data.isEmpty) continue;
      final key = Platform.isWindows ? data.toLowerCase() : data;
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
    // ignore: deprecated_member_use
    if (audioSource is ConcatenatingAudioSource) {
      try {
        await audioSource.add(source);
        _sources.add(source);
      } catch (e, st) {
        LoggerService.instance.warning('Error adding to queue: $e', e, st);
      }
    } else {
      await replaceQueue([song]);
    }
  }

  Future<void> playNext(oaq.SongModel song) async {
    // Alias for insertNext to avoid confusion, or we can deprecate this.
    // For now, let's redirect to insertNext which handles the logic.
    await insertNext(song);
  }

  final bookmarks = <Map<String, dynamic>>[];
  final ValueNotifier<List<Map<String, dynamic>>> bookmarksNotifier = ValueNotifier(const []);
  String currentId = '';
  String? _lastBookmarkLoadId;
  Future<SharedPreferences>? _sharedPreferencesFuture;

  bool get hasQueue => (player.sequenceState.sequence.isNotEmpty);
  bool get isReady => hasQueue;

  String? get activeBookmarkId {
    final current = currentMediaItem?.id;
    if (current != null && current.isNotEmpty) return current;
    if (currentId.isNotEmpty) return currentId;
    return null;
  }

  void _syncBookmarks() {
    bookmarksNotifier.value = List<Map<String, dynamic>>.unmodifiable(bookmarks);
  }

  Future<SharedPreferences> get _sharedPreferences async {
    return _sharedPreferencesFuture ??= SharedPreferences.getInstance();
  }

  MediaItem? get currentMediaItem {
    final seq = player.sequenceState;
    if (seq.sequence.isEmpty) return null;
    final i = player.currentIndex ?? 0;
    final clamped = i.clamp(0, seq.sequence.length - 1);
    final src = seq.sequence[clamped];
    final tag = src.tag;
    return tag is MediaItem ? tag : null;
  }

  void _prefetchNeighborArtwork() {
    // Artwork cache is Android-only (MediaStore).
    if (!Platform.isAndroid) return;
    final seq = player.sequenceState;
    if (seq.sequence.isEmpty) return;
    final i = player.currentIndex;
    if (i == null) return;

    void prefetchAt(int index) {
      if (index < 0 || index >= seq.sequence.length) return;
      final tag = seq.sequence[index].tag;
      if (tag is! MediaItem) return;
      final songId = tag.extras?['songId'];
      if (songId is! int) return;
      ArtworkCacheService.instance
          .prefetchArtwork(id: songId, type: oaq.ArtworkType.AUDIO, size: 600)
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
    debugPrint("PlayerController: _init started");
    await _initAudioSession();
    await _loadFavorites();
    debugPrint("PlayerController: _initAudioSession done");

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
      // Helpful breadcrumbs for playback failures that don't throw synchronously.
      if (Platform.isWindows) {
        debugPrint(
          'PlayerState: playing=${state.playing} processing=${state.processingState} index=${player.currentIndex}',
        );
      }
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

    player.currentIndexStream.listen((_) async {
      final tag = currentMediaItem;
      if (tag == null) return;
      final nextId = tag.id;
      final shouldReloadBookmarks = nextId != currentId;
      currentId = nextId;

      _prefetchNeighborArtwork();

      // Update Last Played
      final songId = tag.extras?['songId']?.toString();
      if (songId != null) {
        SongRepository.instance.updateLastPlayed(songId).catchError((_) {});
      }

      if (shouldReloadBookmarks) {
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
    debugPrint("PlayerController: player configured");

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
        _logAudioError('playbackEventStream', e, st);

        // Attempt to skip to next track on error (mobile only).
        // On desktop, skipping can hide the real failure from the user.
        if (Platform.isAndroid && player.hasNext) {
          debugPrint('Skipping to next track due to error...');
          player.seekToNext();
          player.play();
        }
      },
    );
  }

  Future<void> _saveState() async {
    final tag = currentMediaItem;
    if (tag == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (tag.extras != null && tag.extras!.containsKey('songId')) {
        await prefs.setInt('last_song_original_id', tag.extras!['songId'] as int);
      }
      await prefs.setInt('last_position_ms', player.position.inMilliseconds);
    } catch (e) {
      // Handle save error silently
    }
  }

  Future<void> restoreState(List<oaq.SongModel> allSongs) async {
    if (hasQueue) return; // Don't restore if already playing (e.g. hot reload)
    try {
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
    } catch (e) {
      // Handle restore error silently
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
    } catch (e, st) {
      _logAudioError('setAudioSources(replaceQueue)', e, st, sources: _sources);
      return;
    }

    if (autoPlay) {
      try {
        await player.play();
      } catch (e, st) {
        _logAudioError('play(replaceQueue)', e, st);
      }
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
    // ignore: deprecated_member_use
    if (audioSource is ConcatenatingAudioSource) {
      final current = player.currentIndex ?? 0;
      final insertAt = (current + 1).clamp(0, audioSource.length);

      try {
        await audioSource.insert(insertAt, source);
        _sources.insert(insertAt, source);
      } catch (e, st) {
        LoggerService.instance.warning('Error inserting next: $e', e, st);
      }
    }
  }

  void _applyCrossfadeFromSettings() {
    final sec = SettingsService.instance.crossfadeSeconds.clamp(0, 12);
    try {
      // just_audio API differs across versions; keep this best-effort.
      // Some versions require enabling/disabling separately.
      try {
        (player as dynamic).setCrossFadeEnabled(sec > 0);
      } catch (_) {}
      try {
        (player as dynamic).setCrossFadeDuration(Duration(seconds: sec));
      } catch (_) {}
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

    // Some code paths persist a file:// URI instead of a raw filesystem path.
    // Normalize so Windows/macOS/Linux playback works reliably.
    final rawData = s.data;
    String normalizedPath = rawData;
    if (!Platform.isAndroid && rawData.startsWith('file://')) {
      try {
        normalizedPath = Uri.parse(rawData).toFilePath();
      } catch (_) {
        // Fall back to the raw string.
        normalizedPath = rawData;
      }
    }

    Uri uri;
    if (Platform.isAndroid) {
      uri = Uri.parse("content://media/external/audio/media/${s.id}");
    } else {
      // Use Uri.file to handle Windows paths correctly
      uri = Uri.file(normalizedPath);
    }

    // Check if file exists for Windows
    if (!Platform.isAndroid) {
      if (!await File(normalizedPath).exists()) {
        debugPrint(
          "File not found: $normalizedPath${normalizedPath == rawData ? '' : ' (raw: $rawData)'}",
        );
        return null;
      }
    }

    // NOTE: On desktop we don't currently have a reliable, cheap way to
    // extract embedded artwork for every file, so leave artUri null.
    // (Previously this was set to the audio file path, which breaks any
    // ImageProvider-based artwork loading and prevents fallbacks.)
    final Uri? artUri =
        Platform.isAndroid
            ? Uri.parse("content://media/external/audio/media/${s.id}/albumart")
            : null;

    return AudioSource.uri(
      uri,
      tag: MediaItem(
        id: s.id.toString(),
        album: s.album ?? "Unknown Album",
        title: s.title,
        artist: s.artist ?? "Unknown Artist",
        duration: Duration(milliseconds: s.duration ?? 0),
        artUri: artUri,
        extras: {
          'path': normalizedPath,
          'songId': s.id,
          if (extraExtras != null) ...extraExtras,
        },
      ),
    );
  }

  Future<void> _loadBookmarks() async {
    final id = activeBookmarkId;
    debugPrint('[BOOKMARK DEBUG] _loadBookmarks: activeBookmarkId=$id');
    if (id == null || id.isEmpty) {
      debugPrint('[BOOKMARK DEBUG] _loadBookmarks: id is null or empty, clearing bookmarks');
      bookmarks.clear();
      _lastBookmarkLoadId = null;
      _syncBookmarks();
      return;
    }
    if (id == _lastBookmarkLoadId) {
      debugPrint('[BOOKMARK DEBUG] _loadBookmarks: already loaded bookmarks for id=$id');
      return;
    }
    _lastBookmarkLoadId = id;
    
    TelemetryService.instance.startTimer('bookmark_load');
    try {
      final prefs = await _sharedPreferences;
      final key = 'bookmarks_$id';
      final saved = prefs.getStringList(key) ?? [];
      debugPrint('[BOOKMARK DEBUG] _loadBookmarks: loading from key=$key, count=${saved.length}');
      bookmarks.clear();
      
      for (final s in saved) {
        try {
          // Try parsing as JSON (new format)
          final map = jsonDecode(s) as Map<String, dynamic>;
          
          // Validate bookmark structure
          if (!map.containsKey('pos') || map['pos'] is! int) {
            throw FormatException('Invalid bookmark: missing or invalid pos field');
          }
          
          bookmarks.add(map);
          debugPrint('[BOOKMARK DEBUG] _loadBookmarks: loaded bookmark pos=${map['pos']} note=${map['note']}');
        } catch (e) {
          // Fallback: old format (just milliseconds string)
          try {
            final ms = int.tryParse(s);
            if (ms != null && ms >= 0) {
              bookmarks.add({'pos': ms, 'note': ''});
              debugPrint('[BOOKMARK DEBUG] _loadBookmarks: loaded legacy bookmark pos=$ms');
            } else {
              debugPrint('[BOOKMARK DEBUG] _loadBookmarks: skipped invalid bookmark: $s');
            }
          } catch (e2) {
            debugPrint('[BOOKMARK DEBUG] _loadBookmarks: failed to parse bookmark: $e2');
          }
        }
      }
      
      _syncBookmarks();
      final loadTimeMs = TelemetryService.instance.stopTimer('bookmark_load');
      debugPrint('[BOOKMARK DEBUG] ✓ Loaded ${bookmarks.length} bookmarks in ${loadTimeMs}ms');
      AnalyticsService.logEvent('bookmark_load', {'count': bookmarks.length, 'time_ms': loadTimeMs ?? 0});
    } catch (e, st) {
      LoggerService.instance.warning('Error loading bookmarks', e, st);
      debugPrint('[BOOKMARK DEBUG] ❌ Error loading bookmarks: $e');
      TelemetryService.instance.stopTimer('bookmark_load');
      await AnalyticsService.instance.logException(e, st, context: {
        'operation': '_loadBookmarks',
        'activeBookmarkId': id,
      });
      bookmarks.clear();
      _syncBookmarks();
    }

  Future<void> _saveBookmarks() async {
    final id = activeBookmarkId;
    debugPrint('[BOOKMARK DEBUG] _saveBookmarks: activeBookmarkId=$id, bookmark count=${bookmarks.length}');
    if (id == null || id.isEmpty) {
      debugPrint('[BOOKMARK DEBUG] _saveBookmarks: id is null or empty, NOT saving');
      return;
    }
    _syncBookmarks();
    
    TelemetryService.instance.startTimer('bookmark_save');
    try {
      final prefs = await _sharedPreferences;
      final key = 'bookmarks_$id';
      final encoded = bookmarks.map((b) => jsonEncode(b)).toList();
      
      // Validate before saving
      if (encoded.isEmpty && bookmarks.isNotEmpty) {
        throw StateError('Bookmark encoding failed: empty encoded list but bookmarks exist');
      }
      
      await prefs.setStringList(key, encoded);
      final saveTimeMs = TelemetryService.instance.stopTimer('bookmark_save');
      debugPrint('[BOOKMARK DEBUG] ✓ Saved ${encoded.length} bookmarks in ${saveTimeMs}ms');
      AnalyticsService.logEvent('bookmark_save', {'count': encoded.length, 'time_ms': saveTimeMs ?? 0});
    } catch (e, st) {
      LoggerService.instance.warning('Error saving bookmarks', e, st);
      debugPrint('[BOOKMARK DEBUG] ❌ Error saving bookmarks: $e');
      TelemetryService.instance.stopTimer('bookmark_save');
      await AnalyticsService.instance.logException(e, st, context: {
        'operation': '_saveBookmarks',
        'activeBookmarkId': id,
        'bookmarkCount': bookmarks.length,
      });
    }
  }

  Future<void> addBookmark({String note = ''}) async {
    try {
      debugPrint('[BOOKMARK DEBUG] addBookmark: isReady=$isReady, currentMediaItem=${currentMediaItem?.id}');
      if (!isReady || currentMediaItem == null) {
        const msg = 'addBookmark rejected: not ready or no media item';
        debugPrint('[BOOKMARK DEBUG] $msg');
        await AnalyticsService.instance.logError(
          title: 'Bookmark Add Failed',
          message: msg,
          stackTrace: 'Not ready',
          context: {'isReady': isReady, 'hasMediaItem': currentMediaItem != null},
        );
        return;
      }
      final pos = player.position.inMilliseconds;
      debugPrint('[BOOKMARK DEBUG] addBookmark: adding at pos=$pos, note=$note');
      
      // Validate input
      if (pos < 0) {
        throw ArgumentError('Position cannot be negative: $pos');
      }
      
      bookmarks.add({'pos': pos, 'note': note});

      // Prevent unbounded bookmark growth which could cause native memory pressure.
      const maxBookmarks = 500;
      if (bookmarks.length > maxBookmarks) {
        final removeCount = bookmarks.length - maxBookmarks;
        bookmarks.removeRange(0, removeCount);
        debugPrint('[BOOKMARK DEBUG] addBookmark: trimmed $removeCount old bookmarks');
      }

      _syncBookmarks();
      await _saveBookmarks();
      debugPrint('[BOOKMARK DEBUG] ✓ Bookmark added successfully');
      AnalyticsService.logEvent('bookmark_add', {'pos': pos, 'note_length': note.length});
    } catch (e, st) {
      LoggerService.instance.warning('Error adding bookmark', e, st);
      debugPrint('[BOOKMARK DEBUG] ❌ Error adding bookmark: $e');
      await AnalyticsService.instance.logException(e, st, context: {
        'operation': 'addBookmark',
        'note_length': note.length,
      });
    }
  }

  Future<void> updateBookmarkNote(int index, String note) async {
    if (index < 0 || index >= bookmarks.length) return;
    bookmarks[index]['note'] = note;
    _syncBookmarks();
    await _saveBookmarks();
  }

  Future<void> removeBookmark(int i) async {
    if (i < 0 || i >= bookmarks.length) return;
    bookmarks.removeAt(i);
    _syncBookmarks();
    await _saveBookmarks();
  }

  Future<void> reloadBookmarks() async {
    await _loadBookmarks();
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
        for (final s in librarySongs) s.id.toString(): s,
      };
      final seedSong = songById[seedId];
      final seedArtist = seedSong?.artist?.trim().toLowerCase();

      final songRows = <Map<String, dynamic>>[];
      for (final song in librarySongs) {
        final id = song.id.toString();
        final meta = metaMap[id];
        songRows.add({
          'id': id,
          'artist': song.artist ?? '',
          'bpm': meta?.bpm,
          'key': meta?.key,
        });
      }

      final exclude = <String>{};
      final seq = player.sequenceState;
      for (final src in seq.sequence) {
        final tag = src.tag;
        if (tag is MediaItem) {
          final id = tag.extras?['songId']?.toString();
          if (id != null && id.isNotEmpty) exclude.add(id);
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
        final id = s.id.toString();
        final meta = metaMap[id];
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
      // ignore: deprecated_member_use
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
        final state = player.sequenceState;
        final seq = state.sequence;

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
        } catch (e, st) {
          _logAudioError('setAudioSources(neuralMixFallback)', e, st);
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
    // ignore: deprecated_member_use
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
      for (final src in seq.sequence) {
        final tag = src.tag;
        if (tag is MediaItem) {
          final id = tag.extras?['songId']?.toString();
          if (id != null && id.isNotEmpty) exclude.add(id);
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
      for (final s in librarySongs) s.id.toString(): s,
    };
    final seedArtist = songById[seedId]?.artist?.trim().toLowerCase();

    final songRows = <Map<String, dynamic>>[];
    for (final song in librarySongs) {
      final id = song.id.toString();
      final meta = metaMap[id];
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
      final id = s.id.toString();
      final meta = metaMap[id];
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
    // ignore: deprecated_member_use
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

  // External file playback (e.g., Android "Open with")
  Future<void> playExternalFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('External file not found: $filePath');
        return;
      }

      final uri = Uri.file(filePath);
      final source = AudioSource.uri(uri);

      try {
        await player.setAudioSources([source]);
      } catch (e, st) {
        _logAudioError(
          'setAudioSources(externalFile)',
          e,
          st,
          sources: [source],
        );
        return;
      }

      try {
        await player.play();
      } catch (e, st) {
        _logAudioError('play(externalFile)', e, st);
      }
    } catch (e, st) {
      _logAudioError('externalFile', e, st);
    }
  }

  void _logAudioError(
    String action,
    Object error,
    StackTrace st, {
    List<UriAudioSource>? sources,
  }) {
    _lastPlaybackError = error;
    _lastPlaybackErrorAt = DateTime.now();

    try {
      final item = currentMediaItem;
      final path = item?.extras?['path']?.toString();
      final ext =
          (path != null && path.contains('.'))
              ? path.substring(path.lastIndexOf('.')).toLowerCase()
              : null;

      String errLine = '$error';
      if (error is PlayerException) {
        errLine =
            'PlayerException(code=${error.code}, message=${error.message})';
      }

      debugPrint(
        'AUDIO_ERROR [$action] platform=${Platform.operatingSystem} playing=${player.playing} '
        'processing=${player.processingState} index=${player.currentIndex} path=${path ?? "<none>"} ext=${ext ?? "<none>"} error=$errLine',
      );

      if (sources != null && sources.isNotEmpty) {
        final previewCount = sources.length.clamp(0, 3);
        for (int i = 0; i < previewCount; i++) {
          final s = sources[i];
          debugPrint('AUDIO_ERROR [$action] source[$i]=${s.uri}');
        }
        if (sources.length > previewCount) {
          debugPrint(
            'AUDIO_ERROR [$action] (${sources.length - previewCount} more sources omitted)',
          );
        }
      }
    } catch (_) {
      // Ensure logging never crashes the app.
    }
    debugPrint('AUDIO_ERROR [$action] stack:\n$st');
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

  play() {}

  void stop() {}
}
