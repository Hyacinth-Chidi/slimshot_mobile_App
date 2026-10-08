import 'dart:convert';
import 'dart:typed_data';

/// Whether [bytes] start like a JPEG (FF D8 FF).
bool isJpeg(Uint8List bytes) =>
    bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;

/// Removing a JPEG's personal data **without re-encoding the picture**.
///
/// A JPEG is a run of marker segments ahead of the compressed image. The
/// personal data lives in some of them — EXIF (location, camera, date, and
/// a thumbnail that can show the photo as it was before a crop), XMP, IPTC,
/// comments — and sometimes in a trailer appended after the image ends.
/// Dropping those and copying everything else byte for byte leaves the
/// picture exactly as it was; re-saving it, the old way, recompressed it,
/// lost a little quality and often made the file bigger.
///
/// What is kept: JFIF (APP0), the colour profile (APP2 `ICC_PROFILE`),
/// Adobe's colour-transform flag (APP14), every table and frame segment,
/// and the image data up to its end. The camera's rotation flag lives in
/// EXIF, and without it a portrait photo shows on its side — so it is
/// written back on its own, in an EXIF block holding nothing else.
Uint8List stripJpegMetadata(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    throw const FormatException('Not a JPEG');
  }
  final orientation = jpegOrientation(bytes);
  final kept = BytesBuilder(copy: false)..add(const [0xFF, 0xD8]);
  var wroteExif = false;
  void writeOrientation() {
    if (wroteExif) return;
    wroteExif = true;
    if (orientation != null && orientation != 1) {
      kept.add(_orientationOnlyExif(orientation));
    }
  }

  var i = 2;
  while (true) {
    if (i + 1 >= bytes.length || bytes[i] != 0xFF) {
      throw const FormatException('Malformed JPEG');
    }
    // Fill bytes before a marker.
    while (i + 1 < bytes.length && bytes[i + 1] == 0xFF) {
      i++;
    }
    if (i + 1 >= bytes.length) throw const FormatException('Malformed JPEG');
    final marker = bytes[i + 1];

    // Standalone markers carry no length.
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      kept.add(Uint8List.sublistView(bytes, i, i + 2));
      i += 2;
      continue;
    }
    if (marker == 0xD9) {
      writeOrientation();
      kept.add(const [0xFF, 0xD9]);
      return kept.takeBytes();
    }
    if (i + 3 >= bytes.length) throw const FormatException('Malformed JPEG');
    final length = (bytes[i + 2] << 8) | bytes[i + 3];
    final end = i + 2 + length;
    if (length < 2 || end > bytes.length) {
      throw const FormatException('Malformed JPEG');
    }

    if (marker == 0xDA) {
      // The image itself, from the first scan to the end of image. Inside
      // the entropy-coded data a 0xFF is always followed by 0x00 or a
      // restart marker, so the first FF D9 is the end; anything after it is
      // a trailer and is dropped.
      writeOrientation();
      final eoi = _endOfImage(bytes, end);
      if (eoi < 0) throw const FormatException('JPEG has no end');
      kept.add(Uint8List.sublistView(bytes, i, eoi + 2));
      return kept.takeBytes();
    }

    // EXIF goes right after JFIF where there is one, else right after SOI:
    // anything but APP0 means its place has come.
    if (marker != 0xE0) writeOrientation();
    if (_keep(marker, Uint8List.sublistView(bytes, i + 4, end))) {
      kept.add(Uint8List.sublistView(bytes, i, end));
    }
    i = end;
  }
}

bool _keep(int marker, Uint8List payload) {
  bool startsWith(String id) {
    final idBytes = ascii.encode(id);
    if (payload.length < idBytes.length) return false;
    for (var k = 0; k < idBytes.length; k++) {
      if (payload[k] != idBytes[k]) return false;
    }
    return true;
  }

  if (marker == 0xFE) return false; // COM
  if (marker >= 0xE0 && marker <= 0xEF) {
    return switch (marker) {
      // JFIF only — JFXX carries a thumbnail.
      0xE0 => startsWith('JFIF\u0000'),
      0xE2 => startsWith('ICC_PROFILE\u0000'),
      0xEE => startsWith('Adobe'),
      _ => false,
    };
  }
  return true;
}

/// The offset of the FF D9 that ends the image, searching from [from].
int _endOfImage(Uint8List bytes, int from) {
  for (var k = from; k + 1 < bytes.length; k++) {
    if (bytes[k] == 0xFF && bytes[k + 1] == 0xD9) return k;
  }
  return -1;
}

/// An APP1 EXIF segment holding the orientation and nothing else.
Uint8List _orientationOnlyExif(int orientation) {
  final tiff = <int>[
    0x4D, 0x4D, 0x00, 0x2A, // big-endian TIFF
    0x00, 0x00, 0x00, 0x08, // IFD0 at 8
    0x00, 0x01, // one entry
    0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, // Orientation, SHORT, 1
    orientation >> 8, orientation & 0xFF, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, // no next IFD
  ];
  final payload = [...ascii.encode('Exif'), 0, 0, ...tiff];
  final length = payload.length + 2;
  return Uint8List.fromList([0xFF, 0xE1, length >> 8, length & 0xFF, ...payload]);
}

/// The camera's rotation flag (EXIF tag 0x0112, 1–8), or null when the photo
/// has none or cannot be read. Never throws.
int? jpegOrientation(Uint8List bytes) {
  try {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
    var i = 2;
    while (i + 3 < bytes.length && bytes[i] == 0xFF) {
      final marker = bytes[i + 1];
      if (marker == 0xDA || marker == 0xD9) return null;
      final length = (bytes[i + 2] << 8) | bytes[i + 3];
      final start = i + 4;
      final end = i + 2 + length;
      if (length < 2 || end > bytes.length) return null;
      if (marker == 0xE1 &&
          end - start > 14 &&
          bytes[start] == 0x45 && // E
          bytes[start + 1] == 0x78 && // x
          bytes[start + 2] == 0x69 && // i
          bytes[start + 3] == 0x66 && // f
          bytes[start + 4] == 0 &&
          bytes[start + 5] == 0) {
        return _orientationFromTiff(Uint8List.sublistView(bytes, start + 6, end));
      }
      i = end;
    }
  } on RangeError {
    return null;
  }
  return null;
}

int? _orientationFromTiff(Uint8List tiff) {
  if (tiff.length < 8) return null;
  final Endian endian;
  if (tiff[0] == 0x4D && tiff[1] == 0x4D) {
    endian = Endian.big;
  } else if (tiff[0] == 0x49 && tiff[1] == 0x49) {
    endian = Endian.little;
  } else {
    return null;
  }
  final data = ByteData.sublistView(tiff);
  final ifd = data.getUint32(4, endian);
  if (ifd + 2 > tiff.length) return null;
  final count = data.getUint16(ifd, endian);
  for (var n = 0; n < count; n++) {
    final entry = ifd + 2 + n * 12;
    if (entry + 12 > tiff.length) return null;
    if (data.getUint16(entry, endian) == 0x0112) {
      final value = data.getUint16(entry + 8, endian);
      return value >= 1 && value <= 8 ? value : null;
    }
  }
  return null;
}
