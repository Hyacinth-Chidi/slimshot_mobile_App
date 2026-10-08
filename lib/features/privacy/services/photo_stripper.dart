import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../logic/jpeg_metadata.dart';

/// Writes a copy of a photo without its personal details. Behind an
/// interface so the privacy flow is tested without a device.
// ignore: one_member_abstracts
abstract class PhotoStripper {
  /// The cleaned copy's path. Throws when the photo cannot be cleaned.
  Future<String> strip(String inputPath);
}

/// A JPEG loses its metadata blocks and keeps its picture byte for byte
/// (`stripJpegMetadata`). Anything else — PNG, HEIC, WebP — is written out
/// again without them: PNG losslessly as PNG, the rest as a quality-100 JPEG,
/// because `ExifInterface` can rewrite neither HEIC nor WebP in place. A
/// JPEG too unusual to walk falls back to that too, rather than failing.
class DefaultPhotoStripper implements PhotoStripper {
  @override
  Future<String> strip(String inputPath) async {
    final dir = await getTemporaryDirectory();
    String out(String ext) =>
        '${dir.path}/slimshot_temp_privacy_${const Uuid().v4()}$ext';

    final bytes = await File(inputPath).readAsBytes();
    if (isJpeg(bytes)) {
      try {
        final path = out('.jpg');
        await File(path).writeAsBytes(stripJpegMetadata(bytes), flush: true);
        return path;
      } on FormatException catch (e) {
        debugPrint('PhotoStripper: lossless strip refused ($e), re-encoding');
      }
    }

    final png = inputPath.toLowerCase().endsWith('.png');
    final path = out(png ? '.png' : '.jpg');
    final result = await FlutterImageCompress.compressAndGetFile(
      inputPath,
      path,
      quality: 100,
      keepExif: false,
      format: png ? CompressFormat.png : CompressFormat.jpeg,
    );
    if (result == null) {
      throw Exception('Could not remove the details from this photo');
    }
    return result.path;
  }
}

final photoStripperProvider =
    Provider<PhotoStripper>((ref) => DefaultPhotoStripper());
