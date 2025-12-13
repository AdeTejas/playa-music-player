import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/database_service.dart';
import '../services/library_scan_service.dart';
import '../services/perf_metrics_service.dart';
import '../services/player_controller.dart';
import '../ui/glass_panel.dart';
import '../ui/tokens.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  PermissionStatus? _storage;
  PermissionStatus? _audio;

  @override
  void initState() {
    super.initState();
    _refreshPermissions();
  }

  Future<void> _refreshPermissions() async {
    try {
      final storage = await Permission.storage.status;
      final audio = await Permission.audio.status;
      if (!mounted) return;
      setState(() {
        _storage = storage;
        _audio = audio;
      });
    } catch (_) {
      // Ignore; some platforms don't expose these permissions.
    }
  }

  String _buildDiagnosticsText() {
    final db = DatabaseService.instance;
    final scan = LibraryScanService.instance;
    final perf = PerfMetricsService.instance;
    final player = PlayerController.ensure();

    return [
      'Playa Diagnostics',
      'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      '',
      'Database:',
      '  initialized: ${db.isInitialized}',
      '  path: ${db.dbPath ?? '-'}',
      '',
      'Performance:',
      '  appStartAt: ${perf.appStartAt?.toIso8601String() ?? '-'}',
      '  coldStartToFirstFrameMs: ${perf.coldStartToFirstFrame?.inMilliseconds ?? '-'}',
      '  lastScanDurationMs: ${scan.lastScanDuration?.inMilliseconds ?? '-'}',
      '',
      'LibraryScan:',
      '  phase: ${scan.phase.name}',
      '  progress: ${(scan.progress * 100).toStringAsFixed(0)}%',
      '  lastScanAt: ${scan.lastScanAt?.toIso8601String() ?? '-'}',
      '  lastSongCount: ${scan.lastSongCount}',
      '  lastError: ${scan.lastError ?? '-'}',
      '',
      'Permissions:',
      '  storage: ${_storage?.toString() ?? (Platform.isAndroid ? 'Unknown' : 'N/A')}',
      '  audio: ${_audio?.toString() ?? (Platform.isAndroid ? 'Unknown' : 'N/A')}',
      '',
      'Playback:',
      '  nowPlaying: ${player.currentMediaItem?.title ?? '-'}',
      '  androidAudioSessionId: ${Platform.isAndroid ? (player.player.androidAudioSessionId ?? 0) : 'N/A'}',
      '  lastPlaybackErrorAt: ${player.lastPlaybackErrorAt?.toIso8601String() ?? '-'}',
      '  lastPlaybackError: ${player.lastPlaybackError ?? '-'}',
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final db = DatabaseService.instance;
    final perf = PerfMetricsService.instance;
    final player = PlayerController.ensure();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Diagnostics'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final text = _buildDiagnosticsText();
              await Clipboard.setData(ClipboardData(text: text));
              if (!mounted) return;
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Diagnostics copied to clipboard'),
                ),
              );
            },
            icon: const Icon(Icons.copy),
            tooltip: 'Copy',
          ),
          IconButton(
            onPressed: _refreshPermissions,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: LibraryScanService.instance,
        builder: (context, _) {
          final scan = LibraryScanService.instance;

          return ListView(
            padding: const EdgeInsets.all(kSp * 2),
            children: [
              _section('Database'),
              _card(
                ListTile(
                  title: const Text('SQLite'),
                  subtitle: Text(
                    db.isInitialized
                        ? 'Initialized\n${db.dbPath ?? ''}'
                        : 'Not initialized',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: kSp * 2),
              _section('Performance'),
              _card(
                ListTile(
                  title: const Text('Metrics'),
                  subtitle: Text(
                    'App start: ${perf.appStartAt?.toIso8601String() ?? '-'}\n'
                    'Cold start to first frame: ${perf.coldStartToFirstFrame?.inMilliseconds ?? '-'} ms\n'
                    'Last scan duration: ${scan.lastScanDuration?.inMilliseconds ?? '-'} ms',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: kSp * 2),
              _section('Library Scan'),
              _card(
                Column(
                  children: [
                    ListTile(
                      title: const Text('Status'),
                      subtitle: Text(
                        'Phase: ${scan.phase.name}\n'
                        'Progress: ${(scan.progress * 100).toStringAsFixed(0)}%\n'
                        'Last scan: ${scan.lastScanAt?.toIso8601String() ?? '-'}\n'
                        'Last count: ${scan.lastSongCount}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    if (scan.isScanning)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          kSp * 2,
                          0,
                          kSp * 2,
                          kSp * 2,
                        ),
                        child: LinearProgressIndicator(
                          value: scan.progress,
                          backgroundColor: Colors.white10,
                          color: const Color(0xFF8D5524),
                        ),
                      ),
                    if (scan.lastError != null)
                      ListTile(
                        title: const Text('Last error'),
                        subtitle: Text(
                          scan.lastError!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: kSp * 2),
              _section('Permissions'),
              _card(
                Column(
                  children: [
                    ListTile(
                      title: const Text('Storage'),
                      subtitle: Text(
                        _storage?.toString() ??
                            (Platform.isAndroid ? 'Unknown' : 'N/A'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    ListTile(
                      title: const Text('Audio'),
                      subtitle: Text(
                        _audio?.toString() ??
                            (Platform.isAndroid ? 'Unknown' : 'N/A'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: kSp * 2),
              _section('Playback'),
              _card(
                Column(
                  children: [
                    ListTile(
                      title: const Text('Audio session'),
                      subtitle: Text(
                        Platform.isAndroid
                            ? 'androidAudioSessionId: ${player.player.androidAudioSessionId ?? 0}'
                            : 'N/A',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    ListTile(
                      title: const Text('Now playing'),
                      subtitle: Text(
                        player.currentMediaItem?.title ?? '-',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    if (player.lastPlaybackError != null)
                      ListTile(
                        title: const Text('Last playback error'),
                        subtitle: Text(
                          '${player.lastPlaybackErrorAt?.toIso8601String() ?? ''}\n${player.lastPlaybackError}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white54,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: kSp * 4),
              Center(
                child: Text(
                  'Long-press app version to open this screen.',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.5),
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

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: kSp, left: kSp),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
          color: Color(0xFFA68B6C),
        ),
      ),
    );
  }

  Widget _card(Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: kSp),
      child: GlassPanel(
        borderRadius: BorderRadius.circular(kRadius),
        borderColor: Colors.white.withValues(alpha: 0.15),
        child: child,
      ),
    );
  }
}
