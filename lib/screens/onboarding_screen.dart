// lib/screens/onboarding_screen.dart
// First-run welcome: value pitch, local storage access, content focus.

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../design/design_system.dart';
import '../services/settings_service.dart';
import '../services/telemetry_service.dart';
import '../ui/deep_space_background.dart';
import '../utils/content_mode.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const int _pageCount = 4;

  final PageController _pageController = PageController();
  int _page = 0;
  bool _accessGranted = !Platform.isAndroid;
  bool _requesting = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _requestAccess() async {
    setState(() => _requesting = true);

    var granted = !Platform.isAndroid;
    if (Platform.isAndroid) {
      // Permission.audio = READ_MEDIA_AUDIO on Android 13+ (declared in the
      // manifest); older Android falls back to storage access below.
      granted = await Permission.audio.isGranted;
      if (!granted) {
        granted = await Permission.audio.request().isGranted;
      }
      if (!granted) {
        final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
        if (sdk < 33) {
          granted = await Permission.storage.request().isGranted;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _requesting = false;
      _accessGranted = granted;
    });
  }

  void _next() {
    HapticFeedback.selectionClick();
    if (_page < _pageCount - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _complete() async {
    HapticFeedback.mediumImpact();
    await SettingsService.instance.setTelemetryConsentSeen(true);
    await SettingsService.instance.setOnboardingComplete(true);
  }

  String get _primaryLabel => switch (_page) {
    0 => 'Get Started',
    1 => _accessGranted ? 'Continue' : 'Allow Access',
    2 => 'Continue',
    _ => 'Start Listening',
  };

  VoidCallback? get _primaryAction => switch (_page) {
    0 => _next,
    1 => _accessGranted ? _next : _requestAccess,
    2 => _next,
    _ => _complete,
  };

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: DeepSpaceBackground(subtle: true, accentColor: accent),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: PlayaSpacing.md,
                      vertical: PlayaSpacing.sm,
                    ),
                    child: TextButton(
                      onPressed: _complete,
                      child: const Text('Skip'),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (i) {
                      setState(() => _page = i);
                      if (i == _pageCount - 1) {
                        // The user has seen the telemetry choice.
                        SettingsService.instance.setTelemetryConsentSeen(true);
                      }
                    },
                    children: const [
                      _WelcomePage(),
                      _AccessPage(),
                      _FocusPage(),
                      _TelemetryPage(),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    PlayaSpacing.lg,
                    PlayaSpacing.xs,
                    PlayaSpacing.lg,
                    PlayaSpacing.lg,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PageDots(count: _pageCount, active: _page),
                      const SizedBox(height: PlayaSpacing.lg),
                      SizedBox(
                        width: double.infinity,
                        child: PlayaButton(
                          label: _primaryLabel,
                          isLoading: _requesting,
                          onPressed: _primaryAction,
                        ),
                      ),
                      if (_page == 1 && !_accessGranted)
                        Padding(
                          padding: const EdgeInsets.only(top: PlayaSpacing.sm),
                          child: Text(
                            _requesting
                                ? 'Requesting access…'
                                : 'You can skip and grant access later from Settings.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: PlayaColors.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  final int count;
  final int active;

  const _PageDots({required this.count, required this.active});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: PlayaSpacing.sm),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: i == active ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color:
                  i == active
                      ? accent
                      : PlayaColors.onSurfaceVariant.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(PlayaRadii.pill),
            ),
          ),
        ],
      ],
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context) {
    return const _OnboardingScaffold(
      icon: PhosphorIconsFill.vinylRecord,
      title: 'Playa',
      body: 'Your local music and audiobooks,\nlaunched into deep space.',
      children: [
        _FeatureRow(
          icon: PhosphorIconsBold.shieldCheck,
          label: '100% offline & private — no account, no cloud',
        ),
        SizedBox(height: PlayaSpacing.md),
        _FeatureRow(
          icon: PhosphorIconsBold.bookmarkSimple,
          label: 'Audiobooks: bookmarks, speed control, sleep timer',
        ),
        SizedBox(height: PlayaSpacing.md),
        _FeatureRow(
          icon: PhosphorIconsBold.brain,
          label: 'Music: Neural Mix, equalizer, lyrics, waveforms',
        ),
      ],
    );
  }
}

class _AccessPage extends StatelessWidget {
  const _AccessPage();

  @override
  Widget build(BuildContext context) {
    return const _OnboardingScaffold(
      icon: PhosphorIconsBold.folderSimple,
      title: 'Access your music',
      body:
          'Playa plays files stored on this device. Grant access so it can scan '
          'your music and audiobooks. Everything stays on-device — nothing is uploaded.',
    );
  }
}

class _FocusPage extends StatelessWidget {
  const _FocusPage();

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final filter = SettingsService.instance.libraryBrowseFilter;

    return _OnboardingScaffold(
      icon: PhosphorIconsBold.headphones,
      title: 'What are you into?',
      body: 'Playa adapts its player around your content.',
      children: [
        const SizedBox(height: PlayaSpacing.md),
        _FocusOption(
          icon: PhosphorIconsBold.vinylRecord,
          label: 'Everything',
          subtitle: 'Music, audiobooks & podcasts',
          selected: filter == LibraryBrowseFilter.all,
          accent: accent,
          onTap: () => _selectFocusFrom(context, LibraryBrowseFilter.all),
        ),
        const SizedBox(height: PlayaSpacing.sm),
        _FocusOption(
          icon: PhosphorIconsBold.musicNotesSimple,
          label: 'Music',
          subtitle: 'Tracks, playlists & mixes',
          selected: filter == LibraryBrowseFilter.music,
          accent: accent,
          onTap: () => _selectFocusFrom(context, LibraryBrowseFilter.music),
        ),
        const SizedBox(height: PlayaSpacing.sm),
        _FocusOption(
          icon: PhosphorIconsBold.bookmarkSimple,
          label: 'Audiobooks',
          subtitle: 'Long-form listening & series',
          selected: filter == LibraryBrowseFilter.audiobook,
          accent: accent,
          onTap: () => _selectFocusFrom(context, LibraryBrowseFilter.audiobook),
        ),
      ],
    );
  }

  void _selectFocusFrom(BuildContext context, LibraryBrowseFilter filter) {
    HapticFeedback.selectionClick();
    SettingsService.instance.setLibraryBrowseFilter(filter);
  }
}

class _TelemetryPage extends StatefulWidget {
  const _TelemetryPage();

  @override
  State<_TelemetryPage> createState() => _TelemetryPageState();
}

class _TelemetryPageState extends State<_TelemetryPage> {
  late bool _share;

  @override
  void initState() {
    super.initState();
    _share = SettingsService.instance.telemetryConsent;
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return _OnboardingScaffold(
      icon: PhosphorIconsBold.shieldCheck,
      title: 'Help improve Playa',
      body:
          'Send anonymous crash reports and usage stats to make Playa '
          'better. Your library, listening history, and personal data never '
          'leave this device — you can change this anytime in Settings.',
      children: [
        const SizedBox(height: PlayaSpacing.md),
        _FocusOption(
          icon: PhosphorIconsBold.trendUp,
          label: 'Share anonymous data',
          subtitle: 'Crash reports + usage stats only',
          selected: _share,
          accent: accent,
          onTap: () => _choose(true),
        ),
        const SizedBox(height: PlayaSpacing.sm),
        _FocusOption(
          icon: PhosphorIconsBold.lockSimple,
          label: 'Keep everything local',
          subtitle: 'No data sent. Change anytime in Settings',
          selected: !_share,
          accent: accent,
          onTap: () => _choose(false),
        ),
      ],
    );
  }

  void _choose(bool share) {
    HapticFeedback.selectionClick();
    setState(() => _share = share);
    if (share) {
      TelemetryService.instance.grantConsent();
    } else {
      TelemetryService.instance.revokeConsent();
    }
  }
}

class _OnboardingScaffold extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final List<Widget> children;

  const _OnboardingScaffold({
    required this.icon,
    required this.title,
    required this.body,
    this.children = const [],
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: PlayaSpacing.xl,
        vertical: PlayaSpacing.md,
      ),
      child: Column(
        children: [
          const SizedBox(height: PlayaSpacing.lg),
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: PlayaColors.glass,
              border: Border.all(
                color: accent.withValues(alpha: 0.4),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.25),
                  blurRadius: 32,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(icon, size: 44, color: accent),
          ),
          const SizedBox(height: PlayaSpacing.xl),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: PlayaColors.onSurface,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: PlayaSpacing.md),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: PlayaColors.onSurfaceVariant,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(PlayaRadii.sm),
          ),
          child: Icon(icon, size: 18, color: accent),
        ),
        const SizedBox(width: PlayaSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: PlayaColors.onSurface,
              fontSize: 13,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _FocusOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _FocusOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PlayaRadii.lg),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: PlayaSpacing.md,
            vertical: PlayaSpacing.md,
          ),
          decoration: BoxDecoration(
            color:
                selected ? accent.withValues(alpha: 0.18) : PlayaColors.glass,
            borderRadius: BorderRadius.circular(PlayaRadii.lg),
            border: Border.all(
              color:
                  selected
                      ? accent.withValues(alpha: 0.6)
                      : PlayaColors.borderSubtle,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 22,
                color: selected ? accent : PlayaColors.onSurfaceVariant,
              ),
              const SizedBox(width: PlayaSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: selected ? accent : PlayaColors.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: PlayaColors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(PhosphorIconsBold.check, color: accent, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
