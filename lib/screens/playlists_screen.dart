// lib/screens/playlists_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../design/design_system.dart';
import '../models/playlist.dart';
import '../repositories/playlist_repository.dart';
import 'smart_playlist_screen.dart';
import '../utils/smart_playlist_catalog.dart';
import '../services/settings_service.dart';
import 'playlist_detail_screen.dart';

class PlaylistsScreen extends StatefulWidget {
  final bool isVisible;

  const PlaylistsScreen({super.key, this.isVisible = true});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  final _repo = PlaylistRepository.instance;
  List<Playlist> _playlists = [];
  bool _loading = true;
  bool _smartReorder = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVisible) _loadPlaylists();
  }

  @override
  void didUpdateWidget(PlaylistsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadPlaylists();
    }
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
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            child: RichMatteTexture(
              borderRadius: BorderRadius.circular(PlayaRadii.lg),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PlayaSectionHeader(title: 'Create Playlist', showDivider: false),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: PlayaColors.onSurface),
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        labelStyle: TextStyle(color: PlayaColors.onSurfaceVariant),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: PlayaColors.borderSubtle)),
                      ),
                      autofocus: true,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descController,
                      style: const TextStyle(color: PlayaColors.onSurface),
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        labelStyle: TextStyle(color: PlayaColors.onSurfaceVariant),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: PlayaColors.borderSubtle)),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel', style: TextStyle(color: PlayaColors.onSurfaceVariant)),
                        ),
                        const SizedBox(width: 8),
                        PlayaButton(
                          label: 'Create',
                          onPressed: () async {
                            if (nameController.text.trim().isEmpty) return;
                            await _repo.create(
                              nameController.text.trim(),
                              description:
                                  descController.text.trim().isEmpty
                                      ? null
                                      : descController.text.trim(),
                            );
                            if (context.mounted) {
                              Navigator.pop(context);
                              _loadPlaylists();
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  void _deletePlaylist(Playlist playlist) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (context) => Dialog(
            backgroundColor: Colors.transparent,
            child: GlassPanel(
              useStrongVariant: true,
              borderRadius: BorderRadius.circular(PlayaRadii.lg),
              borderColor: PlayaColors.border,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Delete Playlist',
                    style: TextStyle(
                      color: PlayaColors.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Delete "${playlist.name}"? This action cannot be undone.',
                    style: const TextStyle(color: PlayaColors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text(
                          'Delete',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
    );

    if (confirm == true) {
      await _repo.delete(playlist.id);
      _loadPlaylists();
    }
  }

  Widget _buildSmartTile({
    required SmartPlaylistInfo info,
    required bool pinned,
    required bool reorderMode,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: GlassPanel(
        useShader: false,
        borderRadius: BorderRadius.circular(14),
        borderColor: PlayaColors.border,
        child: Material(
          color: Colors.transparent,
          child: ListTile(
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    info.color.withValues(alpha: 0.2),
                    Colors.transparent,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: info.color.withValues(alpha: 0.3)),
              ),
              child: Icon(info.icon, color: info.color),
            ),
            title: Text(
              info.title,
              style: const TextStyle(
                color: PlayaColors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              info.subtitle,
              style: const TextStyle(
                color: PlayaColors.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: pinned ? 'Unpin' : 'Pin to Library',
                  icon: Icon(
                    pinned
                        ? PhosphorIconsFill.pushPin
                        : PhosphorIconsRegular.pushPin,
                    color: pinned
                        ? Theme.of(context).colorScheme.primary
                        : PlayaColors.onSurfaceVariant,
                  ),
                  onPressed: () async {
                    HapticFeedback.selectionClick();
                    await SettingsService.instance
                        .toggleSmartPlaylistPinned(info.id);
                    if (mounted) setState(() {});
                  },
                ),
                if (reorderMode)
                  const Icon(
                    PhosphorIconsRegular.dotsSixVertical,
                    color: PlayaColors.onSurfaceVariant,
                  ),
              ],
            ),
            onTap: reorderMode
                ? null
                : () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SmartPlaylistScreen(type: info.type),
                      ),
                    );
                  },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PlayaAppBar(
        title: 'Playlists',
        actions: [
          IconButton(
            tooltip: 'Refresh playlists',
            icon: const Icon(PhosphorIconsRegular.arrowClockwise),
            onPressed: () {
              HapticFeedback.selectionClick();
              _loadPlaylists();
            },
          ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                padding: const EdgeInsets.symmetric(horizontal: PlayaSpacing.xs),
                children: [
                  // Smart Playlists Section (pin + reorder with persistence)
                  AnimatedBuilder(
                    animation: SettingsService.instance,
                    builder: (context, _) {
                      final settings = SettingsService.instance;
                      final ordered = orderedSmartPlaylists(
                        settings.smartPlaylistOrder,
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: PlayaSectionHeader(
                                  title: 'Smart Playlists',
                                ),
                              ),
                              IconButton(
                                tooltip: _smartReorder
                                    ? 'Done reordering'
                                    : 'Reorder smart playlists',
                                icon: Icon(
                                  _smartReorder
                                      ? PhosphorIconsRegular.check
                                      : PhosphorIconsRegular.list,
                                ),
                                onPressed: () {
                                  HapticFeedback.selectionClick();
                                  setState(
                                    () => _smartReorder = !_smartReorder,
                                  );
                                },
                              ),
                            ],
                          ),
                          if (_smartReorder)
                            ReorderableListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: ordered.length,
                              onReorder: (oldIndex, newIndex) async {
                                if (newIndex > oldIndex) newIndex -= 1;
                                final ids = ordered.map((e) => e.id).toList();
                                final item = ids.removeAt(oldIndex);
                                ids.insert(newIndex, item);
                                await settings.setSmartPlaylistOrder(ids);
                                if (mounted) setState(() {});
                              },
                              itemBuilder: (context, index) {
                                final info = ordered[index];
                                return Container(
                                  key: ValueKey(info.id),
                                  child: _buildSmartTile(
                                    info: info,
                                    pinned: settings.isSmartPlaylistPinned(
                                      info.id,
                                    ),
                                    reorderMode: true,
                                  ),
                                );
                              },
                            )
                          else
                            ...ordered.map(
                              (info) => _buildSmartTile(
                                info: info,
                                pinned: settings.isSmartPlaylistPinned(info.id),
                                reorderMode: false,
                              ),
                            ),
                        ],
                      );
                    },
                  ),

                  const SizedBox(height: PlayaSpacing.md),

                  // User Playlists Section
                  const PlayaSectionHeader(title: 'User Playlists'),
                  if (_playlists.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Column(
                        children: [
                          Icon(
                            PhosphorIconsRegular.musicNotesPlus,
                            size: 48,
                            color: PlayaColors.onSurfaceVariant,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'No custom playlists yet',
                            style: TextStyle(color: PlayaColors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._playlists.map(
                      (p) => Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: PlayaCard(
                          useStrongVariant: true,
                          useMatteVariant: true,
                          padding: EdgeInsets.zero,
                          borderRadius: BorderRadius.circular(PlayaRadii.sm),
                          child: ListTile(
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: PlayaColors.surfaceVariant,
                                borderRadius: BorderRadius.circular(PlayaRadii.xs),
                                border: Border.all(
                                  color: PlayaColors.borderSubtle,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  '${p.songCount}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                            title: Text(
                              p.name,
                              style: const TextStyle(color: PlayaColors.onSurface, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              p.description?.isNotEmpty == true
                                  ? p.description!
                                  : '${p.songCount} songs',
                              style: const TextStyle(color: PlayaColors.onSurfaceVariant, fontSize: 11),
                            ),
                            trailing: IconButton(
                              tooltip: 'Delete playlist',
                              icon: const Icon(
                                PhosphorIconsRegular.trash,
                                color: PlayaColors.onSurfaceVariant,
                                size: 20,
                              ),
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                _deletePlaylist(p);
                              },
                            ),
                            onTap: () async {
                              HapticFeedback.selectionClick();
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder:
                                      (_) =>
                                          PlaylistDetailScreen(playlist: p),
                                ),
                              );
                              _loadPlaylists(); // Refresh count on return
                            },
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 80),
                ],
              ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          HapticFeedback.mediumImpact();
          _createPlaylist();
        },
        backgroundColor: accentColor,
        child: const Icon(PhosphorIconsBold.plus, color: Colors.black),
      ),
    );
  }
}
