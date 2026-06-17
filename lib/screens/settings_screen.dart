// ignore_for_file: prefer_const_declarations

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../services/settings_service.dart';
import '../services/library_scan_service.dart';
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
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AnimatedBuilder(
        animation: SettingsService.instance,
        builder: (context, _) {
          final settings = SettingsService.instance;
          return ListView(
            padding: kPadScreen,
            children: [
              _buildSectionHeader('Sonic DNA'),
              _buildSwitchTile(
                context: context,
                title: 'Gapless Playback',
                subtitle: 'Remove silence between tracks',
                value: settings.gaplessPlayback,
                onChanged: settings.setGaplessPlayback,
                icon: PhosphorIconsBold.musicNotes,
              ),
              const SizedBox(height: PlayaSpacing.sm * 2),

              _buildSectionHeader('Performance'),
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
              const SizedBox(height: PlayaSpacing.lg),

              _buildSectionHeader('Playback'),
              Padding(
                padding: const EdgeInsets.only(bottom: PlayaSpacing.sm),
                child: PlayaSettingsTile(
                  leading: const Icon(PhosphorIconsBold.arrowsClockwise),
                  title: 'Seek Skip',
                  subtitle: '±${settings.seekSkipSeconds}s on skip buttons',
                  trailing: DropdownButton<int>(
                    value: settings.seekSkipSeconds,
                    dropdownColor: PlayaColors.surface,
                    underline: const SizedBox(),
                    items: SettingsService.seekSkipOptions
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
              Padding(
                padding: const EdgeInsets.only(bottom: PlayaSpacing.sm),
                child: PlayaSettingsTile(
                  leading: const Icon(PhosphorIconsBold.waveSine),
                  title: 'Crossfade',
                  subtitle: settings.crossfadeSeconds == 0
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
              _buildSwitchTile(
                context: context,
                title: 'Keep Screen On',
                subtitle: 'Prevent sleep while app is open',
                value: settings.keepScreenOn,
                onChanged: settings.setKeepScreenOn,
                icon: PhosphorIconsBold.sun,
              ),
              const SizedBox(height: PlayaSpacing.lg),

              _buildSectionHeader('Appearance'),
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
              _buildSwitchTile(
                context: context,
                title: 'Frosted Glass Blur',
                subtitle: 'Panels stay see-through; enable to add blur',
                value: settings.frostedGlassBlur,
                onChanged: settings.setFrostedGlassBlur,
                icon: PhosphorIconsBold.dropHalf,
              ),
              const SizedBox(height: PlayaSpacing.md),

              // Accent Color Selector (improved)
              Padding(
                padding: const EdgeInsets.only(bottom: PlayaSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        'Accent Color',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: SettingsService.colorPresets.entries.map((entry) {
                        final isSelected = settings.accentColor == entry.value;
                        return Tooltip(
                          message: entry.key,
                          child: GestureDetector(
                            onTap: () => settings.setAccentColor(entry.value),
                            child: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: Color(entry.value),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected ? Colors.white : Colors.white24,
                                  width: isSelected ? 3.5 : 1.5,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: Color(entry.value).withValues(alpha: 0.5),
                                          blurRadius: 8,
                                          spreadRadius: 1,
                                        )
                                      ]
                                    : null,
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check, color: Colors.white, size: 20)
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: PlayaSpacing.md),

              // Theme Mode Selector (much improved)
              Padding(
                padding: const EdgeInsets.only(bottom: PlayaSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        'Theme Mode',
                        style: TextStyle(fontWeight: FontWeight.w600),
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
                        const SizedBox(width: 8),
                        _buildThemeModeCard(
                          context: context,
                          settings: settings,
                          value: SettingsService.themeNeon,
                          label: 'Neon',
                          description: 'Vibrant glows',
                          icon: PhosphorIconsBold.sparkle,
                        ),
                        const SizedBox(width: 8),
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
                  ],
                ),
              ),

              const SizedBox(height: PlayaSpacing.lg),

              _buildSectionHeader('Library'),
              AnimatedBuilder(
                animation: settings,
                builder: (context, _) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: PlayaSpacing.sm),
                    child: PlayaSettingsTile(
                      leading: const Icon(PhosphorIconsBold.funnel),
                      title: 'Default Browse Filter',
                      subtitle: settings.libraryBrowseFilter.label,
                      trailing: DropdownButton<LibraryBrowseFilter>(
                        value: settings.libraryBrowseFilter,
                        dropdownColor: PlayaColors.surface,
                        underline: const SizedBox(),
                        items: LibraryBrowseFilter.values
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
                  );
                },
              ),
              ListTile(
                leading: const Icon(PhosphorIconsBold.arrowsClockwise),
                title: const Text('Rescan Library'),
                subtitle: const Text('Refresh your music collection'),
                onTap: () async {
                  await LibraryScanService.instance.scanLibrary(force: true);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Library scan complete')),
                    );
                  }
                },
              ),
              const SizedBox(height: PlayaSpacing.xxl),

              Center(
                child: OutlinedButton.icon(
                  icon: const Icon(PhosphorIconsBold.arrowCounterClockwise, size: 18),
                  label: const Text('Reset All Settings'),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Reset All Settings?'),
                        content: const Text('This will restore every setting to its default value.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset', style: TextStyle(color: Colors.red))),
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
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DiagnosticsScreen()));
                  },
                  child: Text(
                    'Playa v1.0.0',
                    style: TextStyle(color: PlayaColors.onSurface.withValues(alpha: 0.5), fontSize: 12),
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: PlayaSpacing.sm, left: PlayaSpacing.xs),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: PlayaColors.onSurfaceVariant),
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
        child: SwitchListTile(
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: PlayaColors.onSurfaceVariant)),
          value: value,
          onChanged: onChanged,
          secondary: Icon(icon, color: PlayaColors.onSurface, size: 20),
          thumbColor: WidgetStateProperty.all(accentColor),
          trackColor: WidgetStateProperty.all(accentColor.withValues(alpha: 0.3)),
        ),
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
        onTap: () => settings.setThemeMode(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? accent.withValues(alpha: 0.12) : PlayaColors.surface,
            borderRadius: BorderRadius.circular(12),
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
              const SizedBox(height: 6),
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
