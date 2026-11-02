import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/services/raw_atlas_file.dart';

/// A text atlas reaches the engine as its raw pixels, compressed — not as a
/// PNG, whose encoder was two thirds of the wait before a captioned export
/// began. Lossless both ways, so the engine gets exactly what Flutter drew.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Premultiplied RGBA: opaque red, half-covered green, nothing, a faint tint.
  final pixels = Uint8List.fromList([
    255, 0, 0, 255, //
    0, 128, 0, 128, //
    0, 0, 0, 0, //
    10, 20, 30, 40, //
  ]);

  test('what is encoded decodes to the same pixels', () {
    final read = decodeRawAtlas(encodeRawAtlas(pixels, 2, 2))!;
    expect(read.width, 2);
    expect(read.height, 2);
    expect(read.rgba, pixels);
  });

  test('a header of magic, then width and height little-endian', () {
    final bytes = encodeRawAtlas(pixels, 2, 2);
    expect(bytes.sublist(0, 4), 'SSRZ'.codeUnits);
    final header = ByteData.sublistView(bytes);
    expect(header.getUint32(4, Endian.little), 2);
    expect(header.getUint32(8, Endian.little), 2);
  });

  test('anything that is not an atlas reads as none', () {
    final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0]);
    expect(decodeRawAtlas(png), isNull);
    expect(decodeRawAtlas(Uint8List(3)), isNull, reason: 'shorter than a header');
    final wrongSize = encodeRawAtlas(pixels, 2, 2);
    ByteData.sublistView(wrongSize).setUint32(4, 3, Endian.little);
    expect(decodeRawAtlas(wrongSize), isNull, reason: 'pixels short of 3x2');
  });

  test('a written image is exactly the pixels Flutter drew', () async {
    final recorder = ui.PictureRecorder();
    // Half-transparent, so a premultiplication slip would show.
    Canvas(recorder).drawCircle(
      const Offset(8, 8),
      6,
      Paint()..color = const Color(0x80FF3366),
    );
    final image = await recorder.endRecording().toImage(16, 16);
    final drawn =
        (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
    final dir = await Directory.systemTemp.createTemp('raw_atlas_test_');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/atlas.$kRawAtlasExtension';

    await writeRawAtlas(image, path);
    image.dispose();

    final read = decodeRawAtlas(await File(path).readAsBytes())!;
    expect(read.width, 16);
    expect(read.height, 16);
    expect(read.rgba, drawn);
  });

  // The engine's reader is tested against this same file
  // (`RawAtlasFileTest`), so the two sides cannot drift apart. Regenerate with
  // UPDATE_RAW_ATLAS_FIXTURE=1, then re-run the Kotlin suite.
  test('the fixture both sides read holds these pixels', () {
    final files = [
      File('test/fixtures/raw_atlas_fixture.rgbz'),
      File('android/app/src/test/resources/raw_atlas_fixture.rgbz'),
    ];
    if (Platform.environment['UPDATE_RAW_ATLAS_FIXTURE'] == '1') {
      for (final file in files) {
        file.writeAsBytesSync(encodeRawAtlas(pixels, 2, 2));
      }
    }
    for (final file in files) {
      final read = decodeRawAtlas(file.readAsBytesSync())!;
      expect(read.width, 2, reason: file.path);
      expect(read.height, 2, reason: file.path);
      expect(read.rgba, pixels, reason: file.path);
    }
  });
}
