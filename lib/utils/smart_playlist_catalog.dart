import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

enum SmartPlaylistType { heavyRotation, recentlyAdded, forgottenFavorites }

class SmartPlaylistInfo {
  final String id;
  final SmartPlaylistType type;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const SmartPlaylistInfo({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

const List<SmartPlaylistInfo> kSmartPlaylistCatalog = [
  SmartPlaylistInfo(
    id: 'heavyRotation',
    type: SmartPlaylistType.heavyRotation,
    title: 'Heavy Rotation',
    subtitle: 'Your most played tracks',
    icon: PhosphorIconsFill.fire,
    color: Colors.orangeAccent,
  ),
  SmartPlaylistInfo(
    id: 'recentlyAdded',
    type: SmartPlaylistType.recentlyAdded,
    title: 'Recently Added',
    subtitle: 'Fresh tunes',
    icon: PhosphorIconsFill.clockCounterClockwise,
    color: Colors.blueAccent,
  ),
  SmartPlaylistInfo(
    id: 'forgottenFavorites',
    type: SmartPlaylistType.forgottenFavorites,
    title: 'Forgotten Favorites',
    subtitle: 'Rediscover old gems',
    icon: PhosphorIconsFill.archive,
    color: Colors.purpleAccent,
  ),
];

SmartPlaylistInfo? smartPlaylistInfoFor(String id) {
  for (final info in kSmartPlaylistCatalog) {
    if (info.id == id) return info;
  }
  return null;
}

List<SmartPlaylistInfo> orderedSmartPlaylists(List<String> order) {
  final byId = {for (final i in kSmartPlaylistCatalog) i.id: i};
  final out = <SmartPlaylistInfo>[];
  for (final id in order) {
    final info = byId[id];
    if (info != null) out.add(info);
  }
  for (final info in kSmartPlaylistCatalog) {
    if (!out.any((e) => e.id == info.id)) out.add(info);
  }
  return out;
}
