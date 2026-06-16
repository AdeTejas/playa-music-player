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

// Services
import 'services/intent_handler.dart';
import 'services/perf_metrics_service.dart';
import 'services/settings_service.dart';
import 'services/database_service.dart';
import 'services/service_locator.dart';
import 'services/player_controller.dart';
import 'services/library_scan_service.dart';

// UI & Screens
import 'ui/tokens.dart';
import 'ui/deep_space_background.dart';
import 'ui/torch_engine_glow_overlay.dart';
import 'screens/library_page.dart';
import 'screens/player_screen.dart';
import 'screens/equalizer_screen.dart';

import 'design/design_system.dart';
import 'widgets/player_provider.dart';
import 'widgets/audiobook_controls.dart';
import 'widgets/bookmarks_sheet.dart';

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

  // Fully initialize the player controller (audio session, stream
  // listeners, etc.) before the first frame so that bookmark operations
  // and playback commands are safe from the start.
  await PlayerController.ensureInitialized();

  runApp(const PlayaApp());
}

// Global variable to store pending intent data
String? _pendingIntentData;

// Function to handle incoming intents
void _handleIncomingIntent(String data) {
  // This will be handled by the PlayerController when the app is ready
  ServiceLocator.instance.playerController.playExternalFile(data);
}

class PlayaApp extends StatelessWidget {
  const PlayaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SettingsService.instance,
      builder: (context, _) {
        // Using new Design System (Phase 1)
        final resolvedAccent = SettingsService.instance.resolveAccentColor(
          SettingsService.instance.rawAccent,
        );

        final playaColors = PlayaColorsExtension(
          accent: resolvedAccent,
        );

        final theme = AppTheme.dark.copyWith(
          colorScheme: playaColorScheme(resolvedAccent),
          extensions: <ThemeExtension<dynamic>>[
            playaColors,
          ],
          textTheme: GoogleFonts.exo2TextTheme(
            AppTheme.dark.textTheme.apply(bodyColor: PlayaColors.onSurface),
          ),
          sliderTheme: AppTheme.dark.sliderTheme.copyWith(
            trackHeight: 3,
            inactiveTrackColor: Colors.white24,
            activeTrackColor: resolvedAccent,
            thumbColor: resolvedAccent,
            overlayShape: SliderComponentShape.noOverlay,
          ),
        );

        return MaterialApp(
          title: 'Playa',
          debugShowCheckedModeBanner: false,
          theme: theme,
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
        ServiceLocator.instance.playerController.playExternalFile(_pendingIntentData!);
        _pendingIntentData = null; // Clear after handling
      }
      if (kAutoPlaybackTest) {
        // Run the automated playback scenario (non-blocking)
        Future.microtask(() => _runAutoPlaybackTest(ServiceLocator.instance.playerController));
      }
    });
  }

  Future<void> _runAutoPlaybackTest(PlayerController ctrl) async {
    try {
      // Wait for library scan to populate (max ~20s)
      int waited = 0;
      while (ctrl.librarySongs.isEmpty && waited < 20000) {
        await Future.delayed(const Duration(milliseconds: 500));
        waited += 500;
      }

      if (ctrl.librarySongs.isEmpty) {
        return;
      }

      // Pick first two songs (if available)
      final songs = <dynamic>[];
      songs.add(ctrl.librarySongs[0]);
      if (ctrl.librarySongs.length > 1) songs.add(ctrl.librarySongs[1]);

      // Replace queue but don't auto-play yet
      await ctrl.replaceQueue(songs.cast(), autoPlay: false);

      // Give the platform a moment to register player and load sources
      await Future.delayed(const Duration(milliseconds: 1500));

      // Start playback (guard each call individually)
      try {
        await ctrl.player.play();
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 4));

      // Pause
      try {
        await ctrl.player.pause();
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 1));

      // Seek to 30s
      try {
        await ctrl.player.seek(const Duration(seconds: 30));
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 1));

      // Resume
      try {
        await ctrl.player.play();
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 3));

      // Next track (if available)
      if (ctrl.player.hasNext) {
        try {
          await ctrl.player.seekToNext();
          await Future.delayed(const Duration(seconds: 1));
          await ctrl.player.play();
        } catch (_) {}
        await Future.delayed(const Duration(seconds: 2));
      }

      // Change speed and volume
      try {
        await ctrl.player.setSpeed(1.25);
        await ctrl.setUserVolume(0.7);
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 2));

      // Stop
      try {
        await ctrl.player.stop();
      } catch (_) {}
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ServiceLocator.instance.playerController;
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
                    starDensity: _tab == 0 ? 0.80 : 0.49,
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
                    starDensity: _tab == 0 ? 0.80 : 0.49,
                    mode: DeepSpaceMode.overlay,
                  ),
                ),
              ),

            // 2b. Torch engine glow bleed (Now Playing only)
            if (settings.effectiveShowSpaceBackground && _tab != 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: TorchEngineGlowOverlay(ctrl: ctrl),
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
                            onPressed: () => showSleepTimerSheet(context, ctrl),
                          ),
                          IconButton(
                            tooltip: 'Queue',
                            icon: const PhosphorIcon(PhosphorIconsBold.queue),
                            onPressed: () => _showQueue(context, ctrl),
                          ),
                          IconButton(
                            tooltip: 'Bookmarks',
                            icon: const PhosphorIcon(
                              PhosphorIconsBold.bookmarkSimple,
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
                      kSp,
                    ),
                    child: GlassPanel(
                      borderRadius: BorderRadius.circular(32),
                      borderWidth: 1.5,
                      borderColor: PlayaColors.border,
                      backgroundColor: kColorGlassClear,
                      child: SizedBox(
                        height: 48,
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
                                      color: kColorOn2,
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
                            color: SettingsService.instance.accentFor(),
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

  void _showBookmarks(BuildContext context, PlayerController ctrl) async {
    if (!ctrl.isReady) return;
    await ctrl.reloadBookmarks();
    if (!context.mounted) return;
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
    final c = Theme.of(context).extension<PlayaColorsExtension>()!;
    final accent = c.accent;
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
                color: selected ? accent : c.onSurfaceVariant,
                size: 24,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                color: selected ? accent : c.onSurfaceVariant,
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