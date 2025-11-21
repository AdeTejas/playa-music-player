import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:on_audio_query/on_audio_query.dart';
import '../services/settings_service.dart';
import '../services/sonic_dna_service.dart';
import '../ui/tokens.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
            padding: const EdgeInsets.all(kSp * 2),
            children: [
              _buildSectionHeader('Sonic DNA'),
              Card(
                margin: const EdgeInsets.only(bottom: kSp),
                color: const Color(0xFF1B1F26).withValues(alpha: 0.8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
                child: ListTile(
                  leading: const Icon(PhosphorIconsBold.dna, color: Color(0xFFE8DCCA)),
                  title: const Text('Analyze Library', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Detect BPM and Key for all songs', style: TextStyle(fontSize: 12, color: Colors.white54)),
                  trailing: const Icon(PhosphorIconsBold.caretRight, color: Color(0xFFE8DCCA)),
                  onTap: () => _showAnalysisDialog(context),
                ),
              ),
              const SizedBox(height: kSp * 2),

              _buildSectionHeader('Appearance'),
              _buildSwitchTile(
                title: 'Space Background',
                subtitle: 'Show animated stars and nebula',
                value: settings.showSpaceBackground,
                onChanged: settings.batterySaver ? null : settings.setShowSpaceBackground,
                icon: PhosphorIconsBold.planet,
              ),
              _buildSwitchTile(
                title: 'High Quality Blur',
                subtitle: 'Enable glassmorphism effects',
                value: settings.highQualityBlur,
                onChanged: settings.batterySaver ? null : settings.setHighQualityBlur,
                icon: PhosphorIconsBold.drop,
              ),
              _buildSwitchTile(
                title: 'Show Waveforms',
                subtitle: 'Display audio visualization',
                value: settings.showWaveforms,
                onChanged: settings.setShowWaveforms,
                icon: PhosphorIconsBold.waves,
              ),
              
              const SizedBox(height: kSp),
              const Padding(
                padding: EdgeInsets.only(left: kSp, bottom: kSp),
                child: Text('Accent Color', style: TextStyle(fontSize: 12, color: Colors.white54)),
              ),
              _buildColorPicker(settings),
              const SizedBox(height: kSp * 2),

              _buildSectionHeader('Library'),
              ListTile(
                title: const Text('Default Sort'),
                subtitle: Text(
                  settings.librarySortType == 'DATE_ADDED' ? 'Date Added (Newest)' :
                  settings.librarySortType == 'TITLE' ? 'Title (A-Z)' :
                  settings.librarySortType == 'ARTIST' ? 'Artist (A-Z)' : 'Album (A-Z)',
                  style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
                ),
                leading: const Icon(PhosphorIconsBold.sortAscending, color: Color(0xFFE8DCCA)),
                trailing: DropdownButton<String>(
                  value: settings.librarySortType,
                  dropdownColor: const Color(0xFF1B1F26),
                  underline: const SizedBox(),
                  style: const TextStyle(color: Colors.white),
                  icon: const Icon(PhosphorIconsBold.caretDown, color: Color(0xFFE8DCCA), size: 16),
                  items: const [
                    DropdownMenuItem(value: 'DATE_ADDED', child: Text('Date Added')),
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
              const SizedBox(height: kSp * 2),
              
              _buildSectionHeader('Playback'),
              _buildSwitchTile(
                title: 'Keep Screen On',
                subtitle: 'Prevent screen from sleeping while app is open',
                value: settings.keepScreenOn,
                onChanged: settings.setKeepScreenOn,
                icon: PhosphorIconsBold.sun,
              ),
              ListTile(
                title: const Text('Audio Focus'),
                subtitle: Text(
                  settings.audioFocusMode == 'pause' ? 'Pause on interruption' :
                  settings.audioFocusMode == 'duck' ? 'Lower volume on interruption' : 'Ignore interruptions'
                ),
                leading: Icon(PhosphorIconsBold.speakerHigh, color: Theme.of(context).colorScheme.onSurface),
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
              _buildSectionHeader('Power'),
              _buildSwitchTile(
                title: 'Battery Saver',
                subtitle: 'Disable animations and blur to save power',
                value: settings.batterySaver,
                onChanged: settings.setBatterySaver,
                icon: PhosphorIconsBold.batteryCharging,
              ),
              
              const SizedBox(height: kSp * 4),
              Center(
                child: Text(
                  'Playa v1.0.0',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                    fontSize: 12,
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
    showDialog(
      context: context,
      builder: (context) => const _AnalysisDialog(),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: kSp, left: kSp),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
          color: Color(0xFFA68B6C), // Muted wood
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
    required IconData icon,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: kSp),
      color: const Color(0xFF1B1F26).withValues(alpha: 0.8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(kRadius)),
      child: SwitchListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6))),
        value: value,
        onChanged: onChanged,
        secondary: Icon(icon, color: const Color(0xFFE8DCCA)),
        activeColor: const Color(0xFF8D5524),
      ),
    );
  }

  Widget _buildColorPicker(SettingsService settings) {
    final colors = [
      0xFF8D5524, // Wood (Default)
      0xFF00E5FF, // Cyan
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
                border: isSelected 
                    ? Border.all(color: Colors.white, width: 3)
                    : Border.all(color: Colors.white24, width: 1),
                boxShadow: isSelected ? [
                  BoxShadow(color: color.withOpacity(0.5), blurRadius: 8, spreadRadius: 2)
                ] : null,
              ),
              child: isSelected 
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
    final songs = await OnAudioQuery().querySongs();
    if (!mounted) return;
    SonicDnaService.instance.analyzeLibrary(songs);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF14161B),
      title: const Text('Analyzing Library', style: TextStyle(color: Color(0xFFE8DCCA))),
      content: StreamBuilder<double>(
        stream: SonicDnaService.instance.progressStream,
        initialData: 0.0,
        builder: (context, snapshot) {
          final progress = snapshot.data ?? 0.0;
          final isDone = progress >= 1.0;
          
          if (isDone) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(PhosphorIconsBold.checkCircle, color: Color(0xFF8D5524), size: 48),
                const SizedBox(height: 16),
                const Text('Analysis Complete!', style: TextStyle(color: Colors.white)),
                const SizedBox(height: 8),
                const Text('BPM and Key data has been generated.', style: TextStyle(color: Colors.white54, fontSize: 12)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8D5524)),
                  child: const Text('Close', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white10,
                color: const Color(0xFF8D5524),
              ),
              const SizedBox(height: 16),
              Text(
                '${(progress * 100).toInt()}%',
                style: const TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 8),
              const Text(
                'Calculating BPM & Key...',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          );
        },
      ),
    );
  }
}
