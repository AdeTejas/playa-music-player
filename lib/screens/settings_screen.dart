import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'dart:io';
import '../services/windows_audio_query.dart';
import '../services/settings_service.dart';
import '../services/sonic_dna_service.dart';
import '../services/library_scan_service.dart';
import 'diagnostics_screen.dart';
import '../ui/tokens.dart';
import '../ui/glass_panel.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _defaultWindowsExtensions = <String>[
    'mp3',
    'm4a',
    'aac',
    'wav',
    'flac',
    'ogg',
    'opus',
    'wma',
    'aiff',
    'alac',
  ];

  @override
  Widget build(BuildContext context) {
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
              Padding(
                padding: const EdgeInsets.only(bottom: kSp),
                child: GlassPanel(
                  borderRadius: BorderRadius.circular(kRadius),
                  borderColor: Colors.white.withValues(alpha: 0.15),
                  child: Material(
                    color: Colors.transparent,
                    child: ListTile(
                      leading: const Icon(
                        PhosphorIconsBold.dna,
                        color: kColorOn,
                        size: kIconMd,
                      ),
                      title: const Text(
                        'Analyze Library',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Detect BPM and Key for all songs',
                        style: TextStyle(
                          fontSize: kTextXs,
                          color: kColorOn.withValues(alpha: 0.6),
                        ),
                      ),
                      trailing: const Icon(
                        PhosphorIconsBold.caretRight,
                        color: kColorOn,
                        size: kIconSm,
                      ),
                      onTap: () => _showAnalysisDialog(context),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: kSp * 2),

              _buildSectionHeader('Performance'),
              _buildSwitchTile(
                context: context,
                title: 'Low Performance Mode',
                subtitle: 'Reduce animations and effects for smoother playback',
                value: settings.lowPerformanceMode,
                onChanged: settings.setLowPerformanceMode,
                icon: PhosphorIconsBold.gauge,
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: kSp),
                child: GlassPanel(
                  borderRadius: BorderRadius.circular(kRadius),
                  borderColor: Colors.white.withValues(alpha: 0.15),
                  child: Material(
                    color: Colors.transparent,
                    child: ListTile(
                      leading: const Icon(
                        PhosphorIconsBold.gauge,
                        color: kColorOn,
                        size: kIconMd,
                      ),
                      title: const Text(
                        'Turntable Effects',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        settings.turntablePerfTier == 0
                            ? 'Off'
                            : (settings.turntablePerfTier == 1
                                ? 'Minimal'
                                : 'Full'),
                        style: TextStyle(
                          fontSize: kTextXs,
                          color: kColorOn.withValues(alpha: 0.6),
                        ),
                      ),
                      trailing: DropdownButton<int>(
                        value: settings.turntablePerfTier,
                        dropdownColor: kColorSurface,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Off')),
                          DropdownMenuItem(value: 1, child: Text('Minimal')),
                          DropdownMenuItem(value: 2, child: Text('Full')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          settings.setTurntablePerfTier(v);
                        },
                      ),
                    ),
                  ),
                ),
              ),
              _buildSwitchTile(
                context: context,
                title: 'Turntable Slipmat Scratching',
                subtitle: 'Allow record dragging to scrub playback',
                value: settings.turntableSlipmatEnabled,
                onChanged: settings.setTurntableSlipmatEnabled,
                icon: PhosphorIconsBold.waves,
              ),
              _buildSwitchTile(
                context: context,
                title: 'Turntable Needle Drop',
                subtitle: 'Allow dragging the tonearm to seek',
                value: settings.turntableNeedleDropEnabled,
                onChanged: settings.setTurntableNeedleDropEnabled,
                icon: PhosphorIconsBold.arrowsClockwise,
              ),
              const SizedBox(height: kSp * 2),

              _buildSectionHeader('Playback'),
              Padding(
                padding: const EdgeInsets.only(bottom: kSp),
                child: GlassPanel(
                  borderRadius: BorderRadius.circular(kRadius),
                  borderColor: Colors.white.withValues(alpha: 0.15),
                  child: Material(
                    color: Colors.transparent,
                    child: ListTile(
                      leading: const Icon(
                        PhosphorIconsBold.waveSine,
                        color: kColorOn,
                        size: kIconMd,
                      ),
                      title: const Text(
                        'Crossfade',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        settings.crossfadeSeconds == 0
                            ? 'Off (gapless)'
                            : '${settings.crossfadeSeconds}s crossfade',
                        style: TextStyle(
                          fontSize: kTextXs,
                          color: kColorOn.withValues(alpha: 0.6),
                        ),
                      ),
                      trailing: DropdownButton<int>(
                        value: settings.crossfadeSeconds,
                        dropdownColor: kColorSurface,
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('Off')),
                          DropdownMenuItem(value: 2, child: Text('2s')),
                          DropdownMenuItem(value: 4, child: Text('4s')),
                          DropdownMenuItem(value: 6, child: Text('6s')),
                          DropdownMenuItem(value: 8, child: Text('8s')),
                          DropdownMenuItem(value: 10, child: Text('10s')),
                          DropdownMenuItem(value: 12, child: Text('12s')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          settings.setCrossfadeSeconds(v);
                        },
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: kSp),
                child: GlassPanel(
                  borderRadius: BorderRadius.circular(kRadius),
                  borderColor: Colors.white.withValues(alpha: 0.15),
                  child: Material(
                    color: Colors.transparent,
                    child: ListTile(
                      leading: const Icon(
                        PhosphorIconsBold.timer,
                        color: kColorOn,
                        size: kIconMd,
                      ),
                      title: const Text(
                        'Sleep Fade Out',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        settings.sleepFadeSeconds == 0
                            ? 'Off'
                            : '${settings.sleepFadeSeconds}s fade',
                        style: TextStyle(
                          fontSize: kTextXs,
                          color: kColorOn.withValues(alpha: 0.6),
                        ),
                      ),
                      trailing: DropdownButton<int>(
                        value: settings.sleepFadeSeconds,
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
                          settings.setSleepFadeSeconds(v);
                        },
                      ),
                    ),
                  ),
                ),
              ),
              _buildSwitchTile(
                context: context,
                title: 'Loudness Normalization (ReplayGain)',
                subtitle:
                    'Normalize loudness between tracks when tags are present',
                value: settings.replayGainEnabled,
                onChanged: settings.setReplayGainEnabled,
                icon: PhosphorIconsBold.soundcloudLogo,
              ),
              _buildSwitchTile(
                context: context,
                title: 'Smart Volume Limiter',
                subtitle: 'Reduce gain to prevent clipping when peaks are high',
                value: settings.smartVolumeLimiterEnabled,
                onChanged: settings.setSmartVolumeLimiterEnabled,
                icon: PhosphorIconsBold.shieldCheck,
              ),
              const SizedBox(height: kSp * 2),

              _buildSectionHeader('Appearance'),
              _buildSwitchTile(
                context: context,
                title: 'Space Background',
                subtitle: 'Show animated stars and nebula',
                value: settings.showSpaceBackground,
                onChanged:
                    settings.batterySaver
                        ? null
                        : settings.setShowSpaceBackground,
                icon: PhosphorIconsBold.planet,
              ),
              _buildSwitchTile(
                context: context,
                title: 'High Quality Blur',
                subtitle: 'Enable glassmorphism effects',
                value: settings.highQualityBlur,
                onChanged:
                    settings.batterySaver ? null : settings.setHighQualityBlur,
                icon: PhosphorIconsBold.drop,
              ),
              _buildSwitchTile(
                context: context,
                title: 'Show Waveforms',
                subtitle: 'Display audio visualization',
                value: settings.showWaveforms,
                onChanged:
                    settings.batterySaver ? null : settings.setShowWaveforms,
                icon: PhosphorIconsBold.waves,
              ),

              const SizedBox(height: kSp),
              const Padding(
                padding: EdgeInsets.only(left: kSp, bottom: kSp),
                child: Text(
                  'Accent Color',
                  style: TextStyle(fontSize: kTextXs, color: kColorOn2),
                ),
              ),
              _buildColorPicker(settings),
              const SizedBox(height: kSp * 2),

              _buildSectionHeader('Library'),
              Padding(
                padding: const EdgeInsets.only(bottom: kSp),
                child: GlassPanel(
                  borderRadius: BorderRadius.circular(kRadius),
                  borderColor: Colors.white.withValues(alpha: 0.15),
                  child: Material(
                    color: Colors.transparent,
                    child: ListTile(
                      leading: const Icon(
                        PhosphorIconsBold.arrowsClockwise,
                        color: kColorOn,
                        size: kIconMd,
                      ),
                      title: const Text(
                        'Rescan now',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Refresh the library list',
                        style: TextStyle(
                          fontSize: kTextXs,
                          color: kColorOn.withValues(alpha: 0.6),
                        ),
                      ),
                      onTap: () async {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Scanning library...')),
                        );
                        final songs = await LibraryScanService.instance
                            .scanLibrary(restorePlayerState: false);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Scan complete: ${songs.length} songs',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              ListTile(
                title: const Text('Default Sort'),
                subtitle: Text(
                  settings.librarySortType == 'DATE_ADDED'
                      ? 'Date Added (Newest)'
                      : settings.librarySortType == 'TITLE'
                      ? 'Title (A-Z)'
                      : settings.librarySortType == 'ARTIST'
                      ? 'Artist (A-Z)'
                      : 'Album (A-Z)',
                  style: TextStyle(
                    fontSize: kTextXs,
                    color: kColorOn.withValues(alpha: 0.6),
                  ),
                ),
                leading: const Icon(
                  PhosphorIconsBold.sortAscending,
                  color: kColorOn,
                  size: kIconMd,
                ),
                trailing: DropdownButton<String>(
                  value: settings.librarySortType,
                  dropdownColor: kColorCard,
                  underline: const SizedBox(),
                  style: const TextStyle(color: Colors.white),
                  icon: const Icon(
                    PhosphorIconsBold.caretDown,
                    color: kColorOn,
                    size: 16,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'DATE_ADDED',
                      child: Text('Date Added'),
                    ),
                    DropdownMenuItem(value: 'TITLE', child: Text('Title')),
                    DropdownMenuItem(value: 'ARTIST', child: Text('Artist')),
                    DropdownMenuItem(value: 'ALBUM', child: Text('Album')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      // Default to DESC (1) for Date Added, ASC (0) for others
                      final order = v == 'DATE_ADDED' ? 1 : 0;
                      settings.setLibrarySort(v, order);
                    }
                  },
                ),
              ),

              if (Platform.isWindows) ...[
                const SizedBox(height: kSp * 2),
                _buildSectionHeader('Windows Scan'),
                ListTile(
                  title: const Text('Scan folders'),
                  subtitle: Text(
                    settings.windowsScanFolders.isEmpty
                        ? 'Default (Music + Downloads)'
                        : '${settings.windowsScanFolders.length} folder(s)',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                  leading: const Icon(
                    PhosphorIconsBold.folderOpen,
                    color: Color(0xFFE8DCCA),
                  ),
                  trailing: const Icon(
                    PhosphorIconsBold.caretRight,
                    color: Color(0xFFE8DCCA),
                  ),
                  onTap: () => _showWindowsFoldersDialog(context),
                ),
                _buildSwitchTile(
                  context: context,
                  title: 'Recursive scan',
                  subtitle: 'Scan subfolders when enabled',
                  value: settings.windowsScanRecursive,
                  onChanged: settings.setWindowsScanRecursive,
                  icon: PhosphorIconsBold.treeStructure,
                ),
                ListTile(
                  title: const Text('File extensions'),
                  subtitle: Text(
                    settings.windowsScanExtensions.join(', '),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  leading: const Icon(
                    PhosphorIconsBold.file,
                    color: Color(0xFFE8DCCA),
                  ),
                  trailing: const Icon(
                    PhosphorIconsBold.caretRight,
                    color: Color(0xFFE8DCCA),
                  ),
                  onTap: () => _showWindowsExtensionsDialog(context),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    left: kSp,
                    right: kSp,
                    bottom: kSp,
                  ),
                  child: Text(
                    'Changes apply on the next library scan.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: kSp * 2),

              _buildSectionHeader('Playback'),
              _buildSwitchTile(
                context: context,
                title: 'Keep Screen On',
                subtitle: 'Prevent screen from sleeping while app is open',
                value: settings.keepScreenOn,
                onChanged: settings.setKeepScreenOn,
                icon: PhosphorIconsBold.sun,
              ),
              ListTile(
                title: const Text('Audio Focus'),
                subtitle: Text(
                  settings.audioFocusMode == 'pause'
                      ? 'Pause on interruption'
                      : settings.audioFocusMode == 'duck'
                      ? 'Lower volume on interruption'
                      : 'Ignore interruptions',
                ),
                leading: Icon(
                  PhosphorIconsBold.speakerHigh,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                trailing: DropdownButton<String>(
                  value: settings.audioFocusMode,
                  dropdownColor: Theme.of(context).cardColor,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'pause', child: Text('Pause')),
                    DropdownMenuItem(value: 'duck', child: Text('Duck')),
                    DropdownMenuItem(value: 'none', child: Text('Ignore')),
                  ],
                  onChanged: (v) {
                    if (v != null) settings.setAudioFocusMode(v);
                  },
                ),
              ),

              const SizedBox(height: kSp * 2),

              // _buildSectionHeader('Power'),
              // _buildSwitchTile(
              //   title: 'Battery Saver',
              //   subtitle: 'Disable animations and blur to save power',
              //   value: settings.batterySaver,
              //   onChanged: settings.setBatterySaver,
              //   icon: PhosphorIconsBold.batteryCharging,
              // ),
              const SizedBox(height: kSp * 4),
              Center(
                child: GestureDetector(
                  onLongPress: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DiagnosticsScreen(),
                      ),
                    );
                  },
                  child: Text(
                    'Playa v1.0.0',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAnalysisDialog(BuildContext context) {
    showDialog(context: context, builder: (context) => const _AnalysisDialog());
  }

  Future<void> _showWindowsFoldersDialog(BuildContext context) async {
    final settings = SettingsService.instance;
    final folders = List<String>.from(settings.windowsScanFolders);

    final updated = await showDialog<List<String>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              child: GlassPanel(
                useShader: true,
                backdropBlurSigma: 0,
                borderColor: Colors.white.withValues(alpha: 0.18),
                backgroundColor: kColorGlassBlackTint,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Windows scan folders',
                        style: TextStyle(
                          color: kColorOn,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.maxFinite,
                        child:
                            folders.isEmpty
                                ? const Text(
                                  'No custom folders set.\nUsing default (Music + Downloads).',
                                  style: TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                )
                                : ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: folders.length,
                                  itemBuilder: (context, index) {
                                    final p = folders[index];
                                    return ListTile(
                                      dense: true,
                                      title: Text(
                                        p,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          color: Colors.white54,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            folders.removeAt(index);
                                          });
                                        },
                                      ),
                                    );
                                  },
                                ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          TextButton(
                            onPressed: () {
                              setState(() {
                                folders.clear();
                              });
                            },
                            child: const Text('Use defaults'),
                          ),
                          TextButton(
                            onPressed: () async {
                              final selectedDirectory =
                                  await FilePicker.platform.getDirectoryPath();
                              if (selectedDirectory == null) return;
                              final normalized = selectedDirectory.trim();
                              if (normalized.isEmpty) return;
                              setState(() {
                                if (!folders.contains(normalized)) {
                                  folders.add(normalized);
                                }
                              });
                            },
                            child: const Text('Add folder'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(null),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.of(context).pop(folders),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF8D5524),
                            ),
                            child: const Text(
                              'Save',
                              style: TextStyle(color: Colors.white),
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
        );
      },
    );

    if (updated != null) {
      await settings.setWindowsScanFolders(updated);
    }
  }

  Future<void> _showWindowsExtensionsDialog(BuildContext context) async {
    final settings = SettingsService.instance;
    final controller = TextEditingController(
      text: settings.windowsScanExtensions.join(', '),
    );

    final updated = await showDialog<List<String>>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          child: GlassPanel(
            useShader: true,
            backdropBlurSigma: 0,
            borderColor: Colors.white.withValues(alpha: 0.18),
            backgroundColor: kColorGlassBlackTint,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Windows scan extensions',
                    style: TextStyle(
                      color: kColorOn,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'e.g. mp3, flac, m4a',
                      hintStyle: TextStyle(color: Colors.white54),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF8D5524)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed:
                            () => Navigator.of(
                              context,
                            ).pop(_defaultWindowsExtensions),
                        child: const Text('Reset'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(null),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          final raw = controller.text;
                          final parts =
                              raw
                                  .split(RegExp(r'[^A-Za-z0-9]+'))
                                  .map((e) => e.trim().toLowerCase())
                                  .where((e) => e.isNotEmpty)
                                  .toSet()
                                  .toList();
                          Navigator.of(context).pop(parts);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8D5524),
                        ),
                        child: const Text(
                          'Save',
                          style: TextStyle(color: Colors.white),
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
    );

    if (updated != null) {
      await settings.setWindowsScanExtensions(updated);
    }
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: kSp, left: kSp),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: kTextXs,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
          color: kColorOn2,
        ),
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
      padding: const EdgeInsets.only(bottom: kSp),
      child: GlassPanel(
        borderRadius: BorderRadius.circular(kRadius),
        borderColor: Colors.white.withValues(alpha: 0.15),
        child: Material(
          color: Colors.transparent,
          child: SwitchListTile(
            title: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              subtitle,
              style: TextStyle(
                fontSize: kTextXs,
                color: kColorOn.withValues(alpha: 0.6),
              ),
            ),
            value: value,
            onChanged: onChanged,
            secondary: Icon(icon, color: kColorOn, size: kIconMd),
            activeColor: accentColor,
          ),
        ),
      ),
    );
  }

  Widget _buildColorPicker(SettingsService settings) {
    final colors = [
      0xFF00E5FF, // Coruscant-inspired (cyan metallic)
      0xFF8D5524, // Wood (Classic)
      0xFFFFB300, // Amber
      0xFFD50000, // Crimson
      0xFF00C853, // Emerald
      0xFF6200EA, // Purple
    ];

    return SizedBox(
      height: 50,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: kSp),
        itemCount: colors.length,
        separatorBuilder: (_, __) => const SizedBox(width: kSp * 2),
        itemBuilder: (context, index) {
          final color = Color(colors[index]);
          final isSelected = settings.accentColor == colors[index];

          return GestureDetector(
            onTap: () => settings.setAccentColor(colors[index]),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border:
                    isSelected
                        ? Border.all(color: Colors.white, width: 3)
                        : Border.all(color: Colors.white24, width: 1),
                boxShadow:
                    isSelected
                        ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.5),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ]
                        : null,
              ),
              child:
                  isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                      : null,
            ),
          );
        },
      ),
    );
  }
}

class _AnalysisDialog extends StatefulWidget {
  const _AnalysisDialog();

  @override
  State<_AnalysisDialog> createState() => _AnalysisDialogState();
}

class _AnalysisDialogState extends State<_AnalysisDialog> {
  @override
  void initState() {
    super.initState();
    _startAnalysis();
  }

  Future<void> _startAnalysis() async {
    // Fetch songs first
    final songs =
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
            ? await WindowsAudioQuery.instance.querySongs()
            : await OnAudioQuery().querySongs();
    if (!mounted) return;
    SonicDnaService.instance.analyzeLibrary(songs);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: GlassPanel(
        useShader: true,
        backdropBlurSigma: 0,
        borderColor: Colors.white.withValues(alpha: 0.18),
        backgroundColor: kColorGlassBlackTint,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: StreamBuilder<double>(
            stream: SonicDnaService.instance.progressStream,
            initialData: 0.0,
            builder: (context, snapshot) {
              final progress = snapshot.data ?? 0.0;
              final isDone = progress >= 1.0;

              if (isDone) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Analyzing Library',
                      style: TextStyle(
                        color: kColorOn,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Icon(
                      PhosphorIconsBold.checkCircle,
                      color: Color(0xFF8D5524),
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Analysis Complete!',
                      style: TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'BPM/Key extracted when available in file tags.',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8D5524),
                      ),
                      child: const Text(
                        'Close',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Analyzing Library',
                    style: TextStyle(
                      color: kColorOn,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white10,
                    color: const Color(0xFF8D5524),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${(progress * 100).toInt()}%',
                    style: const TextStyle(color: Colors.white54),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Extracting BPM/Key from audio tags...',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
