// lib/screens/playlists_screen.dart
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../ui/tokens.dart';
import '../models/playlist.dart';
import '../repositories/playlist_repository.dart';
import 'smart_playlist_screen.dart';
import 'playlist_detail_screen.dart';

class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  final _repo = PlaylistRepository.instance;
  List<Playlist> _playlists = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    setState(() => _loading = true);
    _playlists = await _repo.getAll();
    if (mounted) setState(() => _loading = false);
  }

  void _createPlaylist() {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Playlist'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: descController,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) return;
              await _repo.create(
                nameController.text.trim(),
                description: descController.text.trim().isEmpty ? null : descController.text.trim(),
              );
              if (context.mounted) {
                Navigator.pop(context);
                _loadPlaylists();
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _deletePlaylist(Playlist playlist) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Playlist'),
        content: Text('Delete "${playlist.name}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      await _repo.delete(playlist.id);
      _loadPlaylists();
    }
  }

  Widget _buildSmartTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required SmartPlaylistType type,
  }) {
    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withValues(alpha: 0.2), Colors.transparent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(color: kColorOn, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(color: kColorOn2, fontSize: 12)),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SmartPlaylistScreen(type: type)),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlists'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPlaylists,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // Smart Playlists Section
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Smart Playlists',
                    style: TextStyle(
                      color: kColorAppAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                _buildSmartTile(
                  icon: PhosphorIconsFill.fire,
                  title: 'Heavy Rotation',
                  subtitle: 'Your most played tracks',
                  color: Colors.orangeAccent,
                  type: SmartPlaylistType.heavyRotation,
                ),
                _buildSmartTile(
                  icon: PhosphorIconsFill.clockCounterClockwise,
                  title: 'Recently Added',
                  subtitle: 'Fresh tunes',
                  color: Colors.blueAccent,
                  type: SmartPlaylistType.recentlyAdded,
                ),
                _buildSmartTile(
                  icon: PhosphorIconsFill.archive,
                  title: 'Forgotten Favorites',
                  subtitle: 'Rediscover old gems',
                  color: Colors.purpleAccent,
                  type: SmartPlaylistType.forgottenFavorites,
                ),
                
                const Divider(color: Colors.white10, height: 32),

                // User Playlists Section
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Your Playlists',
                    style: TextStyle(
                      color: kColorAppAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                if (_playlists.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Column(
                      children: [
                        Icon(Icons.queue_music, size: 48, color: Colors.white24),
                        SizedBox(height: 16),
                        Text('No custom playlists yet', style: TextStyle(color: Colors.white54)),
                      ],
                    ),
                  )
                else
                  ..._playlists.map((p) => ListTile(
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: kColorCard,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '${p.songCount}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    title: Text(p.name, style: const TextStyle(color: kColorOn)),
                    subtitle: Text(
                      p.description?.isNotEmpty == true ? p.description! : '${p.songCount} songs',
                      style: const TextStyle(color: kColorOn2),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: kColorOn2),
                      onPressed: () => _deletePlaylist(p),
                    ),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PlaylistDetailScreen(playlist: p),
                        ),
                      );
                      _loadPlaylists(); // Refresh count on return
                    },
                  )),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createPlaylist,
        child: const Icon(Icons.add),
      ),
    );
  }
}
