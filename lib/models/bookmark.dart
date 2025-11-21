import 'dart:convert';

class Bookmark {
  final Duration position;
  String note;

  Bookmark({required this.position, this.note = ''});

  Map<String, dynamic> toMap() {
    return {
      'position': position.inMilliseconds,
      'note': note,
    };
  }

  factory Bookmark.fromMap(Map<String, dynamic> map) {
    return Bookmark(
      position: Duration(milliseconds: map['position'] as int),
      note: map['note'] as String? ?? '',
    );
  }

  String toJson() => json.encode(toMap());

  factory Bookmark.fromJson(String source) => Bookmark.fromMap(json.decode(source));
  
  // Helper to try parsing from what might be a simple int string (legacy) or a JSON string
  static Bookmark parse(String str) {
    try {
      // Try parsing as JSON object first
      if (str.trim().startsWith('{')) {
        return Bookmark.fromJson(str);
      }
    } catch (_) {
      // Ignore json parse error, fall through to legacy
    }
    
    // Fallback: treat as legacy millisecond string
    final ms = int.tryParse(str) ?? 0;
    return Bookmark(position: Duration(milliseconds: ms));
  }
}
