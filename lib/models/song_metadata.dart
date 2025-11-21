import 'dart:convert';

class SongMetadata {
  final String id;
  final int? rating;
  final String? lyrics;
  final int playCount;
  final DateTime? lastPlayed;
  final double? bpm;
  final String? key;

  const SongMetadata({
    required this.id,
    this.rating,
    this.lyrics,
    this.playCount = 0,
    this.lastPlayed,
    this.bpm,
    this.key,
  });

  SongMetadata copyWith({
    int? rating,
    String? lyrics,
    int? playCount,
    DateTime? lastPlayed,
    double? bpm,
    String? key,
  }) {
    return SongMetadata(
      id: id,
      rating: rating ?? this.rating,
      lyrics: lyrics ?? this.lyrics,
      playCount: playCount ?? this.playCount,
      lastPlayed: lastPlayed ?? this.lastPlayed,
      bpm: bpm ?? this.bpm,
      key: key ?? this.key,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'rating': rating,
      'lyrics': lyrics,
      'playCount': playCount,
      'lastPlayed': lastPlayed?.toIso8601String(),
      'bpm': bpm,
      'key': key,
    };
  }

  factory SongMetadata.fromMap(Map<String, dynamic> map) {
    return SongMetadata(
      id: map['id'] as String,
      rating: map['rating'] as int?,
      lyrics: map['lyrics'] as String?,
      playCount: (map['playCount'] as int?) ?? 0,
      lastPlayed: map['lastPlayed'] != null
          ? DateTime.tryParse(map['lastPlayed'] as String)
          : null,
      bpm: map['bpm'] as double?,
      key: map['key'] as String?,
    );
  }

  String toJson() => json.encode(toMap());

  factory SongMetadata.fromJson(String source) =>
      SongMetadata.fromMap(json.decode(source) as Map<String, dynamic>);
}