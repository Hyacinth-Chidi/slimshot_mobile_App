import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/media_picker_service.dart';
import '../models/media_asset.dart';

/// Turns picked files into [MediaAsset]s the timeline can place.
///
/// Probing happens natively in one batch: the extractor already holds each file
/// open for thumbnails, so asking it for duration and dimensions at the same
/// time avoids opening every file twice.
class MediaImportService {
  MediaImportService({MethodChannel? channel, MediaPickerService? picker})
      : _channel = channel ?? const MethodChannel(_channelName),
        _picker = picker ?? MediaPickerService();

  static const _channelName = 'slimshot_ai/video_thumbnails';

  final MethodChannel _channel;
  final MediaPickerService _picker;

  /// Opens the gallery for photos *and* videos together.
  ///
  /// Goes through [MediaPickerService] — the same picker the home screen uses
  /// — so adding media inside the editor behaves identically to starting a
  /// project, permission handling included.
  ///
  /// Returns assets in the order the user selected them, which becomes the
  /// clip order on the timeline.
  Future<List<MediaAsset>> pickMedia() async {
    final picked = await _picker.pickMedia();
    if (picked.isEmpty) return const [];
    return assetsFor(picked);
  }

  /// Probes [files] and builds assets, dropping any the platform cannot read.
  Future<List<MediaAsset>> assetsFor(List<XFile> files) async {
    if (files.isEmpty) return const [];

    final paths = files.map((file) => file.path).toList(growable: false);
    final probes = await _probe(paths);

    final assets = <MediaAsset>[];
    for (var index = 0; index < paths.length; index++) {
      final probe = probes[paths[index]];
      if (probe == null) {
        debugPrint('[MediaImport] skipped unreadable file: ${paths[index]}');
        continue;
      }
      assets.add(_assetFrom(paths[index], probe, index));
    }
    return assets;
  }

  MediaAsset _assetFrom(String path, Map<String, dynamic> probe, int index) {
    final isImage = probe['isImage'] as bool? ?? false;
    final durationMs = (probe['durationMs'] as num?)?.toDouble() ?? 0.0;

    return MediaAsset(
      // Unique per import, not per path: importing the same file twice should
      // give two independently trimmable assets.
      id: 'asset_${DateTime.now().microsecondsSinceEpoch}_$index',
      path: path,
      type: isImage ? MediaAssetType.image : MediaAssetType.video,
      durationSeconds: isImage ? 0.0 : durationMs / 1000.0,
      width: (probe['width'] as num?)?.toDouble() ?? 0.0,
      height: (probe['height'] as num?)?.toDouble() ?? 0.0,
      hasAudio: probe['hasAudio'] as bool? ?? false,
    );
  }

  Future<Map<String, Map<String, dynamic>>> _probe(List<String> paths) async {
    try {
      final results = await _channel.invokeListMethod<dynamic>('probe', {
        'paths': paths,
      });
      if (results == null) return const {};

      final byPath = <String, Map<String, dynamic>>{};
      for (final entry in results) {
        if (entry is! Map) continue;
        final probe = entry.map((key, value) => MapEntry(key.toString(), value));
        final path = probe['path'] as String?;
        if (path != null) byPath[path] = probe;
      }
      return byPath;
    } catch (error) {
      debugPrint('[MediaImport] probe failed: $error');
      return const {};
    }
  }

  /// The clip that should represent [asset] when it first lands on the
  /// timeline: a photo gets a default length, a video its whole range.
  static VideoSegmentSeed seedFor(MediaAsset asset) {
    return VideoSegmentSeed(
      assetId: asset.id,
      sourceStart: 0.0,
      sourceEnd: asset.isImage
          ? kDefaultPhotoDurationSeconds
          : asset.durationSeconds,
    );
  }
}

/// The time range a newly added clip should cover.
@immutable
class VideoSegmentSeed {
  const VideoSegmentSeed({
    required this.assetId,
    required this.sourceStart,
    required this.sourceEnd,
  });

  final String assetId;
  final double sourceStart;
  final double sourceEnd;
}
