// ignore_for_file: prefer_const_declarations

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../services/settings_service.dart';
import '../services/library_scan_service.dart';
import '../services/sonic_dna_analysis_service.dart';
import '../services/telemetry_service.dart';
import '../utils/content_mode.dart';
import 'diagnostics_screen.dart';
import '../design/design_system.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const kPadScreen = EdgeInsets.all(PlayaSpacing.md);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: const PlayaAppBar(title: 'Settings'),
      body: AnimatedBuilder(
        animation: SettingsService.instance,
        builder: (context, _) {
          final settings = SettingsService.instance;
          return ListView(
            padding: kPadScreen,
            children: [
              const PlayaSectionHeader(title: 'Sonic DNA'),
              _buildSwitchTile(
                context: context,
                title: 'Gapless Playback',
                subtitle: 'Remove silence between tracks',
                value: settings.gaplessPlayback,
                onChanged: settings.setGaplessPlayback,
                icon: PhosphorIconsBold.musicNotes,
              ),
              const SizedBox(height: PlayaSpacing.sm),

              const PlayaSectionHeader(title: 'Performance'),
              _buildSwitchTile(
                context: context,
                title: 'Low Performance Mode',
                subtitle: 'Reduce animations for smoother playback',
                value: settings.lowPerformanceMode,
                onChanged: settings.setLowPerformanceMode,
                icon: PhosphorIconsBold.gauge,
              ),
              _buildSwitchTile(
                context: context,
                title: 'Battery Saver',
                subtitle: 'Disable heavy visual effects',
                value: settings.batterySaver,
                onChanged: settings.setBatterySaver,
                icon: PhosphorIconsBold.batteryLow,
              ),
              const SizedBox(height: PlayaSpacing.sm),

              const PlayaSectionHeader(title: 'Playback'),
              Padding(
                padding: const EdgeInsets.only(bottom: PlayaSpacing.sm),
                child: PlayaCard(
                  padding: EdgeInsets.zero,
                  useMatteVariant: true,
                  child: PlayaSettingsTile(
                    leading: const Icon(PhosphorIconsBold.arrowsClockwise),
                    title: 'Seek Skip',
                    subtitle: '±${settings.seekSkipSeconds}s on skip buttons',
                    trailing: DropdownButton<int>(
                      value: settings.seekSkipSeconds,
                      dropdownColor: PlayaColors.surface,
                      underline: const SizedBox(),
                      items:
                          SettingsService.seekSkipOptions
                              .map(
                                (v) => DropdownMenuItem(
                                  value: v,
                                  child: Text('${v}s'),
                                ),
                              )
                              .toList(),
                      onChanged: (v) {
                        if (v != null) settings.setSeekSkipSeconds(v);
                      },
                    ),
                    showDivider: false,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: PlayaSpacing.sm),
                child: PlayaCard(
                  padding: EdgeInsets.zero,
                  useMatteVariant: true,
                  child: PlayaSettingsTile(
                    leading: const Icon(PhosphorIconsBold.waveSine),
                    title: 'Crossfade',
                    subtitle:
                        settings.crossfadeSeconds == 0
                            ? 'Off'
                            : '${settings.crossfadeSeconds}s crossfade',
                    trailing: DropdownButton<int>(
                      value: settings.crossfadeSeconds,
                      dropdownColor: PlayaColors.surface,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('Off')),
                        DropdownMenuItem(value: 2, child: Text('2s')),
                        DropdownMenuItem(value: 4, child: Text('4s')),
                        DropdownMenuItem(value: 6, child: Text('6s')),
                      ],
                      onChanged: (v) {
                        if (v != null) settings.setCrossfadeSeconds(v);
                      },
                    ),
                    showDivider: false,
                  ),
                ),
              ),
              _buildSwitchTile(
                context: context,
                title: 'Keep Screen On',
                subtitle: 'Prevent sleep while app is open',
                value: settings.keepScreenOn,
                onChanged: settings.setKeepScreenOn,
                icon: PhosphorIconsBold.sun,
              ),
              const SizedBox(height: PlayaSpacing.sm),

              const PlayaSectionHeader(title: 'Appearance'),
              Padding(
                padding: const EdgeInsets.only(
                  bottom: PlayaSpacing.sm,
                  left: PlayaSpacing.xs,
                  right: PlayaSpacing.xs,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Quick themes',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: PlayaColors.onSurfaceVariant.withValues(
                          alpha: 0.9,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonal(
                          onPressed: () async {
                            await settings.setAccentColor(
                              SettingsService.colorPresets['Lime Shock']!,
                            );
                            await settings.setShowSpaceBackground(true);
                          },
                          child: const Text('Neon Lime'),
                        ),
                        FilledButton.tonal(
                          onPressed: () async {
                            await settings.setAccentColor(
                              SettingsService.colorPresets['Champagne Gold']!,
                            );
                            await settings.setShowSpaceBackground(false);
                          },
                          child: const Text('Classic Gold'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _buildSwitchTile(
                context: context,
                title: 'Show Waveforms',
                subtitle: 'Display audio visualization',
                value: settings.showWaveforms,
                onChanged: settings.setShowWaveforms,
                icon: PhosphorIconsBold.waveform,
              ),
              _buildSwitchTile(
                context: context,
                title: 'Space Background',
                subtitle: 'Subtle animated nebulae',
                value: settings.showSpaceBackground,
                onChanged: settings.setShowSpaceBackground,
                icon: PhosphorIconsBold.planet,
              ),
              const SizedBox(height: PlayaSpacing.sm),

              const PlayaSectionHeader(title: 'Glass & Frosting'),
              _buildSwitchTile(
                context: context,
                title: 'Global Frosting',
                subtitle: 'Apply blur to all glass surfaces',
                value: settings.frostedGlassBlur,
                onChanged: settings.setFrostedGlassBlur,
                icon: PhosphorIconsBold.dropHalf,
              ),
              if (settings.frostedGlassBlur)
                _buildSliderTile(
                  title: 'Global Blur Intensity',
                  value: settings.glassBlurSigma,
                  min: 1,
                  max: 30,
                  onChanged: settings.setGlassBlurSigma,
                ),
              _buildSwitchTile(
                context: context,
                title: 'Library Specific Frosting',
                subtitle: 'Different frosting intensity for the library',
                value: settings.libraryFrostedBackground,
                onChanged: settings.setLibraryFrostedBackground,
                icon: PhosphorIconsBold.selectionBackground,
              ),
              if (settings.libraryFrostedBackground)
                _buildSliderTile(
                  title: 'Library Blur Intensity',
                  value: settings.libraryBlurSigma,
                  min: 1,
                  max: 30,
                  onChanged: settings.setLibraryBlurSigma,
                ),
              _buildSliderTile(
                title: 'Glass Opacity',
                value: settings.glassOpacity,
                min: 0.05,
                max: 0.95,
                onChanged: settings.setGlassOpacity,
              ),
              const SizedBox(height: PlayaSpacing.sm),

              // Accent Color Selector
              const Padding(
                padding: EdgeInsets.only(
                  bottom: PlayaSpacing.sm,
                  left: PlayaSpacing.xs,
                ),
                child: Text(
                  '[SYS//ACCENT_COLOR]',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    letterSpacing: 1.2,
                    color: PlayaColors.onSurfaceVariant,
                  ),
                ),
              ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children:
                    SettingsService.colorPresets.entries.map((entry) {
                      final isSelected = settings.accentColor == entry.value;
                      return Tooltip(
                        message: entry.key,
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            settings.setAccentColor(entry.value);
                          },
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Color(entry.value),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color:
                                    isSelected ? Colors.white : Colors.white24,
                                width: isSelected ? 3.5 : 1.5,
                              ),
                              boxShadow:
                                  isSelected
                                      ? [
                                        BoxShadow(
                                          color: Color(
                                            entry.value,
                                          ).withValues(alpha: 0.5),
                                          blurRadius: 8,
                                          spreadRadius: 1,
                                        ),
                                      ]
                                      : null,
                            ),
                            child:
                                isSelected
                                    ? const Icon(
                                      PhosphorIconsRegular.check,
                                      color: Colors.white,
                                      size: 20,
                                    )
                                    : null,
                          ),
                        ),
                      );
                    }).toList(),
              ),

              const SizedBox(height: PlayaSpacing.md),

              // Theme Mode Selector
              const Padding(
                padding: EdgeInsets.only(
                  bottom: PlayaSpacing.sm,
                  left: PlayaSpacing.xs,
                ),
                child: Text(
                  '[SYS//THEME_MODE]',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    letterSpacing: 1.2,
                    color: PlayaColors.onSurfaceVariant,
                  ),
                ),
              ),
              Row(
                children: [
                  _buildThemeModeCard(
                    context: context,
                    settings: settings,
                    value: SettingsService.themeClassic,
                    label: 'Classic',
                    description: 'Balanced & metallic',
                    icon: PhosphorIconsBold.circle,
                  ),
                  const SizedBox(width: PlayaSpacing.xs),
                  _buildThemeModeCard(
                    context: context,
                    settings: settings,
                    value: SettingsService.themeNeon,
                    label: 'Neon',
                    description: 'Vibrant glows',
                    icon: PhosphorIconsBold.sparkle,
                  ),
                  const SizedBox(width: PlayaSpacing.xs),
                  _buildThemeModeCard(
                    context: context,
                    settings: settings,
                    value: SettingsService.themeAlbumArt,
                    label: 'Album Art',
                    description: 'Dominant cover color',
                    icon: PhosphorIconsBold.imageSquare,
                  ),
                ],
              ),

              const SizedBox(height: PlayaSpacing.lg),

              const PlayaSectionHeader(title: 'Library'),
              Padding(
                padding: const EdgeInsets.only(bottom: PlayaSpacing.sm),
                child: PlayaCard(
                  padding: EdgeInsets.zero,
                  useMatteVariant: true,
                  child: PlayaSettingsTile(
                    leading: const Icon(PhosphorIconsBold.funnel),
                    title: 'Default Browse Filter',
                    subtitle: settings.libraryBrowseFilter.label,
                    trailing: DropdownButton<LibraryBrowseFilter>(
                      value: settings.libraryBrowseFilter,
                      dropdownColor: PlayaColors.surface,
                      underline: const SizedBox(),
                      items:
                          LibraryBrowseFilter.values
                              .map(
                                (f) => DropdownMenuItem(
                                  value: f,
                                  child: Text(f.label),
                                ),
                              )
                              .toList(),
                      onChanged: (v) {
                        if (v != null) settings.setLibraryBrowseFilter(v);
                      },
                    ),
                    showDivider: false,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(PhosphorIconsBold.arrowsClockwise),
                title: const Text(
                  'Rescan Library',
                  style: TextStyle(
                    color: PlayaColors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: const Text(
                  'Refresh your music collection',
                  style: TextStyle(
                    color: PlayaColors.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
                onTap: () async {
                  HapticFeedback.mediumImpact();
                  await LibraryScanService.instance.scanLibrary(force: true);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Library scan complete')),
                    );
                  }
                },
              ),
              const SizedBox(height: PlayaSpacing.sm),
              PlayaCard(
                padding: EdgeInsets.zero,
                useMatteVariant: true,
                child: PlayaSettingsTile(
                  leading: const Icon(PhosphorIconsBold.gauge),
                  title: 'Sonic DNA Analysis',
                  subtitle: 'Detect BPM & key for Neural Mix and smart mixes',
                  showDivider: false,
                  onTap: () => _openSonicDnaAnalysis(context),
                ),
              ),
              const SizedBox(height: PlayaSpacing.lg),

              const PlayaSectionHeader(title: 'Privacy & Analytics'),
              _buildSwitchTile(
                context: context,
                title: 'Anonymous Crash & Usage Data',
                subtitle:
                    'Send anonymous crash reports and usage stats to improve '
                    'Playa. Off by default — no library, history, or personal '
                    'data is ever shared.',
                value: settings.telemetryConsent,
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  final telemetry = TelemetryService.instance;
                  if (v) {
                    unawaited(telemetry.grantConsent());
                  } else {
                    unawaited(telemetry.revokeConsent());
                  }
                },
                icon: PhosphorIconsBold.shieldCheck,
              ),
              const SizedBox(height: PlayaSpacing.lg),

              Center(
                child: OutlinedButton.icon(
                  icon: const Icon(
                    PhosphorIconsBold.arrowCounterClockwise,
                    size: 18,
                  ),
                  label: const Text('Reset All Settings'),
                  onPressed: () async {
                    HapticFeedback.heavyImpact();
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder:
                          (ctx) => AlertDialog(
                            backgroundColor: PlayaColors.surface,
                            title: const Text(
                              'Reset All Settings?',
                              style: TextStyle(color: PlayaColors.onSurface),
                            ),
                            content: const Text(
                              'This will restore every setting to its default value.',
                              style: TextStyle(
                                color: PlayaColors.onSurfaceVariant,
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(
                                    color: PlayaColors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text(
                                  'Reset',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                    );
                    if (confirmed == true) {
                      await settings.resetToDefaults();
                    }
                  },
                ),
              ),

              const SizedBox(height: PlayaSpacing.lg),
              Center(
                child: GestureDetector(
                  onLongPress: () {
                    HapticFeedback.mediumImpact();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DiagnosticsScreen(),
                      ),
                    );
                  },
                  child: Text(
                    'Playa v1.0.0',
                    style: TextStyle(
                      color: PlayaColors.onSurface.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: PlayaSpacing.xxl),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSwitchTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
    required IconData icon,
  }) {
    final accentColor = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: PlayaSpacing.sm),
      child: PlayaCard(
        padding: EdgeInsets.zero,
        useMatteVariant: true,
        child: SwitchListTile(
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11,
              color: PlayaColors.onSurfaceVariant,
            ),
          ),
          value: value,
          onChanged: (v) {
            HapticFeedback.selectionClick();
            if (onChanged != null) onChanged(v);
          },
          secondary: Icon(icon, color: PlayaColors.onSurface, size: 20),
          thumbColor: WidgetStateProperty.all(accentColor),
          trackColor: WidgetStateProperty.all(
            accentColor.withValues(alpha: 0.3),
          ),
        ),
      ),
    );
  }

  Widget _buildSliderTile({
    required String title,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: PlayaSpacing.md,
        vertical: PlayaSpacing.xxs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  color: PlayaColors.onSurfaceVariant,
                ),
              ),
              Text(
                value.toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: PlayaColors.onSurface,
                ),
              ),
            ],
          ),
          Slider(
            value: value,
            min: min,
            max: max,
            onChanged: (v) {
              onChanged(v);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildThemeModeCard({
    required BuildContext context,
    required SettingsService settings,
    required String value,
    required String label,
    required String description,
    required IconData icon,
  }) {
    final isSelected = settings.themeMode == value;
    final accent = settings.accentFor();

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          settings.setThemeMode(value);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color:
                isSelected
                    ? accent.withValues(alpha: 0.12)
                    : PlayaColors.surface,
            borderRadius: BorderRadius.circular(PlayaRadii.sm),
            border: Border.all(
              color: isSelected ? accent : PlayaColors.borderSubtle,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isSelected ? accent : PlayaColors.onSurfaceVariant,
                size: 22,
              ),
              const SizedBox(height: PlayaSpacing.xs),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: isSelected ? accent : PlayaColors.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 10,
                  color: PlayaColors.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _openSonicDnaAnalysis(BuildContext context) {
  final svc = SonicDnaAnalysisService.instance;
  if (!svc.isRunning) {
    unawaited(svc.startAnalysis());
  }

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder:
        (ctx) => AnimatedBuilder(
          animation: svc,
          builder: (context, _) {
            final running = svc.isRunning;
            final progress = svc.total == 0 ? 0.0 : svc.done / svc.total;
            final accent = Theme.of(context).colorScheme.primary;

            String status;
            if (running) {
              status = 'Analyzing…';
            } else {
              switch (svc.phase) {
                case SonicDnaAnalysisPhase.done:
                  status = 'Complete';
                  break;
                case SonicDnaAnalysisPhase.error:
                  status = 'Failed';
                  break;
                default:
                  status = 'Ready';
              }
            }

            return GlassPanel(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              borderColor: Colors.white.withValues(alpha: 0.14),
              backgroundColor: PlayaColors.glass,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(PlayaSpacing.md),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Sonic DNA Analysis',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: PlayaTypography.lg,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: PlayaSpacing.sm),
                      if (running)
                        LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          color: accent,
                          backgroundColor: PlayaColors.trackMuted,
                        )
                      else if (svc.phase == SonicDnaAnalysisPhase.error)
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: PlayaSpacing.xs,
                          ),
                          child: Text(
                            svc.lastError ?? 'Analysis failed',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      const SizedBox(height: PlayaSpacing.sm),
                      Text(
                        '$status · ${svc.done}/${svc.total} tracks · '
                        '${svc.skipped} cached · ${svc.found} with BPM/key',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: PlayaColors.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      if (svc.phase == SonicDnaAnalysisPhase.done &&
                          svc.lastRunDuration != null) ...[
                        const SizedBox(height: PlayaSpacing.xs),
                        Text(
                          'Finished in ${_formatRunDuration(svc.lastRunDuration!)}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: PlayaColors.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: PlayaSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: PlayaButton(
                              label: running ? 'Cancel' : 'Close',
                              isPrimary: !running,
                              onPressed: () {
                                if (running) svc.cancel();
                                Navigator.pop(ctx);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
  );
}

String _formatRunDuration(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds}s';
  final m = d.inMinutes;
  final s = d.inSeconds.remainder(60);
  return '${m}m ${s}s';
}
