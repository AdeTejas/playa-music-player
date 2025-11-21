// lib/main.dart
// Playa - The Real Deal Edition
// ignore_for_file: prefer_const_declarations

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'ui/tokens.dart';
import 'ui/frosted_glass_shader.dart';
import 'screens/equalizer_screen.dart';
import 'screens/library_page.dart';
import 'screens/player_screen.dart';
import 'services/settings_service.dart';
import 'services/database_service.dart';
import 'services/player_controller.dart';
import 'ui/deep_space_background.dart';
import 'widgets/player_provider.dart';

// Debug drawing for turntable painter (set with --dart-define=DEV_TT_GUIDES=true)
const bool kDevPaintTurntableGuides =
  bool.fromEnvironment('DEV_TT_GUIDES', defaultValue: false);

/* ========================= THEME & TOKENS ========================= */

const _bg = Color(0xFF06070A);
const _surface = Color(0xFF14161B);
const _card = Color(0xFF1B1F26);
const _on = Color(0xFFE8DCCA); // Light Wood/Beige for text
const _on2 = Color(0xFFA68B6C); // Muted Wood for secondary text

Future<void> main() async {
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
  runApp(const PlayaApp());
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
            textTheme: GoogleFonts.exo2TextTheme(base.textTheme.apply(
              bodyColor: _on,
              displayColor: _on,
            )),
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
            cardTheme: CardTheme(
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
              tileColor: _card.withValues(alpha: 0.92),
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
    // Equalizer debug removed as per request
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = PlayerController.ensure();
    final settings = SettingsService.instance;

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
            if (settings.showSpaceBackground && !settings.batterySaver)
              Positioned.fill(
                child: RepaintBoundary(
                  child: DeepSpaceBackground(
                    subtle: _tab == 0,
                    mode: DeepSpaceMode.background,
                  ),
                ),
              ),

            // 2. Overlay Layer (Comets) - Behind Content
            if (settings.showSpaceBackground && !settings.batterySaver)
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
            appBar: _tab == 0
                ? null
                : AppBar(
                    title: const Text('Now Playing'),
                    actions: [
                      if (Platform.isAndroid)
                        IconButton(
                          tooltip: 'Equalizer',
                          icon: const PhosphorIcon(PhosphorIconsBold.sliders),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EqualizerScreen(
                                sessionId:
                                    ctrl.player.androidAudioSessionId ?? 0,
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
                child: FrostedGlassShader(
                  borderRadius: BorderRadius.circular(32),
                  child: Container(
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _NavBarItem(
                          icon: PhosphorIconsRegular.musicNotesSimple,
                          selectedIcon: PhosphorIconsFill.musicNotesSimple,
                          label: 'Library',
                          selected: _tab == 0,
                          onTap: () => setState(() => _tab = 0),
                        ),
                        _NavBarItem(
                          icon: PhosphorIconsRegular.vinylRecord,
                          selectedIcon: PhosphorIconsFill.vinylRecord,
                          label: 'Player',
                          selected: _tab == 1,
                          onTap: () => setState(() => _tab = 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }  void _showSleepTimer(BuildContext context, PlayerController ctrl) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(kSp),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Sleep Timer',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: kSp),
            ListTile(
              leading: const Icon(PhosphorIconsRegular.timer),
              title: const Text('15 Minutes'),
              onTap: () {
                ctrl.setSleepTimer(15);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sleep timer set for 15 minutes')),
                );
              },
            ),
            ListTile(
              leading: const Icon(PhosphorIconsRegular.timer),
              title: const Text('30 Minutes'),
              onTap: () {
                ctrl.setSleepTimer(30);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sleep timer set for 30 minutes')),
                );
              },
            ),
            ListTile(
              leading: const Icon(PhosphorIconsRegular.timer),
              title: const Text('60 Minutes'),
              onTap: () {
                ctrl.setSleepTimer(60);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sleep timer set for 60 minutes')),
                );
              },
            ),
            ListTile(
              leading: const Icon(PhosphorIconsRegular.xCircle),
              title: const Text('Turn Off Timer'),
              onTap: () {
                ctrl.setSleepTimer(0);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sleep timer turned off')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showQueue(BuildContext context, PlayerController ctrl) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (_, controller) =>
            QueueSheet(ctrl: ctrl, scrollController: controller),
      ),
    );
  }

  void _showBookmarks(BuildContext context, PlayerController ctrl) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
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
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: anim,
                child: child,
              ),
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
