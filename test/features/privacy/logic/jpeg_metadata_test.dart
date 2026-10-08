import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/privacy/logic/jpeg_metadata.dart';

/// One marker segment: FF, marker, a big-endian length that counts itself,
/// then the payload.
List<int> _segment(int marker, List<int> payload) {
  final length = payload.length + 2;
  return [0xFF, marker, length >> 8, length & 0xFF, ...payload];
}

/// An EXIF block: "Exif\0\0", a TIFF header in either byte order, and IFD0
/// holding the orientation and, beside it, an ASCII "secret" value the way a
/// camera model or GPS reference sits there.
List<int> _exif({required bool bigEndian, int? orientation}) {
  List<int> u16(int v) => bigEndian ? [v >> 8, v & 0xFF] : [v & 0xFF, v >> 8];
  List<int> u32(int v) => bigEndian
      ? [v >> 24, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF]
      : [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, v >> 24];
  final secret = utf8.encode('secret-camera\x00');
  final entries = <List<int>>[
    if (orientation != null) [...u16(0x0112), ...u16(3), ...u32(1), ...u16(orientation), 0, 0],
    // Model (0x0110), ASCII, stored past the IFD.
    [...u16(0x0110), ...u16(2), ...u32(secret.length), ...u32(8 + 2 + 12 * (orientation == null ? 1 : 2) + 4)],
  ];
  final tiff = [
    ...(bigEndian ? [0x4D, 0x4D] : [0x49, 0x49]),
    ...u16(42),
    ...u32(8),
    ...u16(entries.length),
    for (final e in entries) ...e,
    ...u32(0),
    ...secret,
  ];
  return [...ascii.encode('Exif'), 0, 0, ...tiff];
}

/// The picture itself: tables, the frame, a scan whose entropy data holds a
/// stuffed FF00 and a restart marker, and the end of image.
final List<int> _picture = [
  ..._segment(0xDB, List.filled(65, 7)), // DQT
  ..._segment(0xC0, [8, 0, 16, 0, 16, 1, 1, 0x11, 0]), // SOF0
  ..._segment(0xC4, List.filled(20, 3)), // DHT
  ..._segment(0xDA, [1, 1, 0, 0, 63, 0]), // SOS header
  0x12, 0xFF, 0x00, 0x34, 0xFF, 0xD0, 0x56, 0x78, // entropy-coded data
  0xFF, 0xD9, // EOI
];

Uint8List _photo({int? orientation = 6, bool bigEndian = true}) {
  return Uint8List.fromList([
    0xFF, 0xD8, // SOI
    ..._segment(0xE0, [...ascii.encode('JFIF'), 0, 1, 1, 0, 0, 1, 0, 1, 0, 0]),
    ..._segment(0xE1, _exif(bigEndian: bigEndian, orientation: orientation)),
    ..._segment(0xE1, [...ascii.encode('http://ns.adobe.com/xap/1.0/'), 0,
      ...utf8.encode('<x:xmpmeta>secret-xmp</x:xmpmeta>')]),
    ..._segment(0xE2, [...ascii.encode('ICC_PROFILE'), 0, 1, 1, ...List.filled(30, 9)]),
    ..._segment(0xE2, [...ascii.encode('MPF'), 0, ...utf8.encode('secret-mpf')]),
    ..._segment(0xED, [...ascii.encode('Photoshop 3.0'), 0, ...utf8.encode('secret-iptc')]),
    ..._segment(0xFE, utf8.encode('secret-comment')),
    ..._picture,
    // A trailer some phones append after the image: a second picture, or
    // their own metadata.
    ...utf8.encode('secret-trailer'),
  ]);
}

bool _contains(List<int> haystack, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

void main() {
  group('stripJpegMetadata', () {
    test('takes out every place personal data lives', () {
      final out = stripJpegMetadata(_photo());
      expect(_contains(out, ascii.encode('secret')), isFalse);
    });

    test('leaves the picture byte for byte as it was', () {
      final out = stripJpegMetadata(_photo());
      expect(out.sublist(out.length - _picture.length), _picture);
      expect(out.sublist(0, 2), [0xFF, 0xD8]);
    });

    test('keeps the colour profile and the JFIF header', () {
      final out = stripJpegMetadata(_photo());
      expect(_contains(out, ascii.encode('ICC_PROFILE')), isTrue);
      expect(_contains(out, ascii.encode('JFIF')), isTrue);
    });

    test('keeps the rotation, so a portrait photo stays upright', () {
      for (final bigEndian in [true, false]) {
        final out = stripJpegMetadata(_photo(orientation: 6, bigEndian: bigEndian));
        expect(jpegOrientation(out), 6, reason: 'bigEndian: $bigEndian');
      }
    });

    test('an upright photo carries no EXIF at all afterwards', () {
      for (final orientation in [null, 1]) {
        final out = stripJpegMetadata(_photo(orientation: orientation));
        expect(_contains(out, ascii.encode('Exif')), isFalse,
            reason: 'orientation: $orientation');
      }
    });

    test('refuses what is not a JPEG, or is cut short', () {
      expect(() => stripJpegMetadata(Uint8List.fromList(ascii.encode('PNG..'))),
          throwsFormatException);
      final cut = _photo();
      expect(() => stripJpegMetadata(Uint8List.sublistView(cut, 0, 40)),
          throwsFormatException);
    });
  });

  group('jpegOrientation', () {
    test('reads the flag in either byte order', () {
      expect(jpegOrientation(_photo(orientation: 3, bigEndian: true)), 3);
      expect(jpegOrientation(_photo(orientation: 8, bigEndian: false)), 8);
    });

    test('is null without one, and never throws on junk', () {
      expect(jpegOrientation(_photo(orientation: null)), isNull);
      expect(jpegOrientation(Uint8List.fromList([0xFF, 0xD8, 0xFF])), isNull);
      expect(jpegOrientation(Uint8List(0)), isNull);
    });
  });
}
