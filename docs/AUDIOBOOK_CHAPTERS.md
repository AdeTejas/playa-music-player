# Audiobook chapters & series shelf

Playa groups long-form listening for **Continue Listening** and the Library
**Series shelf** using best-effort heuristics.

## What works today

- **Multi-file series**: tracks that share an album+artist (or parent folder)
  key via `ContentModeDetector.seriesKeyForSong` appear as one series.
- **Chapter titles**: filenames/titles matching `Chapter N`, `Ch. N`, `Part N`,
  `Disc N`, etc. are ordered numerically inside a series.
- **Resume**: Continue Listening stores progress per series key and restores
  the last-played chapter file + position.

## Known limits

- **Embedded CUE sheets** (`.cue` companions) are **not** parsed.
- **MP4/M4B chapter atoms** (`chpl`, `©chap`, Nero/QuickTime chapter tracks)
  are **not** parsed on any platform yet.
- Single-file audiobooks without chapter markers appear as one “chapter”.
- MediaStore/`content://` paths on Android rely on the system title/album;
  weak tags fall back to filename heuristics (see polish item 11).

When native cue/chapter parsing lands, the Series shelf should prefer those
markers over title regexes while keeping the same series-key resume model.
