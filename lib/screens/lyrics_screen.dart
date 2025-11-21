// lib/screens/lyrics_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_lyric/lyrics_reader.dart';
import '../ui/tokens.dart';
import '../repositories/song_repository.dart';

class LyricsScreen extends StatefulWidget {
  final String songId;
  final String songTitle;
  final Duration Function() getCurrentPosition;
  final Stream<Duration> positionStream;

  const LyricsScreen({
    super.key,
    required this.songId,
    required this.songTitle,
    required this.getCurrentPosition,
    required this.positionStream,
  });

  @override
  State<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends State<LyricsScreen> with TickerProviderStateMixin {
  final _repo = SongRepository.instance;
  dynamic _lyricsModel;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLyrics();
  }

  Future<void> _loadLyrics() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final meta = await _repo.getMetadata(widget.songId);
      final lyricsText = meta?.lyrics;

      if (lyricsText == null || lyricsText.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'No lyrics available for this song';
        });
        return;
      }

      // Parse LRC format or plain text
      final model = LyricsModelBuilder.create()
          .bindLyricToMain(lyricsText)
          .getModel();

      setState(() {
        _lyricsModel = model;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load lyrics: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06070A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(widget.songTitle),
        actions: [
          if (_lyricsModel != null)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => _showEditDialog(),
              tooltip: 'Edit Lyrics',
            ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: _lyricsModel == null && !_loading
          ? FloatingActionButton.extended(
              onPressed: () => _showAddLyricsDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Add Lyrics'),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lyrics_outlined, size: 64, color: Colors.white24),
            const SizedBox(height: kSp * 2),
            Text(
              _error!,
              style: const TextStyle(color: Colors.white54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_lyricsModel == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lyrics_outlined, size: 64, color: Colors.white24),
            SizedBox(height: kSp * 2),
            Text(
              'No lyrics available',
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<Duration>(
      stream: widget.positionStream,
      builder: (context, snapshot) {
        return LyricsReader(
          padding: const EdgeInsets.symmetric(horizontal: kSp * 3, vertical: kSp * 2),
          model: _lyricsModel,
          position: snapshot.data?.inMilliseconds ?? 0,
          lyricUi: UINetease(
            highlight: true,
            defaultSize: 18,
            defaultExtSize: 16,
            otherMainSize: 16,
            bias: 0.3,
            lineGap: 16,
            inlineGap: 12,
          ),
          playing: true,
          emptyBuilder: () => const Center(
            child: Text(
              'No lyrics text available',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          selectLineBuilder: (progress, confirm) {
            return Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          const Color(0xFFFF4D4D).withValues(alpha: 0.3),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    height: 2,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showAddLyricsDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Lyrics'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Paste lyrics in LRC format or plain text:',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 10,
              decoration: const InputDecoration(
                hintText: '[00:12.00] First line of lyrics\n[00:15.00] Second line...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      await _repo.saveLyrics(widget.songId, result, source: 'manual');
      _loadLyrics();
    }
  }

  Future<void> _showEditDialog() async {
    final meta = await _repo.getMetadata(widget.songId);
    final controller = TextEditingController(text: meta?.lyrics ?? '');
    
    if (!mounted) return;
    
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Lyrics'),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 15,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      await _repo.saveLyrics(widget.songId, result, source: 'manual');
      _loadLyrics();
    }
  }
}
