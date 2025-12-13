import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

typedef SonicDna = ({double? bpm, String? key});

class SonicDnaTagReader {
  static Future<SonicDna> readFromFilePath(String path) async {
    final ext = path.toLowerCase();
    try {
      final file = File(path);
      if (!await file.exists()) return (bpm: null, key: null);

      // Read just the header-ish portion for tags (keeps scanning fast).
      // ID3 tags live at the beginning; FLAC metadata blocks are early too.
      final bytes = await file
          .openRead(0, 256 * 1024)
          .fold<BytesBuilder>(BytesBuilder(), (b, chunk) => b..add(chunk));
      final data = bytes.takeBytes();

      if (ext.endsWith('.mp3')) {
        return _readId3v2(data);
      }
      if (ext.endsWith('.flac')) {
        return _readFlacVorbisComments(data);
      }

      // Best-effort support: Opus/Vorbis comments in OGG/OPUS containers.
      if (ext.endsWith('.ogg') || ext.endsWith('.opus')) {
        return _readOggVorbisComments(data);
      }
    } catch (_) {
      // Silent failure: caller treats missing as unknown.
    }

    return (bpm: null, key: null);
  }

  static SonicDna _readId3v2(Uint8List bytes) {
    if (bytes.length < 10) return (bpm: null, key: null);
    if (bytes[0] != 0x49 || bytes[1] != 0x44 || bytes[2] != 0x33) {
      return (bpm: null, key: null);
    }

    final major = bytes[3]; // 3 => ID3v2.3, 4 => ID3v2.4
    final tagSize = _synchsafeToInt(bytes.sublist(6, 10));
    final limit = (10 + tagSize).clamp(0, bytes.length);

    int i = 10;
    double? bpm;
    String? key;

    while (i + 10 <= limit) {
      final id = ascii.decode(bytes.sublist(i, i + 4), allowInvalid: true);
      if (id.trim().isEmpty || id == '\u0000\u0000\u0000\u0000') break;

      final sizeBytes = bytes.sublist(i + 4, i + 8);
      final frameSize =
          major == 4 ? _synchsafeToInt(sizeBytes) : _u32be(sizeBytes);

      // Skip flags
      final frameDataStart = i + 10;
      final frameDataEnd = frameDataStart + frameSize;
      if (frameSize <= 0 || frameDataEnd > limit) break;

      if (id == 'TBPM' || id == 'TKEY') {
        final value = _decodeId3TextFrame(
          bytes.sublist(frameDataStart, frameDataEnd),
        );
        if (id == 'TBPM') {
          final parsed = double.tryParse(
            value.replaceAll(RegExp(r'[^0-9\\.]'), ''),
          );
          if (parsed != null) bpm = parsed;
        } else {
          final cleaned = value.trim();
          if (cleaned.isNotEmpty) key = cleaned;
        }

        if (bpm != null && key != null) break;
      }

      i = frameDataEnd;
    }

    return (bpm: bpm, key: key);
  }

  static SonicDna _readFlacVorbisComments(Uint8List bytes) {
    if (bytes.length < 4) return (bpm: null, key: null);
    if (!(bytes[0] == 0x66 &&
        bytes[1] == 0x4C &&
        bytes[2] == 0x61 &&
        bytes[3] == 0x43)) {
      return (bpm: null, key: null);
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
        return _parseVorbisCommentBlock(block);
      }

      offset += len;
      if (isLast) break;
    }

    return (bpm: null, key: null);
  }

  static SonicDna _readOggVorbisComments(Uint8List bytes) {
    // Very lightweight heuristic: find "OpusTags" or the Vorbis comment packet marker.
    // - Opus comment packet begins with ASCII "OpusTags".
    // - Vorbis comment packet begins with 0x03 + "vorbis".

    int idx = _indexOf(bytes, ascii.encode('OpusTags'));
    if (idx >= 0 && idx + 8 + 8 < bytes.length) {
      final start = idx + 8;
      return _parseVorbisCommentBlock(bytes.sublist(start));
    }

    idx = _indexOf(bytes, ascii.encode('vorbis'));
    if (idx >= 1 && bytes[idx - 1] == 0x03) {
      final start = idx + 6;
      return _parseVorbisCommentBlock(bytes.sublist(start));
    }

    return (bpm: null, key: null);
  }

  static SonicDna _parseVorbisCommentBlock(Uint8List block) {
    if (block.length < 8) return (bpm: null, key: null);
    final bd = ByteData.sublistView(block);

    int offset = 0;
    final vendorLen = bd.getUint32(offset, Endian.little);
    offset += 4 + vendorLen;
    if (offset + 4 > block.length) return (bpm: null, key: null);

    final count = bd.getUint32(offset, Endian.little);
    offset += 4;

    double? bpm;
    String? key;

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

      if (k == 'BPM' && bpm == null) {
        bpm = double.tryParse(v.replaceAll(RegExp(r'[^0-9\\.]'), ''));
      }
      if ((k == 'INITIALKEY' || k == 'KEY') && (key == null || key.isEmpty)) {
        if (v.isNotEmpty) key = v;
      }

      if (bpm != null && key != null) break;
    }

    return (bpm: bpm, key: key);
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

    // 0: ISO-8859-1, 1: UTF-16 with BOM, 2: UTF-16BE, 3: UTF-8
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
    // No BOM; assume BE (common for ID3).
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
