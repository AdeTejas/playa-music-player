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
import 'package:just_audio/just_audio.dart';
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
import 'services/analytics_service.dart';
import 'services/telemetry_service.dart';
import 'services/sonic_dna_scheduler.dart';
import 'services/neural_mix_index_service.dart';

// UI & Screens

import 'ui/deep_space_background.dart';
import 'ui/torch_engine_glow_overlay.dart';
import 'ui/now_playing_layout.dart';
import 'screens/library_page.dart';
import 'screens/player_screen.dart';
import 'screens/equalizer_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/playlists_screen.dart';
import 'screens/settings_screen.dart';

import 'design/design_system.dart';
import 'widgets/player_provider.dart';
import 'widgets/audiobook_controls.dart';
import 'widgets/artwork_image.dart';
import 'widgets/telemetry_lifecycle_observer.dart';

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
  // Local, on-device error logging always runs; remote crash reporting is
  // privacy-gated via TelemetryService.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FLUTTER ERROR: ${details.exception}');
    unawaited(AnalyticsService.instance.logFlutterError(details));
    unawaited(TelemetryService.instance.captureFlutterError(details));
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('PLATFORM ERROR: $error');
    unawaited(
      AnalyticsService.instance.logError(
        title: 'Platform error',
        message: error.toString(),
        stackTrace: stack.toString(),
      ),
    );
    unawaited(TelemetryService.instance.capturePlatformError(error, stack));
    return true;
  };

  // Initialize sqflite for desktop
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService.instance.init(); // Initialize Settings
  await TelemetryService.instance
      .init(); // Privacy-gated telemetry (reads consent)
  await DatabaseService.instance.init(); // Initialize Database
  await AnalyticsService.instance.init();

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

  // Auto-run Sonic DNA analysis when charging + idle (non-blocking).
  unawaited(SonicDnaScheduler.instance.start());

  // Warm the Neural Mix index after DNA scans and invalidate on library change.
  NeuralMixIndexService.instance.start();

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
    return TelemetryLifecycleObserver(
      child: AnimatedBuilder(
        animation: SettingsService.instance,
        builder: (context, _) {
          // Using new Design System (Phase 1)
          final resolvedAccent = SettingsService.instance.resolveAccentColor(
            SettingsService.instance.rawAccent,
          );

          final playaColors = PlayaColorsExtension(accent: resolvedAccent);

          final theme = AppTheme.dark.copyWith(
            colorScheme: playaColorScheme(resolvedAccent),
            extensions: <ThemeExtension<dynamic>>[playaColors],
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
            home:
                SettingsService.instance.onboardingComplete
                    ? const _Shell()
                    : const OnboardingScreen(),
          );
        },
      ),
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
        ServiceLocator.instance.playerController.playExternalFile(
          _pendingIntentData!,
        );
        _pendingIntentData = null; // Clear after handling
      }
      if (kAutoPlaybackTest) {
        // Run the automated playback scenario (non-blocking)
        Future.microtask(
          () => _runAutoPlaybackTest(ServiceLocator.instance.playerController),
        );
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
    final immersiveSpace =
        !settings.lowPerformanceMode && !settings.batterySaver;

    return PlayerProvider(
      ctrl: ctrl,
      child: PopScope(
        canPop: _tab == 0,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          setState(() => _tab = 0);
        },
        child: StreamBuilder<Object?>(
          stream: ctrl.player.sequenceStateStream,
          builder: (context, snapshot) {
            final item = ctrl.currentMediaItem;
            final bpm = (item?.extras?['bpm'] as num?)?.toDouble();

            return Stack(
              children: [
                // 1. Background Layer (Stars + Nebula)
                if (settings.effectiveShowSpaceBackground)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: DeepSpaceBackground(
                        subtle: !immersiveSpace,
                        hdrBoost: immersiveSpace,
                        hdrIntensity: _tab == 0 ? 1.0 : 0.75,
                        starDensity: _tab == 0 ? 0.96 : 0.62,
                        mode: DeepSpaceMode.background,
                        bpm: bpm,
                        accentColor: settings.accentFor(),
                      ),
                    ),
                  ),

                // 2. Overlay Layer (Comets) - Behind Content
                if (settings.effectiveShowSpaceBackground)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: DeepSpaceBackground(
                        subtle: !immersiveSpace,
                        hdrIntensity: _tab == 0 ? 1.0 : 0.75,
                        starDensity: _tab == 0 ? 0.96 : 0.62,
                        mode: DeepSpaceMode.overlay,
                        bpm: bpm,
                        accentColor: settings.accentFor(),
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
                      _tab == 1
                          ? PlayaAppBar(
                            title: 'Now Playing',
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
                                icon: const PhosphorIcon(
                                  PhosphorIconsBold.timer,
                                ),
                                onPressed:
                                    () => showSleepTimerSheet(context, ctrl),
                              ),
                              IconButton(
                                tooltip: 'Queue',
                                icon: const PhosphorIcon(
                                  PhosphorIconsBold.queue,
                                ),
                                onPressed: () => _showQueue(context, ctrl),
                              ),
                              IconButton(
                                tooltip: 'Settings',
                                icon: const PhosphorIcon(
                                  PhosphorIconsBold.gear,
                                ),
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const SettingsScreen(),
                                  ),
                                ),
                              ),
                            ],
                          )
                          : null,
                  body: LayoutBuilder(
                    builder: (context, constraints) {
                      final wideDesktop = constraints.maxWidth >=
                          NowPlayingLayoutMetrics.wideDesktopWidth;
                      final stack = IndexedStack(
                        index: _tab,
                        children: [
                          LibraryPage(isVisible: _tab == 0),
                          PlayerScreen(isVisible: _tab == 1),
                          PlaylistsScreen(isVisible: _tab == 2),
                        ],
                      );

                      void selectTab(int tab) {
                        if (_tab == tab) return;
                        HapticFeedback.mediumImpact();
                        if (tab != 1) {
                          FocusScope.of(context).unfocus();
                        }
                        setState(() => _tab = tab);
                      }

                      if (wideDesktop) {
                        // Side rail avoids bottom-nav + mini-player clipping at
                        // ~1280×720 Windows desktop windows.
                        return Row(
                          children: [
                            NavigationRail(
                              selectedIndex: _tab,
                              onDestinationSelected: selectTab,
                              labelType: NavigationRailLabelType.all,
                              backgroundColor: Colors.transparent,
                              destinations: const [
                                NavigationRailDestination(
                                  icon: Icon(
                                    PhosphorIconsRegular.musicNotesSimple,
                                  ),
                                  selectedIcon: Icon(
                                    PhosphorIconsFill.musicNotesSimple,
                                  ),
                                  label: Text('Library'),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(PhosphorIconsRegular.vinylRecord),
                                  selectedIcon: Icon(
                                    PhosphorIconsFill.vinylRecord,
                                  ),
                                  label: Text('Player'),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(PhosphorIconsRegular.playlist),
                                  selectedIcon: Icon(
                                    PhosphorIconsFill.playlist,
                                  ),
                                  label: Text('Playlists'),
                                ),
                              ],
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(child: stack),
                          ],
                        );
                      }

                      return stack;
                    },
                  ),
                  bottomNavigationBar: LayoutBuilder(
                    builder: (context, constraints) {
                      final wideDesktop = MediaQuery.sizeOf(context).width >=
                          NowPlayingLayoutMetrics.wideDesktopWidth;
                      if (wideDesktop) return const SizedBox.shrink();

                      final shortViewport = MediaQuery.sizeOf(context).height <
                          NowPlayingLayoutMetrics.shortViewportHeight;
                      final bottomPad = shortViewport
                          ? PlayaSpacing.kSp * 0.5
                          : PlayaSpacing.kSp;

                      return SafeArea(
                        top: false,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            PlayaSpacing.kSp * 2,
                            0,
                            PlayaSpacing.kSp * 2,
                            bottomPad,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_tab == 0)
                                _MiniPlayer(
                                  ctrl: ctrl,
                                  onOpen: () {
                                    HapticFeedback.selectionClick();
                                    setState(() => _tab = 1);
                                  },
                                ),
                              if (_tab == 0)
                                SizedBox(
                                  height: shortViewport
                                      ? PlayaSpacing.kSp * 0.5
                                      : PlayaSpacing.kSp,
                                ),
                              Container(
                                decoration: PlayaEffects.matteSurface(
                                  borderRadius: BorderRadius.circular(32),
                                  elevated: true,
                                ),
                                child: SizedBox(
                                  height: shortViewport ? 48 : 52,
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceEvenly,
                                    children: [
                                      _NavBarItem(
                                        icon: PhosphorIconsRegular
                                            .musicNotesSimple,
                                        selectedIcon: PhosphorIconsFill
                                            .musicNotesSimple,
                                        label: 'Library',
                                        selected: _tab == 0,
                                        onTap: () {
                                          if (_tab != 0) {
                                            HapticFeedback.mediumImpact();
                                            FocusScope.of(context).unfocus();
                                            setState(() => _tab = 0);
                                          }
                                        },
                                      ),
                                      _NavBarItem(
                                        icon: PhosphorIconsRegular.vinylRecord,
                                        selectedIcon:
                                            PhosphorIconsFill.vinylRecord,
                                        label: 'Player',
                                        selected: _tab == 1,
                                        onTap: () {
                                          if (_tab != 1) {
                                            HapticFeedback.mediumImpact();
                                            setState(() => _tab = 1);
                                          }
                                        },
                                      ),
                                      _NavBarItem(
                                        icon: PhosphorIconsRegular.playlist,
                                        selectedIcon:
                                            PhosphorIconsFill.playlist,
                                        label: 'Playlists',
                                        selected: _tab == 2,
                                        onTap: () {
                                          if (_tab != 2) {
                                            HapticFeedback.mediumImpact();
                                            FocusScope.of(context).unfocus();
                                            setState(() => _tab = 2);
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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
                                horizontal: PlayaSpacing.kSp * 2,
                                vertical: PlayaSpacing.kSp,
                              ),
                              child: GlassPanel(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: PlayaSpacing.xs,
                                  vertical: PlayaSpacing.xxs * 1.5,
                                ),
                                borderRadius: BorderRadius.circular(
                                  PlayaRadii.sm,
                                ),
                                borderColor: Colors.redAccent.withValues(
                                  alpha: 0.35,
                                ),
                                color: Colors.black.withValues(alpha: 0.35),
                                child: Row(
                                  children: [
                                    const Icon(
                                      PhosphorIconsRegular.warningCircle,
                                      color: Colors.redAccent,
                                      size: 18,
                                    ),
                                    const SizedBox(width: PlayaSpacing.xs),
                                    Expanded(
                                      child: Text(
                                        'Scan failed. ${scan.lastError}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: PlayaColors.onSurfaceVariant,
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
                                                        restorePlayerState:
                                                            false,
                                                        force: true,
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
                              horizontal: PlayaSpacing.kSp * 2,
                              vertical: PlayaSpacing.kSp,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                PlayaRadii.pill,
                              ),
                              child: LinearProgressIndicator(
                                value:
                                    scan.progress == 0 ? null : scan.progress,
                                backgroundColor: PlayaColors.trackMuted,
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
            );
          },
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

class _MiniPlayer extends StatelessWidget {
  final PlayerController ctrl;
  final VoidCallback onOpen;

  const _MiniPlayer({required this.ctrl, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return StreamBuilder<SequenceState?>(
      stream: ctrl.player.sequenceStateStream,
      builder: (context, snapshot) {
        final item = ctrl.currentMediaItem;
        if (item == null) return const SizedBox.shrink();

        final mediaId = item.extras?['mediaId'];

        return Container(
          height: 64,
          decoration: PlayaEffects.matteSurface(
            borderRadius: BorderRadius.circular(PlayaRadii.md),
            elevated: true,
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(PlayaRadii.md),
                  onTap: onOpen,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: PlayaSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: ArtworkImage(
                            id:
                                mediaId is int
                                    ? mediaId
                                    : (int.tryParse('$mediaId') ?? 0),
                            nullArtworkWidget: const Icon(
                              PhosphorIconsRegular.musicNote,
                              color: PlayaColors.onSurfaceVariant,
                            ),
                            artworkBorder: BorderRadius.circular(PlayaRadii.xs),
                            artworkFit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: PlayaSpacing.sm),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: PlayaColors.onSurface,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.artist ?? 'Unknown',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: PlayaColors.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              StreamBuilder<bool>(
                stream: ctrl.player.playingStream,
                initialData: ctrl.player.playing,
                builder: (context, snap) {
                  final playing = snap.data ?? false;
                  return IconButton(
                    tooltip: playing ? 'Pause' : 'Play',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    icon: Icon(
                      playing
                          ? PhosphorIconsFill.pause
                          : PhosphorIconsFill.play,
                      color: accent,
                      size: 26,
                    ),
                    onPressed:
                        !ctrl.isReady
                            ? null
                            : () {
                              HapticFeedback.selectionClick();
                              if (playing) {
                                ctrl.pause();
                              } else {
                                ctrl.play();
                              }
                            },
                  );
                },
              ),
              IconButton(
                tooltip: 'Next',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: const Icon(
                  PhosphorIconsBold.skipForward,
                  color: PlayaColors.onSurface,
                  size: 22,
                ),
                onPressed:
                    !ctrl.isReady
                        ? null
                        : () {
                          HapticFeedback.selectionClick();
                          ctrl.player.seekToNext();
                        },
              ),
            ],
          ),
        );
      },
    );
  }
}
