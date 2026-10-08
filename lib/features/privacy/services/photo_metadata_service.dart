import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/photo_metadata.dart';

/// What a photo file carries. Behind an interface so the privacy flow is
/// tested without a device.
// ignore: one_member_abstracts
abstract class PhotoMetadataService {
  /// Null when the file could not be read at all.
  Future<PhotoMetadata?> read(String path);
}

/// Android's `ExifInterface`, through `PhotoMetadataReader.kt`.
class ChannelPhotoMetadataService implements PhotoMetadataService {
  static const _channel = MethodChannel('slimshot_ai/photo_metadata');

  @override
  Future<PhotoMetadata?> read(String path) async {
    try {
      final map = await _channel.invokeMapMethod<Object?, Object?>(
        'read',
        {'path': path},
      );
      return map == null ? null : PhotoMetadata.fromMap(map);
    } catch (e) {
      debugPrint('PhotoMetadataService: $path: $e');
      return null;
    }
  }
}

final photoMetadataServiceProvider = Provider<PhotoMetadataService>(
  (ref) => ChannelPhotoMetadataService(),
);
