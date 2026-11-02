import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:slimshotai/features/video_editor/services/raw_atlas_file.dart';

/// A text atlas file as an image, for tests that look at its pixels.
///
/// The atlas is raw premultiplied RGBA (`raw_atlas_file.dart`), which no image
/// codec reads; `decodeImageFromPixels` takes those pixels as they are, and
/// `raw_atlas_file_test.dart` pins that what comes back is what was drawn.
Future<ui.Image> decodeAtlasImage(String path) {
  final pixels = decodeRawAtlas(File(path).readAsBytesSync());
  if (pixels == null) throw StateError('Not an atlas file: $path');
  final image = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels.rgba,
    pixels.width,
    pixels.height,
    ui.PixelFormat.rgba8888,
    image.complete,
  );
  return image.future;
}
