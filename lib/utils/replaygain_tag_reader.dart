import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

typedef ReplayGainInfo =
    ({
      double? trackGainDb,
      double? trackPeak,
      double? albumGainDb,
      double? albumPeak,
    });

class ReplayGainTagReader {
  static Future<ReplayGainInfo> readFromFilePath(String path) async {
    final ext = path.toLowerCase();
    try {
      final file = File(path);
      if (!await file.exists()) {
        return (
          trackGainDb: null,
          trackPeak: null,
          albumGainDb: null,
          albumPeak: null,
        );
      }

      // Read the early metadata region. ID3v2 and FLAC blocks are at the start.
      final bytes = await file
          .openRead(0, 512 * 1024)
          .fold<BytesBuilder>(BytesBuilder(), (b, chunk) => b..add(chunk));
      final data = bytes.takeBytes();

      if (ext.endsWith('.mp3')) {
        return _readId3v2ReplayGain(data);
      }
      if (ext.endsWith('.flac')) {
        return _readFlacVorbisCommentsReplayGain(data);
      }
      if (ext.endsWith('.ogg') || ext.endsWith('.opus')) {
        return _readOggVorbisCommentsReplayGain(data);
      }
    } catch (_) {
      // Silent failure.
    }

    return (
      trackGainDb: null,
      trackPeak: null,
      albumGainDb: null,
      albumPeak: null,
    );
  }

  static ReplayGainInfo _readId3v2ReplayGain(Uint8List bytes) {
    if (bytes.length < 10) {
      return (
        trackGainDb: null,
        trackPeak: null,
        albumGainDb: null,
        albumPeak: null,
      );
    }
    if (bytes[0] != 0x49 || bytes[1] != 0x44 || bytes[2] != 0x33) {
      return (
        trackGainDb: null,
        trackPeak: null,
        albumGainDb: null,
        albumPeak: null,
      );
    }

    final major = bytes[3];
    final tagSize = _synchsafeToInt(bytes.sublist(6, 10));
    final limit = (10 + tagSize).clamp(0, bytes.length);

    int i = 10;
    double? trackGainDb;
    double? trackPeak;
    double? albumGainDb;
    double? albumPeak;

    while (i + 10 <= limit) {
      final id = ascii.decode(bytes.sublist(i, i + 4), allowInvalid: true);
      if (id.trim().isEmpty || id == '\u0000\u0000\u0000\u0000') break;

      final sizeBytes = bytes.sublist(i + 4, i + 8);
      final frameSize =
          major == 4 ? _synchsafeToInt(sizeBytes) : _u32be(sizeBytes);

      final frameDataStart = i + 10;
      final frameDataEnd = frameDataStart + frameSize;
      if (frameSize <= 0 || frameDataEnd > limit) break;

      if (id == 'TXXX') {
        final info = _decodeId3Txxx(
          bytes.sublist(frameDataStart, frameDataEnd),
        );
        final desc = info.description.trim().toLowerCase();
        final value = info.value.trim();

        // Common names.
        if (desc == 'replaygain_track_gain' && trackGainDb == null) {
          trackGainDb = _parseDb(value);
        } else if (desc == 'replaygain_track_peak' && trackPeak == null) {
          trackPeak = double.tryParse(
            value.replaceAll(RegExp(r'[^0-9\\.]'), ''),
          );
        } else if (desc == 'replaygain_album_gain' && albumGainDb == null) {
          albumGainDb = _parseDb(value);
        } else if (desc == 'replaygain_album_peak' && albumPeak == null) {
          albumPeak = double.tryParse(
            value.replaceAll(RegExp(r'[^0-9\\.]'), ''),
          );
        }

        if (trackGainDb != null &&
            trackPeak != null &&
            albumGainDb != null &&
            albumPeak != null) {
          break;
        }
      }

      i = frameDataEnd;
    }

    return (
      trackGainDb: trackGainDb,
      trackPeak: trackPeak,
      albumGainDb: albumGainDb,
      albumPeak: albumPeak,
    );
  }

  static ({String description, String value}) _decodeId3Txxx(Uint8List frame) {
    if (frame.isEmpty) return (description: '', value: '');
    final encoding = frame[0];
    final payload = frame.sublist(1);

    // Decode payload as best-effort string, then split at first NUL.
    final decoded = switch (encoding) {
      0 => latin1.decode(payload, allowInvalid: true),
      3 => utf8.decode(payload, allowMalformed: true),
      1 => _decodeUtf16WithBom(payload),
      2 => _decodeUtf16(payload, Endian.big),
      _ => utf8.decode(payload, allowMalformed: true),
    };

    final cleaned = decoded.replaceAll('\u0000\u0000', '\u0000');
    final nul = cleaned.indexOf('\u0000');
    if (nul < 0) return (description: cleaned.trim(), value: '');
    final desc = cleaned.substring(0, nul);
    final val = cleaned.substring(nul + 1);
    return (description: desc, value: val);
  }

  static ReplayGainInfo _readFlacVorbisCommentsReplayGain(Uint8List bytes) {
    if (bytes.length < 4) {
      return (
        trackGainDb: null,
        trackPeak: null,
        albumGainDb: null,
        albumPeak: null,
      );
    }
    if (!(bytes[0] == 0x66 &&
        bytes[1] == 0x4C &&
        bytes[2] == 0x61 &&
        bytes[3] == 0x43)) {
      return (
        trackGainDb: null,
        trackPeak: null,
        albumGainDb: null,
        albumPeak: null,
      );
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
        final block = bytes.sublist(offset, offset + len);
        return _parseVorbisCommentBlockReplayGain(block);
      }

      offset += len;
      if (isLast) break;
    }

    return (
      trackGainDb: null,
      trackPeak: null,
      albumGainDb: null,
      albumPeak: null,
    );
  }

  static ReplayGainInfo _readOggVorbisCommentsReplayGain(Uint8List bytes) {
    int idx = _indexOf(bytes, ascii.encode('OpusTags'));
    if (idx >= 0 && idx + 8 + 8 < bytes.length) {
      final start = idx + 8;
      return _parseVorbisCommentBlockReplayGain(bytes.sublist(start));
    }

    idx = _indexOf(bytes, ascii.encode('vorbis'));
    if (idx >= 1 && bytes[idx - 1] == 0x03) {
      final start = idx + 6;
      return _parseVorbisCommentBlockReplayGain(bytes.sublist(start));
    }

    return (
      trackGainDb: null,
      trackPeak: null,
      albumGainDb: null,
      albumPeak: null,
    );
  }

  static ReplayGainInfo _parseVorbisCommentBlockReplayGain(Uint8List block) {
    if (block.length < 8) {
      return (
        trackGainDb: null,
        trackPeak: null,
        albumGainDb: null,
        albumPeak: null,
      );
    }
    final bd = ByteData.sublistView(block);

    int offset = 0;
    final vendorLen = bd.getUint32(offset, Endian.little);
    offset += 4 + vendorLen;
    if (offset + 4 > block.length) {
      return (
        trackGainDb: null,
        trackPeak: null,
        albumGainDb: null,
        albumPeak: null,
      );
    }

    final count = bd.getUint32(offset, Endian.little);
    offset += 4;

    double? trackGainDb;
    double? trackPeak;
    double? albumGainDb;
    double? albumPeak;

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

      if (k == 'REPLAYGAIN_TRACK_GAIN' && trackGainDb == null) {
        trackGainDb = _parseDb(v);
      } else if (k == 'REPLAYGAIN_TRACK_PEAK' && trackPeak == null) {
        trackPeak = double.tryParse(v.replaceAll(RegExp(r'[^0-9\\.]'), ''));
      } else if (k == 'REPLAYGAIN_ALBUM_GAIN' && albumGainDb == null) {
        albumGainDb = _parseDb(v);
      } else if (k == 'REPLAYGAIN_ALBUM_PEAK' && albumPeak == null) {
        albumPeak = double.tryParse(v.replaceAll(RegExp(r'[^0-9\\.]'), ''));
      }

      if (trackGainDb != null &&
          trackPeak != null &&
          albumGainDb != null &&
          albumPeak != null) {
        break;
      }
    }

    return (
      trackGainDb: trackGainDb,
      trackPeak: trackPeak,
      albumGainDb: albumGainDb,
      albumPeak: albumPeak,
    );
  }

  static double? _parseDb(String s) {
    // Examples: "-7.12 dB" or "-7.12".
    final m = RegExp(r'([-+]?[0-9]+(\\.[0-9]+)?)').firstMatch(s);
    if (m == null) return null;
    return double.tryParse(m.group(1)!);
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

  static String _decodeUtf16WithBom(Uint8List payload) {
    if (payload.length < 2) return '';
    final bom0 = payload[0];
    final bom1 = payload[1];
    final rest = payload.sublist(2);

    if (bom0 == 0xFF && bom1 == 0xFE) {
      return _decodeUtf16(rest, Endian.little);
    }
    if (bom0 == 0xFE && bom1 == 0xFF) {
      return _decodeUtf16(rest, Endian.big);
    }
    // No BOM: assume little.
    return _decodeUtf16(payload, Endian.little);
  }

  static String _decodeUtf16(Uint8List payload, Endian endian) {
    if (payload.isEmpty) return '';
    final bd = ByteData.sublistView(payload);
    final codes = <int>[];
    for (int i = 0; i + 1 < payload.length; i += 2) {
      final c = bd.getUint16(i, endian);
      if (c == 0) continue;
      codes.add(c);
    }
    return String.fromCharCodes(codes);
  }

  static int _indexOf(Uint8List data, List<int> needle) {
    if (needle.isEmpty || data.isEmpty || needle.length > data.length) {
      return -1;
    }
    outer:
    for (int i = 0; i <= data.length - needle.length; i++) {
      for (int j = 0; j < needle.length; j++) {
        if (data[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }
}
