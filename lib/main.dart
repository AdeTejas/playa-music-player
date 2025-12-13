// lib/main.dart
// Playa - The Real Deal Edition
// ignore_for_file: prefer_const_declarations

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'services/intent_handler.dart';
import 'services/perf_metrics_service.dart';

import 'ui/tokens.dart';
import 'ui/glass_panel.dart';
import 'screens/equalizer_screen.dart';
import 'screens/library_page.dart';
import 'screens/player_screen.dart';
import 'services/library_scan_service.dart';
import 'services/settings_service.dart';
import 'services/database_service.dart';
import 'services/player_controller.dart';
import 'ui/deep_space_background.dart';
import 'widgets/player_provider.dart';

// Debug drawing for turntable painter (set with --dart-define=DEV_TT_GUIDES=true)
const bool kDevPaintTurntableGuides = bool.fromEnvironment(
  'DEV_TT_GUIDES',
  defaultValue: false,
);

// Automated playback test: enable with --dart-define=AUTO_PLAYBACK_TEST=true
const bool kAutoPlaybackTest = bool.fromEnvironment(
  'AUTO_PLAYBACK_TEST',
  defaultValue: false,
);

/* ========================= THEME & TOKENS ========================= */

const _bg = Color(0xFF06070A);
const _surface = Color(0xFF14161B);
const _card = Color(0xFF1B1F26);
const _on = Color(0xFFE8DCCA); // Light Wood/Beige for text
const _on2 = Color(0xFFA68B6C); // Muted Wood for secondary text

Future<void> main([List<String> args = const []]) async {
  PerfMetricsService.instance.markAppStart();

  // Global Error Handling
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FLUTTER ERROR: ${details.exception}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('PLATFORM ERROR: $error');
    return true;
  };

  // Initialize sqflite for desktop
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService.instance.init(); // Initialize Settings
  await DatabaseService.instance.init(); // Initialize Database

  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    try {
      await JustAudioBackground.init(
        androidNotificationChannelId: 'com.playa.channel.audio',
        androidNotificationChannelName: 'Playa Playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        androidNotificationIcon: 'mipmap/launcher_icon',
        fastForwardInterval: const Duration(seconds: 10),
        rewindInterval: const Duration(seconds: 10),
      );
    } catch (e) {
      debugPrint('ERROR: JustAudioBackground.init failed: $e');
    }
  }

  // Handle incoming intents (for opening audio files from external apps)
  if (Platform.isAndroid) {
    try {
      IntentHandler.setupIntentHandling();

      final receivedData = await IntentHandler.getInitialIntent();
      if (receivedData != null) {
        _pendingIntentData = receivedData;
      }

      // Listen for new intents while app is running
      IntentHandler.receivedIntentStream.listen((String? data) {
        if (data != null) _handleIncomingIntent(data);
      });
    } catch (e) {
      debugPrint('ERROR: Intent handling setup failed: $e');
    }
  }

  // Handle desktop "open with" / file association launch arguments.
  if ((Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
      args.isNotEmpty) {
    try {
      for (final a in args) {
        final v = a.trim();
        if (v.isEmpty) continue;
        if (v.startsWith('-')) continue;

        String? path;
        if (v.startsWith('file://')) {
          try {
            path = Uri.parse(v).toFilePath();
          } catch (_) {
            path = null;
          }
        } else {
          path = v;
        }

        if (path != null && File(path).existsSync()) {
          _pendingIntentData = path;
          break;
        }
      }
    } catch (e) {
      debugPrint('ERROR: Desktop launch args handling failed: $e');
    }
  }

  runApp(const PlayaApp());
}

// Global variable to store pending intent data
String? _pendingIntentData;

// Function to handle incoming intents
void _handleIncomingIntent(String data) {
  // This will be handled by the PlayerController when the app is ready
  PlayerController.ensure().playExternalFile(data);
}

class PlayaApp extends StatelessWidget {
  const PlayaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SettingsService.instance,
      builder: (context, _) {
        final base = ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: _bg,
          splashFactory: InkSparkle.splashFactory,
          visualDensity: VisualDensity.standard,
        );

        return MaterialApp(
          title: 'Playa',
          debugShowCheckedModeBanner: false,
          theme: base.copyWith(
            colorScheme: ColorScheme.dark(
              surface: _surface,
              primary: Color(SettingsService.instance.accentColor),
              onSurface: _on,
            ),
            textTheme: GoogleFonts.exo2TextTheme(
              base.textTheme.apply(bodyColor: _on, displayColor: _on),
            ),
            iconTheme: const IconThemeData(color: _on),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              foregroundColor: _on,
              elevation: 0,
              centerTitle: true,
              titleTextStyle: TextStyle(
                color: _on,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            cardTheme: CardThemeData(
              color: _card.withValues(alpha: 0.94),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(kRadius),
              ),
              elevation: 0,
              margin: const EdgeInsets.all(kSp),
            ),
            listTileTheme: ListTileThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(kRadius),
              ),
              tileColor: _card.withValues(
                alpha: 0.4,
              ), // More transparent for glass effect
              iconColor: _on,
              textColor: _on,
              dense: true,
              visualDensity: VisualDensity.compact,
            ),
            bottomSheetTheme: const BottomSheetThemeData(
              backgroundColor: _surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
            ),
            sliderTheme: base.sliderTheme.copyWith(
              trackHeight: 3,
              inactiveTrackColor: Colors.white24,
              activeTrackColor: Color(SettingsService.instance.accentColor),
              thumbColor: Color(SettingsService.instance.accentColor),
              overlayShape: SliderComponentShape.noOverlay,
            ),
          ),
          home: const _Shell(),
        );
      },
    );
  }
}

/* ========================= SHELL ========================= */

class _Shell extends StatefulWidget {
  const _Shell();
  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PerfMetricsService.instance.markFirstFrame();
    });

    // Handle any pending intent data from app launch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pendingIntentData != null && _pendingIntentData!.trim().isNotEmpty) {
        debugPrint('Handling pending intent data: $_pendingIntentData');
        PlayerController.ensure().playExternalFile(_pendingIntentData!);
        _pendingIntentData = null; // Clear after handling
      }
      if (kAutoPlaybackTest) {
        // Run the automated playback scenario (non-blocking)
        Future.microtask(() => _runAutoPlaybackTest(PlayerController.ensure()));
      }
    });
  }

  Future<void> _runAutoPlaybackTest(PlayerController ctrl) async {
    try {
      debugPrint('AUTO_PLAYBACK_TEST: starting sequence');

      // Wait for library scan to populate (max ~20s)
      int waited = 0;
      while (ctrl.librarySongs.isEmpty && waited < 20000) {
        await Future.delayed(const Duration(milliseconds: 500));
        waited += 500;
      }

      if (ctrl.librarySongs.isEmpty) {
        debugPrint('AUTO_PLAYBACK_TEST: no songs found in library, aborting');
        return;
      }

      // Pick first two songs (if available)
      final songs = <dynamic>[];
      songs.add(ctrl.librarySongs[0]);
      if (ctrl.librarySongs.length > 1) songs.add(ctrl.librarySongs[1]);

      // Replace queue but don't auto-play yet
      await ctrl.replaceQueue(songs.cast(), autoPlay: false);
      debugPrint(
        'AUTO_PLAYBACK_TEST: queue replaced with ${songs.length} tracks',
      );

      // Give the platform a moment to register player and load sources
      // Increased delay to reduce race with plugin dispose/recreate.
      await Future.delayed(const Duration(milliseconds: 1500));

      // Start playback (guard each call individually)
      try {
        await ctrl.player.play();
        debugPrint('AUTO_PLAYBACK_TEST: play()');
      } catch (e) {
        debugPrint('AUTO_PLAYBACK_TEST: play() error: $e');
      }
      await Future.delayed(const Duration(seconds: 4));

      // Pause
      try {
        await ctrl.player.pause();
        debugPrint('AUTO_PLAYBACK_TEST: pause()');
      } catch (e) {
        debugPrint('AUTO_PLAYBACK_TEST: pause() error: $e');
      }
      await Future.delayed(const Duration(seconds: 1));

      // Seek to 30s
      try {
        await ctrl.player.seek(const Duration(seconds: 30));
        debugPrint('AUTO_PLAYBACK_TEST: seek(30s)');
      } catch (e) {
        debugPrint('AUTO_PLAYBACK_TEST: seek(30s) error: $e');
      }
      await Future.delayed(const Duration(seconds: 1));

      // Resume
      try {
        await ctrl.player.play();
        debugPrint('AUTO_PLAYBACK_TEST: resume play()');
      } catch (e) {
        debugPrint('AUTO_PLAYBACK_TEST: resume play() error: $e');
      }
      await Future.delayed(const Duration(seconds: 3));

      // Next track (if available)
      if (ctrl.player.hasNext) {
        try {
          await ctrl.player.seekToNext();
          await Future.delayed(const Duration(seconds: 1));
          await ctrl.player.play();
          debugPrint('AUTO_PLAYBACK_TEST: next + play');
        } catch (e) {
          debugPrint('AUTO_PLAYBACK_TEST: next/play error: $e');
        }
        await Future.delayed(const Duration(seconds: 2));
      }

      // Change speed and volume
      try {
        await ctrl.player.setSpeed(1.25);
        await ctrl.setUserVolume(0.7);
        debugPrint('AUTO_PLAYBACK_TEST: setSpeed(1.25) setVolume(0.7)');
      } catch (e) {
        debugPrint('AUTO_PLAYBACK_TEST: setSpeed/setVolume error: $e');
      }
      await Future.delayed(const Duration(seconds: 2));

      // Stop
      try {
        await ctrl.player.stop();
        debugPrint('AUTO_PLAYBACK_TEST: stop() done');
      } catch (e) {
        debugPrint('AUTO_PLAYBACK_TEST: stop() error: $e');
      }
    } catch (e, st) {
      debugPrint('AUTO_PLAYBACK_TEST: error $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = PlayerController.ensure();
    final settings = SettingsService.instance;
    final scan = LibraryScanService.instance;

    return PlayerProvider(
      ctrl: ctrl,
      child: PopScope(
        canPop: _tab == 0,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          setState(() => _tab = 0);
        },
        child: Stack(
          children: [
            // 1. Background Layer (Stars + Nebula)
            if (settings.effectiveShowSpaceBackground)
              Positioned.fill(
                child: RepaintBoundary(
                  child: DeepSpaceBackground(
                    subtle: _tab == 0,
                    mode: DeepSpaceMode.background,
                  ),
                ),
              ),

            // 2. Overlay Layer (Comets) - Behind Content
            if (settings.effectiveShowSpaceBackground)
              Positioned.fill(
                child: RepaintBoundary(
                  child: DeepSpaceBackground(
                    subtle: _tab == 0,
                    mode: DeepSpaceMode.overlay,
                  ),
                ),
              ),

            // 3. Content (Scaffold)
            Scaffold(
              backgroundColor: Colors.transparent,
              appBar:
                  _tab == 0
                      ? null
                      : AppBar(
                        title: const Text('Now Playing'),
                        actions: [
                          if (Platform.isAndroid)
                            IconButton(
                              tooltip: 'Equalizer',
                              icon: const PhosphorIcon(
                                PhosphorIconsBold.sliders,
                              ),
                              onPressed:
                                  () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder:
                                          (_) => EqualizerScreen(
                                            sessionId:
                                                ctrl
                                                    .player
                                                    .androidAudioSessionId ??
                                                0,
                                          ),
                                    ),
                                  ),
                            ),
                          IconButton(
                            tooltip: 'Sleep Timer',
                            icon: const PhosphorIcon(PhosphorIconsBold.timer),
                            onPressed: () => _showSleepTimer(context, ctrl),
                          ),
                          IconButton(
                            tooltip: 'Queue',
                            icon: const PhosphorIcon(PhosphorIconsBold.queue),
                            onPressed: () => _showQueue(context, ctrl),
                          ),
                          IconButton(
                            tooltip: 'Chapters',
                            icon: const PhosphorIcon(
                              PhosphorIconsBold.bookmarksSimple,
                            ),
                            onPressed: () => _showBookmarks(context, ctrl),
                          ),
                        ],
                      ),
              body: IndexedStack(
                index: _tab,
                children: [
                  const LibraryPage(),
                  PlayerScreen(isVisible: _tab == 1),
                ],
              ),
              bottomNavigationBar: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    kSp * 2,
                    0,
                    kSp * 2,
                    kSp * 1.5,
                  ),
                  child: GlassPanel(
                    borderRadius: BorderRadius.circular(32),
                    borderWidth: 1.5,
                    borderColor: Colors.white.withValues(alpha: 0.15),
                    backgroundColor: kColorGlassClear,
                    child: SizedBox(
                      height: 64,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _NavBarItem(
                            icon: PhosphorIconsRegular.musicNotesSimple,
                            selectedIcon: PhosphorIconsFill.musicNotesSimple,
                            label: 'Library',
                            selected: _tab == 0,
                            onTap: () {
                              FocusScope.of(context).unfocus();
                              setState(() => _tab = 0);
                            },
                          ),
                          _NavBarItem(
                            icon: PhosphorIconsRegular.vinylRecord,
                            selectedIcon: PhosphorIconsFill.vinylRecord,
                            label: 'Player',
                            selected: _tab == 1,
                            onTap: () {
                              FocusScope.of(context).unfocus();
                              setState(() => _tab = 1);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 4. Global scan indicator (visible outside Library tab)
            if (_tab != 0)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: AnimatedBuilder(
                    animation: scan,
                    builder: (context, _) {
                      if (scan.phase == LibraryScanPhase.error &&
                          scan.lastError != null) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: kSp * 2,
                            vertical: kSp,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: kSp,
                              vertical: kSp * 0.75,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(kRadius),
                              border: Border.all(
                                color: Colors.redAccent.withValues(alpha: 0.35),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  color: Colors.redAccent,
                                  size: 18,
                                ),
                                const SizedBox(width: kSp),
                                Expanded(
                                  child: Text(
                                    'Scan failed. ${scan.lastError}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: _on2,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed:
                                      scan.isScanning
                                          ? null
                                          : () {
                                            // Avoid disrupting playback while user is on Player tab.
                                            unawaited(
                                              LibraryScanService.instance
                                                  .scanLibrary(
                                                    restorePlayerState: false,
                                                  ),
                                            );
                                          },
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      if (!scan.isScanning) return const SizedBox.shrink();
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: kSp * 2,
                          vertical: kSp,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: scan.progress == 0 ? null : scan.progress,
                            backgroundColor: Colors.white10,
                            color: Color(SettingsService.instance.accentColor),
                            minHeight: 6,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showSleepTimer(BuildContext context, PlayerController ctrl) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        int fadeSeconds = SettingsService.instance.sleepFadeSeconds;
        return StatefulBuilder(
          builder: (ctx, setState) {
            final fade = Duration(seconds: fadeSeconds);
            return Container(
              padding: const EdgeInsets.all(kSp * 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Sleep Timer',
                    style: TextStyle(
                      fontSize: kTextLg,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: kSp),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Fade out',
                          style: TextStyle(color: kColorOn2, fontSize: kTextSm),
                        ),
                      ),
                      DropdownButton<int>(
                        value: fadeSeconds,
                        dropdownColor: kColorSurface,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Off')),
                          DropdownMenuItem(value: 5, child: Text('5s')),
                          DropdownMenuItem(value: 10, child: Text('10s')),
                          DropdownMenuItem(value: 20, child: Text('20s')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => fadeSeconds = v);
                          // Persist as the default for next time.
                          SettingsService.instance.setSleepFadeSeconds(v);
                        },
                      ),
                      const SizedBox(width: kSp),
                      TextButton(
                        onPressed:
                            fadeSeconds == 0
                                ? null
                                : () async {
                                  await ctrl.previewFadeToSilence(fade);
                                },
                        child: const Text('Preview'),
                      ),
                    ],
                  ),
                  const SizedBox(height: kSp),
                  ListTile(
                    leading: const Icon(PhosphorIconsRegular.timer),
                    title: const Text('15 Minutes'),
                    onTap: () {
                      ctrl.setSleepTimer(15, fadeOut: fade);
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Sleep timer set for 15 minutes'),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(PhosphorIconsRegular.timer),
                    title: const Text('30 Minutes'),
                    onTap: () {
                      ctrl.setSleepTimer(30, fadeOut: fade);
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Sleep timer set for 30 minutes'),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(PhosphorIconsRegular.timer),
                    title: const Text('60 Minutes'),
                    onTap: () {
                      ctrl.setSleepTimer(60, fadeOut: fade);
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Sleep timer set for 60 minutes'),
                        ),
                      );
                    },
                  ),
                  const Divider(color: Colors.white10),
                  ListTile(
                    leading: const Icon(PhosphorIconsRegular.musicNotes),
                    title: const Text('End of Track'),
                    subtitle: const Text(
                      'Stop after the current track finishes',
                    ),
                    onTap: () {
                      ctrl.setSleepTimerEndOfTrack(fadeOut: fade);
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Sleep timer set: end of track'),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(PhosphorIconsRegular.disc),
                    title: const Text('End of Album'),
                    subtitle: const Text('Stop after the current album ends'),
                    onTap: () {
                      ctrl.setSleepTimerEndOfAlbum(fadeOut: fade);
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Sleep timer set: end of album'),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(PhosphorIconsRegular.playlist),
                    title: const Text('End of Playlist'),
                    subtitle: const Text(
                      'Stop after the current playlist ends',
                    ),
                    onTap: () {
                      ctrl.setSleepTimerEndOfPlaylist(fadeOut: fade);
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Sleep timer set: end of playlist'),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(PhosphorIconsRegular.queue),
                    title: const Text('End of Queue'),
                    subtitle: const Text('Stop when the queue finishes'),
                    onTap: () {
                      ctrl.setSleepTimerEndOfQueue(fadeOut: fade);
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Sleep timer set: end of queue'),
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(PhosphorIconsRegular.xCircle),
                    title: const Text('Turn Off Timer'),
                    onTap: () {
                      ctrl.cancelSleepTimer();
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Sleep timer turned off')),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showQueue(BuildContext context, PlayerController ctrl) {
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (_) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.75,
            minChildSize: 0.45,
            maxChildSize: 0.95,
            builder:
                (_, controller) =>
                    QueueSheet(ctrl: ctrl, scrollController: controller),
          ),
    ).whenComplete(() {
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  void _showBookmarks(BuildContext context, PlayerController ctrl) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.transparent,
      builder: (_) => BookmarksSheet(ctrl: ctrl),
    );
  }
}

class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;
    return GestureDetector(
      onTap: () {
        onTap();
        HapticFeedback.selectionClick();
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 80,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder:
                  (child, anim) => ScaleTransition(scale: anim, child: child),
              child: Icon(
                selected ? selectedIcon : icon,
                key: ValueKey(selected),
                color: selected ? Color(settings.accentColor) : _on2,
                size: 24,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                color: selected ? Color(settings.accentColor) : _on2,
                fontSize: 10,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
