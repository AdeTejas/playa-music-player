import 'dart:convert';

class Playlist {
  final String id;
  final String name;
  final String? description;
  final List<String> songIds;
  final bool isFavorite;
  final int playCount;

  const Playlist({
    required this.id,
    required this.name,
    this.description,
    this.songIds = const [],
    this.isFavorite = false,
    this.playCount = 0,
  });

  int get songCount => songIds.length;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'songIds': songIds,
      'isFavorite': isFavorite,
      'playCount': playCount,
    };
  }

  factory Playlist.fromMap(Map<String, dynamic> map) {
    return Playlist(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      songIds: List<String>.from(map['songIds'] ?? []),
      isFavorite: map['isFavorite'] as bool? ?? false,
      playCount: map['playCount'] as int? ?? 0,
    );
  }

  String toJson() => json.encode(toMap());

  factory Playlist.fromJson(String source) =>
      Playlist.fromMap(json.decode(source));
}
