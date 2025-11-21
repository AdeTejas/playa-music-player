import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:on_audio_query/on_audio_query.dart' as oaq;
import 'package:shared_preferences/shared_preferences.dart';

import '../repositories/song_repository.dart';
import 'equalizer_service.dart';
import 'settings_service.dart';

class PlayerController {
  PlayerController._();
  static PlayerController? _i;
  static PlayerController ensure() =>
      _i ??= PlayerController._().._init();

  int _lastSessionId = 0;

  Timer? _sleepTimer;
  
  void setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    if (minutes <= 0) return;
    
    _sleepTimer = Timer(Duration(minutes: minutes), () {
      player.pause();
      _sleepTimer = null;
    });
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

  // Library Cache for Quick Access
  List<oaq.SongModel> librarySongs = [];

  void updateLibrary(List<oaq.SongModel> songs) {
    librarySongs = List.from(songs);
  }

  Future<void> addToQueue(oaq.SongModel song) async {
    final source = await _buildSource(song);
    if (source == null) return;
    
    final audioSource = player.audioSource;
    // ignore: deprecated_member_use
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
    // Alias for insertNext to avoid confusion, or we can deprecate this.
    // For now, let's redirect to insertNext which handles the logic.
    await insertNext(song);
  }

  final bookmarks = <Map<String, dynamic>>[];
  String currentId = '';

  bool get hasQueue => (player.sequenceState.sequence.isNotEmpty);
  bool get isReady => hasQueue;

  MediaItem? get currentMediaItem {
    final seq = player.sequenceState;
    if (seq.sequence.isEmpty) return null;
    final i = player.currentIndex ?? 0;
    final clamped = i.clamp(0, seq.sequence.length - 1);
    final src = seq.sequence[clamped];
    final tag = src.tag;
    return tag is MediaItem ? tag : null;
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
              player.setVolume(0.3);
            }
            break;
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            break;
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            player.setVolume(1.0);
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
      }
    });

    player.currentIndexStream.listen((_) async {
      final tag = currentMediaItem;
      if (tag == null) return;
      currentId = tag.id;

      // Update Last Played
      final songId = tag.extras?['songId']?.toString();
      if (songId != null) {
        SongRepository.instance.updateLastPlayed(songId).catchError((_) {});
      }

      await _loadBookmarks();
      _saveState();
    });

    player.playerStateStream.listen((state) {
      if (!state.playing) {
        _saveState();
      }
    });

    await player.setSkipSilenceEnabled(true);
    await player.setLoopMode(LoopMode.off); // Ensure stop at end
    debugPrint("PlayerController: player configured");

    try {
      final sid = player.androidAudioSessionId ?? 0;
      if (sid != 0) {
        _lastSessionId = sid;
        await EqualizerService.initializeEqualizer(sid);
      }
    } catch (_) {}

    player.playbackEventStream.listen((_) {
      try {
        final cur = player.androidAudioSessionId ?? 0;
        if (cur != 0 && cur != _lastSessionId) {
          _lastSessionId = cur;
          EqualizerService.initializeEqualizer(cur)
              .catchError((_) {});
        }
      } catch (_) {}
    }, onError: (Object e, StackTrace st) {
      debugPrint('Playback error: $e');
      // Attempt to skip to next track on error
      if (player.hasNext) {
        debugPrint('Skipping to next track due to error...');
        player.seekToNext();
        player.play();
      }
    });
  }

  Future<void> _saveState() async {
    final tag = currentMediaItem;
    if (tag == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (tag.extras != null && tag.extras!.containsKey('songId')) {
       await prefs.setInt('last_song_original_id', tag.extras!['songId'] as int);
    }
    await prefs.setInt('last_position_ms', player.position.inMilliseconds);
  }

  Future<void> restoreState(List<oaq.SongModel> allSongs) async {
    if (hasQueue) return; // Don't restore if already playing (e.g. hot reload)
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

  Future<void> replaceQueue(List<oaq.SongModel> songs, {int initialIndex = 0, bool autoPlay = true}) async {
    _sources.clear();
    
    // Parallel processing for speed
    final sources = await Future.wait(songs.map((s) => _buildSource(s)));
    
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
    
    if (adjustedIndex >= _sources.length) adjustedIndex = max(0, _sources.length - 1);

    if (_sources.isEmpty) return;

    try {
      await player.setAudioSources(
        _sources,
        initialIndex: adjustedIndex,
        initialPosition: Duration.zero,
        preload: false,
      );
      if (autoPlay) {
        await player.play();
      }
    } catch (e) {
      debugPrint("Error setting audio source: $e");
    }
  }

  Future<void> insertNext(oaq.SongModel song) async {
    if (!hasQueue) {
      await replaceQueue([song]);
      return;
    }
    
    final source = await _buildSource(song);
    if (source == null) return;

    final audioSource = player.audioSource;
    // ignore: deprecated_member_use
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

  Future<void> playAt(int index) async {
    if (!isReady) return;
    await player.seek(Duration.zero, index: index);
    await player.play();
  }

  Future<UriAudioSource?> _buildSource(oaq.SongModel s) async {
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
      artUri = Uri.parse("content://media/external/audio/media/${s.id}/albumart");
    } else {
      // Use Uri.file for artwork path too
      artUri = Uri.file(s.data);
    }
    
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
          'path': s.data,
          'songId': s.id,
        },
      ),
    );
  }

  Future<void> _loadBookmarks() async {
    if (currentId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('bookmarks_$currentId') ?? [];
    bookmarks.clear();
    for (final s in saved) {
      try {
        // Try parsing as JSON (new format)
        final map = jsonDecode(s) as Map<String, dynamic>;
        bookmarks.add(map);
      } catch (_) {
        // Fallback: old format (just milliseconds string)
        final ms = int.tryParse(s);
        if (ms != null) {
          bookmarks.add({'pos': ms, 'note': ''});
        }
      }
    }
  }

  Future<void> _saveBookmarks() async {
    if (currentId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'bookmarks_$currentId',
      bookmarks.map((b) => jsonEncode(b)).toList(),
    );
  }

  void addBookmark({String note = ''}) {
    if (!isReady) return;
    bookmarks.add({
      'pos': player.position.inMilliseconds,
      'note': note,
    });
    _saveBookmarks();
  }

  void updateBookmarkNote(int index, String note) {
    if (index < 0 || index >= bookmarks.length) return;
    bookmarks[index]['note'] = note;
    _saveBookmarks();
  }

  void removeBookmark(int i) {
    if (i < 0 || i >= bookmarks.length) return;
    bookmarks.removeAt(i);
    _saveBookmarks();
  }

  Future<void> jumpTo(int ms) async {
    if (!isReady) return;
    await player.seek(Duration(milliseconds: ms));
  }

  Future<void> smartShuffle() async {
    if (!isReady) return;
    
    final seedItem = currentMediaItem;
    if (seedItem == null) return;
    
    final seedId = seedItem.extras?['songId']?.toString();
    if (seedId == null) return;

    final repo = SongRepository.instance;
    final seedMeta = await repo.getMetadata(seedId);
    
    // Ensure library is populated
    if (librarySongs.isEmpty) {
      try {
        librarySongs = await oaq.OnAudioQuery().querySongs(
          sortType: oaq.SongSortType.DATE_ADDED,
          orderType: oaq.OrderType.DESC_OR_GREATER,
          uriType: oaq.UriType.EXTERNAL,
        );
      } catch (e) {
        debugPrint("Error fetching library for Smart Shuffle: $e");
      }
    }

    // If no DNA, we can't do smart matching, but we should still generate a mix (random)
    if (seedMeta?.bpm == null) {
      debugPrint("Neural Mix: No DNA found for seed song. Generating random mix.");
      // Fall through to fallback logic
    }

    final seedBpm = seedMeta?.bpm;
    final seedKey = seedMeta?.key;

    // Get all metadata for library
    // We need to map librarySongs to their metadata
    // For performance, we'll just fetch what we need or iterate
    // Ideally: DatabaseService should support bulk fetch or we rely on what we have.
    // Let's iterate librarySongs and fetch metadata (slow? maybe, but we have cache in DB)
    
    // Better: Get ALL metadata map from DB
    final allMeta = await repo.getAllMetadata();
    final metaMap = {for (var m in allMeta) m.id: m};

    final scored = <oaq.SongModel, double>{};

    if (seedBpm != null) {
      for (final song in librarySongs) {
        if (song.id.toString() == seedId) continue; // Skip current

        final meta = metaMap[song.id.toString()];
        double score = 0;

        if (meta?.bpm != null) {
          final diff = (seedBpm - meta!.bpm!).abs();
          if (diff < 5) {
            score += 100;
          } else if (diff < 10) {
            score += 70;
          } else if (diff < 20) {
            score += 40;
          } else {
            score -= diff; // Penalize large gaps
          }
        }

        if (meta?.key != null && seedKey != null) {
          if (meta!.key == seedKey) score += 50;
          // Simple harmonic check (same mode, different root? complex to parse string)
          // For demo, exact key match is a strong boost
        }
        
        // Add a little randomness so it's not identical every time
        score += Random().nextDouble() * 20;
        
        scored[song] = score;
      }
    }

    // Sort by score descending
    final sortedSongs = scored.keys.toList()
      ..sort((a, b) => scored[b]!.compareTo(scored[a]!));

    // Take top 50 for the mix
    var mix = sortedSongs.take(50).toList();
    
    if (mix.isEmpty) {
      debugPrint("Neural Mix: No matches found (or no DNA). Falling back to random selection.");
      if (librarySongs.isNotEmpty) {
         // Filter out current song from random mix
         final candidates = librarySongs.where((s) => s.id.toString() != seedId).toList();
         final randomList = List<oaq.SongModel>.from(candidates)..shuffle();
         mix = randomList.take(50).toList();
      }
    }

    if (mix.isEmpty) {
       debugPrint("Neural Mix: Library is empty. Cannot generate mix.");
       return;
    }

    // Replace queue (keep current playing)
    // We want to play the mix AFTER the current song
    
    // 1. Build sources for the mix
    final mixSources = <UriAudioSource>[];
    for (final s in mix) {
      final source = await _buildSource(s);
      if (source != null) mixSources.add(source);
    }

    debugPrint("Neural Mix: Generated ${mixSources.length} tracks.");

    // 2. Get current source
    // sequenceState is nullable in just_audio, but linter might be confused or we have a version mismatch.
    // Safest is to check for null explicitly if needed, or trust linter.
    // If linter says it's not null, then it's not null.
    // But wait, if I remove ?., and it IS null at runtime, it will crash.
    // 2. Get current source
    final state = player.sequenceState;
    final seq = state.sequence;
    
    if (seq.isEmpty) {
       _sources
        ..clear()
        ..addAll(mixSources);
    } else {
      final currentIndex = player.currentIndex ?? 0;
      if (currentIndex < seq.length) {
         final currentSource = seq[currentIndex];
         _sources.clear();
         if (currentSource is UriAudioSource) {
            _sources.add(currentSource);
         }
         _sources.addAll(mixSources);
      } else {
         _sources
          ..clear()
          ..addAll(mixSources);
      }
    }
      
    try {
      await player.setAudioSources(
        _sources,
        initialIndex: 0,
        initialPosition: player.position,
      );
    } catch (e) {
      debugPrint("Neural Mix Error: $e");
    }
    await player.play();
    
    await player.setShuffleModeEnabled(false);
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
