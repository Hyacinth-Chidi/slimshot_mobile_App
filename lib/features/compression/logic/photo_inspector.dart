import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'compress_labels.dart';

/// What the photo screens need to know about a photo before showing it:
/// its shape and its "HEIC · 12 MP". One copy for every screen that shows a
/// picked photo, so none of them gets the shape wrong differently.
class PhotoInspector {
  /// Width over height as the photo is shown — read from the decoded image,
  /// which has already applied the camera's rotation flag. A phone stores
  /// most portrait photos sideways with that flag, so the file's own header
  /// would give them the wrong shape.
  final Map<String, double> aspect = {};

  /// "HEIC · 12 MP", from the file's header: width × height is the same
  /// whichever way round the photo is stored.
  final Map<String, String> info = {};

  /// The photo at a size fit for a phone screen; the same provider the
  /// shape is read through, so the decode is shared.
  ImageProvider imageFor(String path) => ResizeImage(
        FileImage(File(path)),
        width: 1600,
        policy: ResizeImagePolicy.fit,
      );

  /// Reads [path]'s shape and label once, calling [changed] as each lands.
  Future<void> inspect(String path, VoidCallback changed) async {
    if (!aspect.containsKey(path)) {
      final stream = imageFor(path).resolve(ImageConfiguration.empty);
      late final ImageStreamListener listener;
      listener = ImageStreamListener((image, _) {
        stream.removeListener(listener);
        final width = image.image.width;
        final height = image.image.height;
        if (width > 0 && height > 0) {
          aspect[path] = width / height;
          changed();
        }
      }, onError: (_, __) => stream.removeListener(listener));
      stream.addListener(listener);
    }
    if (!info.containsKey(path)) {
      int? width;
      int? height;
      try {
        final buffer = await ui.ImmutableBuffer.fromFilePath(path);
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        width = descriptor.width;
        height = descriptor.height;
        descriptor.dispose();
        buffer.dispose();
      } catch (_) {
        // A format the platform cannot read: the label keeps the format.
      }
      info[path] = photoInfoLabel(path, width, height);
      changed();
    }
  }
}
