import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// A text atlas as the engine reads it: its raw pixels, compressed.
///
/// It was a PNG, and encoding the PNG was two thirds of the wait before a
/// captioned export began — an atlas is a couple of million pixels, nearly all
/// of them the empty padding a shadow needs, and Flutter's PNG encoder works
/// hard on every one (measured: 129 ms an atlas, against 29 ms to read the
/// pixels back and deflate them at zlib's fastest level). Both are lossless,
/// so the engine gets exactly the pixels Flutter drew; the raw pixels even
/// skip the round trip a PNG makes out of premultiplied alpha and back.
///
/// The layout — `SSRZ`, then width and height as little-endian 32-bit
/// integers, then the premultiplied RGBA rows deflated as one zlib stream —
/// is read by `RawAtlasFile.kt`, and both sides are tested against
/// `test/fixtures/raw_atlas_fixture.rgbz`. If one changes the other must.
const String kRawAtlasExtension = 'rgbz';

const List<int> _magic = [0x53, 0x53, 0x52, 0x5A]; // "SSRZ"
const int _headerBytes = 12;

/// An atlas's pixels: premultiplied RGBA, row by row, four bytes a pixel.
class RawAtlasPixels {
  const RawAtlasPixels(this.width, this.height, this.rgba);

  final int width;
  final int height;
  final Uint8List rgba;
}

/// The file's bytes for [width] x [height] premultiplied RGBA [rgba].
Uint8List encodeRawAtlas(Uint8List rgba, int width, int height) {
  final deflated = ZLibCodec(level: 1).encode(rgba);
  final out = Uint8List(_headerBytes + deflated.length);
  out.setAll(0, _magic);
  ByteData.sublistView(out)
    ..setUint32(4, width, Endian.little)
    ..setUint32(8, height, Endian.little);
  out.setAll(_headerBytes, deflated);
  return out;
}

/// The pixels in an atlas file's [bytes], or null for anything that is not
/// one whole — another format, a short header, pixels short of the size.
RawAtlasPixels? decodeRawAtlas(Uint8List bytes) {
  if (bytes.length < _headerBytes) return null;
  for (var i = 0; i < _magic.length; i++) {
    if (bytes[i] != _magic[i]) return null;
  }
  final header = ByteData.sublistView(bytes);
  final width = header.getUint32(4, Endian.little);
  final height = header.getUint32(8, Endian.little);
  try {
    final rgba = Uint8List.fromList(
      ZLibCodec().decode(Uint8List.sublistView(bytes, _headerBytes)),
    );
    if (rgba.length != width * height * 4) return null;
    return RawAtlasPixels(width, height, rgba);
  } on Exception {
    // A stream zlib refuses.
    return null;
  }
}

/// Writes [image] to [path] as an atlas file. The deflate runs on a
/// background isolate, so it never holds up a frame on the screen it is
/// prepared under.
Future<void> writeRawAtlas(ui.Image image, String path) async {
  final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (pixels == null) throw StateError('No pixels to read back');
  final rgba = pixels.buffer.asUint8List(pixels.offsetInBytes, pixels.lengthInBytes);
  final width = image.width;
  final height = image.height;
  final bytes = await Isolate.run(() => encodeRawAtlas(rgba, width, height));
  await File(path).writeAsBytes(bytes);
}
