import 'package:flutter/material.dart';
import 'package:flutter_lyric/lyrics_reader.dart';
import '../services/player_controller.dart';
import '../services/lyrics_service.dart';


class LyricsSheet extends StatefulWidget {
  final PlayerController ctrl;
  const LyricsSheet({required this.ctrl, super.key});

  @override
  State<LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends State<LyricsSheet> {
  dynamic _lyricModel;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadLyrics();
  }

  Future<void> _loadLyrics() async {
    final item = widget.ctrl.currentMediaItem;
    if (item == null) {
      setState(() => _loading = false);
      return;
    }

    final lrc = await LyricsService.instance.getLyrics(
      item.artist ?? '',
      item.title,
      duration: item.duration,
    );
    if (lrc != null) {
      _lyricModel = LyricsModelBuilder.create()
          .bindLyricToMain(lrc)
          .getModel();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF14161B),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Lyrics',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFFE8DCCA),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _lyricModel == null
                    ? const Center(child: Text('No lyrics found', style: TextStyle(color: Colors.white54)))
                    : StreamBuilder<Duration>(
                        stream: widget.ctrl.player.positionStream,
                        builder: (context, snapshot) {
                          final pos = snapshot.data?.inMilliseconds ?? 0;
                          return StreamBuilder<bool>(
                            stream: widget.ctrl.player.playingStream,
                            builder: (context, playSnap) {
                              final playing = playSnap.data ?? false;
                              return LyricsReader(
                                model: _lyricModel,
                                position: pos,
                                lyricUi: UINetease(
                                  highlight: true,
                                  defaultSize: 18,
                                  defaultExtSize: 14,
                                  otherMainSize: 16,
                                  bias: 0.5,
                                  lineGap: 25,
                                  inlineGap: 25,
                                  lyricAlign: LyricAlign.CENTER,
                                  lyricBaseLine: LyricBaseLine.CENTER,
                                ),
                                playing: playing,
                                size: Size(double.infinity, MediaQuery.of(context).size.height * 0.6),
                                emptyBuilder: () => const Center(child: Text("No lyrics")),
                              );
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
