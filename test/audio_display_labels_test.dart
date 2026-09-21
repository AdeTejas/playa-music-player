import 'package:flutter_test/flutter_test.dart';
import 'package:playa_clean/utils/audio_display_labels.dart';

void main() {
  group('AudioDisplayLabels', () {
    test('parses Artist - Title from filename when tags missing', () {
      expect(
        AudioDisplayLabels.displayTitle(
          title: '01 - Radiohead - Karma Police',
          path: r'C:\Music\01 - Radiohead - Karma Police.mp3',
        ),
        'Karma Police',
      );
      expect(
        AudioDisplayLabels.displayArtist(
          artist: 'Unknown Artist',
          path: r'/music/Radiohead - Karma Police.mp3',
        ),
        'Radiohead',
      );
      expect(
        AudioDisplayLabels.displayTitle(
          title: 'Radiohead - Karma Police',
          path: r'/music/Radiohead - Karma Police.mp3',
        ),
        'Karma Police',
      );
    });

    test('keeps real embedded titles', () {
      expect(
        AudioDisplayLabels.displayTitle(
          title: 'Karma Police',
          path: r'/music/track01.mp3',
          artist: 'Radiohead',
        ),
        'Karma Police',
      );
    });

    test('softens unknown artist for UI', () {
      expect(AudioDisplayLabels.isUnknownArtist('Unknown Artist'), isTrue);
      expect(AudioDisplayLabels.isUnknownArtist('<unknown>'), isTrue);
      expect(
        AudioDisplayLabels.displayArtistOrFallback(
          artist: 'Unknown Artist',
          path: '/a/lonely_file.mp3',
        ),
        'Artist unknown',
      );
    });
  });
}
