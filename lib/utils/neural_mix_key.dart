/// Parses a musical key string (e.g. `F#m`, `A minor`, `G♭`) into a
/// semitone pitch and minor flag. Shared by the Neural Mix rank function
/// (runs in an isolate) and the warm index builder so keys are only parsed
/// once per library.
({int pitch, bool minor})? parseNeuralMixKey(String? key) {
  if (key == null) return null;
  final raw = key.trim();
  if (raw.isEmpty) return null;
  final compact = raw.replaceAll(RegExp(r'\s+'), '');
  final lower = compact.toLowerCase();
  final isMinor =
      compact.endsWith('m') ||
      lower.endsWith('min') ||
      lower.endsWith('minor');
  var note = compact;
  if (lower.endsWith('minor')) note = note.substring(0, note.length - 5);
  if (lower.endsWith('min')) note = note.substring(0, note.length - 3);
  if (note.endsWith('m')) note = note.substring(0, note.length - 1);
  if (note.isEmpty) return null;

  final normalized = note[0].toUpperCase() + note.substring(1);
  const map = <String, int>{
    'C': 0,
    'C#': 1,
    'Db': 1,
    'D': 2,
    'D#': 3,
    'Eb': 3,
    'E': 4,
    'F': 5,
    'F#': 6,
    'Gb': 6,
    'G': 7,
    'G#': 8,
    'Ab': 8,
    'A': 9,
    'A#': 10,
    'Bb': 10,
    'B': 11,
  };

  final pitch = map[normalized];
  if (pitch == null) return null;
  return (pitch: pitch, minor: isMinor);
}
