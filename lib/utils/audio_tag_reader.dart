import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Best-effort embedded title/artist/album/duration from common audio tags.
///
/// Mirrors the lightweight header-scan approach used by [SonicDnaTagReader]
/// and [ReplayGainTagReader]. Does not cover every container (notably full
/// MP4/M4A atom trees and WMA); callers should keep filename fallbacks.
typedef AudioFileTags = ({
  String? title,
  String? artist,
  String? album,
  int? durationMs,
});

class AudioTagReader {
  AudioTagReader._();

  static Future<AudioFileTags> readFromFilePath(String path) async {
    final ext = path.toLowerCase();
    try {
      final file = File(path);
      if (!await file.exists()) {
        return (title: null, artist: null, album: null, durationMs: null);
      }

      final bytes = await file
          .openRead(0, 512 * 1024)
          .fold<BytesBuilder>(BytesBuilder(), (b, chunk) => b..add(chunk));
      final data = bytes.takeBytes();

      if (ext.endsWith('.mp3')) {
        return _readId3v2(data);
      }
      if (ext.endsWith('.flac')) {
        return _readFlacVorbisComments(data);
      }
      if (ext.endsWith('.ogg') || ext.endsWith('.opus')) {
        return _readOggVorbisComments(data);
      }
    } catch (_) {
      // Silent failure: caller keeps filename / MediaStore fallbacks.
    }

    return (title: null, artist: null, album: null, durationMs: null);
  }

  /// Synchronous variant for isolate workers that already hold file bytes.
  static AudioFileTags readFromBytes(Uint8List data, String path) {
    final ext = path.toLowerCase();
    try {
      if (ext.endsWith('.mp3')) return _readId3v2(data);
      if (ext.endsWith('.flac')) return _readFlacVorbisComments(data);
      if (ext.endsWith('.ogg') || ext.endsWith('.opus')) {
        return _readOggVorbisComments(data);
      }
    } catch (_) {}
    return (title: null, artist: null, album: null, durationMs: null);
  }

  static AudioFileTags _readId3v2(Uint8List bytes) {
    if (bytes.length < 10) {
      return (title: null, artist: null, album: null, durationMs: null);
    }
    if (bytes[0] != 0x49 || bytes[1] != 0x44 || bytes[2] != 0x33) {
      return (title: null, artist: null, album: null, durationMs: null);
    }

    final major = bytes[3];
    final tagSize = _synchsafeToInt(bytes.sublist(6, 10));
    final limit = (10 + tagSize).clamp(0, bytes.length);

    int i = 10;
    String? title;
    String? artist;
    String? album;
    int? durationMs;

    while (i + 10 <= limit) {
      final id = ascii.decode(bytes.sublist(i, i + 4), allowInvalid: true);
      if (id.trim().isEmpty || id == '\u0000\u0000\u0000\u0000') break;

      final sizeBytes = bytes.sublist(i + 4, i + 8);
      final frameSize =
          major == 4 ? _synchsafeToInt(sizeBytes) : _u32be(sizeBytes);
      final frameDataStart = i + 10;
      final frameDataEnd = frameDataStart + frameSize;
      if (frameSize <= 0 || frameDataEnd > limit) break;

      if (id == 'TIT2' || id == 'TPE1' || id == 'TALB' || id == 'TLEN') {
        final value = _decodeId3TextFrame(
          bytes.sublist(frameDataStart, frameDataEnd),
        );
        if (id == 'TIT2' && value.isNotEmpty) {
          title = value;
        } else if (id == 'TPE1' && value.isNotEmpty) {
          artist = value;
        } else if (id == 'TALB' && value.isNotEmpty) {
          album = value;
        } else if (id == 'TLEN') {
          final ms = int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), ''));
          if (ms != null && ms > 0) durationMs = ms;
        }
      }

      i = frameDataEnd;
      if (title != null && artist != null && album != null && durationMs != null) {
        break;
      }
    }

    return (
      title: title,
      artist: artist,
      album: album,
      durationMs: durationMs,
    );
  }

  static AudioFileTags _readFlacVorbisComments(Uint8List bytes) {
    if (bytes.length < 4) {
      return (title: null, artist: null, album: null, durationMs: null);
    }
    if (!(bytes[0] == 0x66 &&
        bytes[1] == 0x4C &&
        bytes[2] == 0x61 &&
        bytes[3] == 0x43)) {
      return (title: null, artist: null, album: null, durationMs: null);
    }

    int offset = 4;
    while (offset + 4 <= bytes.length) {
      final header = bytes[offset];
      final isLast = (header & 0x80) != 0;
      final type = header & 0x7F;
      final len =
          (bytes[offset + 1] << 16) |
          (bytes[offset + 2] << 8) |
          bytes[offset + 3];
      offset += 4;
      if (offset + len > bytes.length) break;

      if (type == 4) {
        return _parseVorbisCommentBlock(bytes.sublist(offset, offset + len));
      }

      offset += len;
      if (isLast) break;
    }

    return (title: null, artist: null, album: null, durationMs: null);
  }

  static AudioFileTags _readOggVorbisComments(Uint8List bytes) {
    int idx = _indexOf(bytes, ascii.encode('OpusTags'));
    if (idx >= 0 && idx + 8 + 8 < bytes.length) {
      return _parseVorbisCommentBlock(bytes.sublist(idx + 8));
    }

    idx = _indexOf(bytes, ascii.encode('vorbis'));
    if (idx >= 1 && bytes[idx - 1] == 0x03) {
      return _parseVorbisCommentBlock(bytes.sublist(idx + 6));
    }

    return (title: null, artist: null, album: null, durationMs: null);
  }

  static AudioFileTags _parseVorbisCommentBlock(Uint8List block) {
    if (block.length < 8) {
      return (title: null, artist: null, album: null, durationMs: null);
    }
    final bd = ByteData.sublistView(block);

    int offset = 0;
    final vendorLen = bd.getUint32(offset, Endian.little);
    offset += 4 + vendorLen;
    if (offset + 4 > block.length) {
      return (title: null, artist: null, album: null, durationMs: null);
    }

    final count = bd.getUint32(offset, Endian.little);
    offset += 4;

    String? title;
    String? artist;
    String? album;
    int? durationMs;

    for (int i = 0; i < count; i++) {
      if (offset + 4 > block.length) break;
      final len = bd.getUint32(offset, Endian.little);
      offset += 4;
      if (offset + len > block.length) break;

      final s = utf8.decode(
        block.sublist(offset, offset + len),
        allowMalformed: true,
      );
      offset += len;

      final eq = s.indexOf('=');
      if (eq <= 0) continue;
      final k = s.substring(0, eq).trim().toUpperCase();
      final v = s.substring(eq + 1).trim();
      if (v.isEmpty) continue;

      if (k == 'TITLE') {
        title ??= v;
      } else if (k == 'ARTIST') {
        artist ??= v;
      } else if (k == 'ALBUM') {
        album ??= v;
      } else if (k == 'LENGTH' || k == 'DURATION') {
        final ms = int.tryParse(v.replaceAll(RegExp(r'[^0-9]'), ''));
        if (ms != null && ms > 0) durationMs ??= ms;
      }
    }

    return (
      title: title,
      artist: artist,
      album: album,
      durationMs: durationMs,
    );
  }

  static int _synchsafeToInt(List<int> b) {
    if (b.length != 4) return 0;
    return ((b[0] & 0x7F) << 21) |
        ((b[1] & 0x7F) << 14) |
        ((b[2] & 0x7F) << 7) |
        (b[3] & 0x7F);
  }

  static int _u32be(List<int> b) {
    if (b.length != 4) return 0;
    return (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
  }

  static String _decodeId3TextFrame(Uint8List frame) {
    if (frame.isEmpty) return '';
    final encoding = frame[0];
    final payload = frame.sublist(1);

    switch (encoding) {
      case 0:
        return latin1
            .decode(payload, allowInvalid: true)
            .replaceAll('\u0000', '')
            .trim();
      case 3:
        return utf8
            .decode(payload, allowMalformed: true)
            .replaceAll('\u0000', '')
            .trim();
      case 1:
        return _decodeUtf16WithBom(payload);
      case 2:
        return _decodeUtf16(payload, Endian.big);
      default:
        return utf8
            .decode(payload, allowMalformed: true)
            .replaceAll('\u0000', '')
            .trim();
    }
  }

  static String _decodeUtf16WithBom(Uint8List bytes) {
    if (bytes.length < 2) return '';
    final bom0 = bytes[0];
    final bom1 = bytes[1];
    if (bom0 == 0xFF && bom1 == 0xFE) {
      return _decodeUtf16(bytes.sublist(2), Endian.little);
    }
    if (bom0 == 0xFE && bom1 == 0xFF) {
      return _decodeUtf16(bytes.sublist(2), Endian.big);
    }
    return _decodeUtf16(bytes, Endian.big);
  }

  static String _decodeUtf16(Uint8List bytes, Endian endian) {
    final bd = ByteData.sublistView(bytes);
    final codeUnits = <int>[];
    for (int i = 0; i + 1 < bytes.length; i += 2) {
      final cu = bd.getUint16(i, endian);
      if (cu == 0) continue;
      codeUnits.add(cu);
    }
    return String.fromCharCodes(codeUnits).trim();
  }

  static int _indexOf(Uint8List haystack, List<int> needle) {
    if (needle.isEmpty) return -1;
    for (int i = 0; i + needle.length <= haystack.length; i++) {
      bool ok = true;
      for (int j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }
}
