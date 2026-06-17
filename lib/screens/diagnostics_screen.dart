import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../design/design_system.dart';
import '../services/analytics_service.dart';
import '../services/database_service.dart';
import '../services/settings_service.dart';
import '../services/library_scan_service.dart';
import '../services/perf_metrics_service.dart';
import '../services/service_locator.dart';
import '../utils/resume_soak_check.dart';

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  PermissionStatus? _storage;
  PermissionStatus? _audio;
  ResumeSoakReport? _soakReport;
  bool _soakRunning = false;

  @override
  void initState() {
    super.initState();
    _refreshPermissions();
  }

  Future<void> _refreshPermissions() async {
    try {
      PermissionStatus? storage;
      PermissionStatus? audio;

      if (Platform.isAndroid) {
        audio = await Permission.audio.status;
        final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
        if (sdk < 33) {
          storage = await Permission.storage.status;
        }
      } else if (Platform.isIOS) {
        audio = await Permission.audio.status;
      }

      if (!mounted) return;
      setState(() {
        _storage = storage;
        _audio = audio;
      });
    } catch (_) {
      // Ignore; some platforms don't expose these permissions.
    }
  }

  Future<void> _runResumeSoak() async {
    if (_soakRunning) return;
    setState(() => _soakRunning = true);
    try {
      final player = ServiceLocator.instance.playerController;
      final report = await ResumeSoakCheck.runAll(
        ctrl: player,
        library: player.librarySongs,
      );
      if (!mounted) return;
      setState(() => _soakReport = report);
    } finally {
      if (mounted) setState(() => _soakRunning = false);
    }
  }

  String _buildDiagnosticsText() {
    final db = DatabaseService.instance;
    final scan = LibraryScanService.instance;
    final perf = PerfMetricsService.instance;
    final player = ServiceLocator.instance.playerController;
    final analytics = AnalyticsService.instance;

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
      '  storage: ${_storage?.toString() ?? (Platform.isAndroid ? 'N/A (API 33+)' : 'N/A')}',
      '  audio: ${_audio?.toString() ?? (Platform.isAndroid ? 'Unknown' : 'N/A')}',
      '',
      'Playback:',
      '  nowPlaying: ${player.currentMediaItem?.title ?? '-'}',
      '  bookmarkKey: ${player.activeBookmarkKey.isEmpty ? '-' : player.activeBookmarkKey}',
      '  bookmarkCount: ${player.bookmarks.length}',
      '  lastBookmarkError: ${player.lastBookmarkError.isEmpty ? '-' : player.lastBookmarkError}',
      '  contentMode: ${player.currentContentMode.name}',
      '  libraryBrowseFilter: ${SettingsService.instance.libraryBrowseFilter.label}',
      '  androidAudioSessionId: ${Platform.isAndroid ? (player.player.androidAudioSessionId ?? 0) : 'N/A'}',
      '  lastPlaybackErrorAt: ${player.lastPlaybackErrorAt?.toIso8601String() ?? '-'}',
      '  lastPlaybackError: ${player.lastPlaybackError ?? '-'}',
      '',
      'Analytics:',
      '  errorReports: ${analytics.getErrors().length}',
      if (_soakReport != null) ...[
        '',
        'Resume soak:',
        _soakReport!.summary,
      ],
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final db = DatabaseService.instance;
    final perf = PerfMetricsService.instance;
    final player = ServiceLocator.instance.playerController;

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
            padding: const EdgeInsets.all(PlayaSpacing.md),
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
                      color: PlayaColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: PlayaSpacing.md),
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
                      color: PlayaColors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: PlayaSpacing.md),
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
                          color: PlayaColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (scan.isScanning)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          PlayaSpacing.md,
                          0,
                          PlayaSpacing.md,
                          PlayaSpacing.md,
                        ),
                        child: LinearProgressIndicator(
                          value: scan.progress,
                          backgroundColor: PlayaColors.trackMuted,
                          color: PlayaColors.sonic,
                        ),
                      ),
                    if (scan.lastError != null)
                      ListTile(
                        title: const Text('Last error'),
                        subtitle: Text(
                          scan.lastError!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: PlayaColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: PlayaSpacing.md),
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
                          color: PlayaColors.onSurfaceVariant,
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
                          color: PlayaColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: PlayaSpacing.md),
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
                          color: PlayaColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                    ListTile(
                      title: const Text('Now playing'),
                      subtitle: Text(
                        player.currentMediaItem?.title ?? '-',
                        style: TextStyle(
                          fontSize: 12,
                          color: PlayaColors.onSurfaceVariant,
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
                            color: PlayaColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: PlayaSpacing.md),
              _section('Resume soak'),
              _card(
                Column(
                  children: [
                    ListTile(
                      title: const Text('Multi-chapter resume validation'),
                      subtitle: Text(
                        _soakReport == null
                            ? 'Run synthetic + live checks against recent listening.'
                            : '${_soakReport!.passed} passed, ${_soakReport!.failed} failed',
                        style: TextStyle(
                          fontSize: 12,
                          color: PlayaColors.onSurfaceVariant,
                        ),
                      ),
                      trailing: _soakRunning
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : IconButton(
                              onPressed: _runResumeSoak,
                              icon: const Icon(Icons.play_arrow),
                              tooltip: 'Run checks',
                            ),
                    ),
                    if (_soakReport != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          PlayaSpacing.md,
                          0,
                          PlayaSpacing.md,
                          PlayaSpacing.md,
                        ),
                        child: SelectableText(
                          _soakReport!.summary,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: _soakReport!.ok
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: PlayaSpacing.md),
              _section('Analytics'),
              _card(
                ListTile(
                  title: const Text('Error reports'),
                  subtitle: Text(
                    '${AnalyticsService.instance.getErrors().length} logged this session',
                    style: TextStyle(
                      fontSize: 12,
                      color: PlayaColors.onSurfaceVariant,
                    ),
                  ),
                  trailing: AnalyticsService.instance.getErrors().isNotEmpty
                      ? IconButton(
                          onPressed: () async {
                            await AnalyticsService.instance.clearErrors();
                            if (!mounted) return;
                            setState(() {});
                          },
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Clear errors',
                        )
                      : null,
                ),
              ),

              const SizedBox(height: PlayaSpacing.xl),
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
      padding: const EdgeInsets.only(
        bottom: PlayaSpacing.xs,
        left: PlayaSpacing.xs,
      ),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
          color: PlayaColors.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _card(Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: PlayaSpacing.xs),
      child: GlassPanel(
        borderRadius: BorderRadius.circular(PlayaRadii.kRadius),
        borderColor: PlayaColors.border,
        child: child,
      ),
    );
  }
}
