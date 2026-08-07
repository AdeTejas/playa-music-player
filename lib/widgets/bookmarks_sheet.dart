import 'package:flutter/material.dart';

import '../design/design_system.dart';
import '../services/player_controller.dart';
import '../utils/ui_utils.dart';

class BookmarksSheet extends StatelessWidget {
  final PlayerController ctrl;
  const BookmarksSheet({super.key, required this.ctrl});

  Future<void> _editBookmarkNote(
    BuildContext context, {
    required int index,
    required String initial,
  }) async {
    final controller = TextEditingController(text: initial);
    final accent = Theme.of(context).colorScheme.primary;

    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: PlayaColors.surface,
          title: const Text('Edit Bookmark'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Note (optional)...',
              hintStyle: const TextStyle(color: Colors.white38),
              enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: PlayaColors.onSurfaceVariant),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: accent),
              ),
            ),
            style: const TextStyle(color: PlayaColors.onSurface),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'Cancel',
                style: TextStyle(color: PlayaColors.onSurfaceVariant),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: Text('Save', style: TextStyle(color: accent)),
            ),
          ],
        );
      },
    );

    if (saved == null) return;
    await ctrl.updateBookmarkNote(index, saved);
    if (!context.mounted) return;
    showToast(context, 'Bookmark updated');
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return GlassPanel(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      borderColor: Colors.white.withValues(alpha: 0.14),
      backgroundColor: PlayaColors.glass,
      child: SizedBox(
        height: 400,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Bookmarks',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<List<Map<String, dynamic>>>(
                valueListenable: ctrl.bookmarksNotifier,
                builder: (context, bookmarks, _) {
                  if (bookmarks.isEmpty) {
                    return const Center(
                      child: Text(
                        'No bookmarks yet',
                        style: TextStyle(color: PlayaColors.onSurfaceVariant),
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: bookmarks.length,
                    itemBuilder: (context, index) {
                      final b = bookmarks[index];
                      final pos = Duration(
                        milliseconds: (b['pos'] as num?)?.toInt() ?? 0,
                      );
                      return ListTile(
                        leading: Text(
                          _formatBookmarkTime(pos),
                          style: TextStyle(
                            color: accent,
                            fontFamily: 'monospace',
                          ),
                        ),
                        title: Text((b['note'] as String?) ?? ''),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Edit bookmark',
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () async {
                                await _editBookmarkNote(
                                  context,
                                  index: index,
                                  initial: (b['note'] as String?) ?? '',
                                );
                              },
                            ),
                            IconButton(
                              tooltip: 'Delete bookmark',
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () async {
                                await ctrl.removeBookmark(index);
                                if (!context.mounted) return;
                                showToast(context, 'Bookmark removed');
                              },
                            ),
                          ],
                        ),
                        onTap: () {
                          ctrl.player.seek(pos);
                          Navigator.pop(context);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatBookmarkTime(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) return '$h:$m:$s';
  return '$m:$s';
}