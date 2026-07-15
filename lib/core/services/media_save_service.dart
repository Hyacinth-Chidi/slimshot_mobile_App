import 'dart:io';

import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';

import '../utils/file_utils.dart';

class MediaSaveService {
  static Future<void> saveImagesToGallery(List<String> paths) async {
    for (final path in paths) {
      await Gal.putImage(path);
    }
  }

  static Future<void> saveOptimizedMediaToGallery(
    List<String> paths, {
    String album = 'SlimShotAI',
  }) async {
    for (var i = 0; i < paths.length; i++) {
      final path = paths[i];
      final prettyPath = await _copyWithGalleryName(path, i);

      try {
        if (isVideoPath(path)) {
          await Gal.putVideo(prettyPath, album: album);
        } else {
          await Gal.putImage(prettyPath, album: album);
        }
      } finally {
        await FileUtils.deleteFile(prettyPath);
      }
    }
  }

  static Future<void> shareFiles(List<String> paths) async {
    await Share.shareXFiles(paths.map((path) => XFile(path)).toList());
  }

  static bool isVideoPath(String path) {
    final ext = _extension(path);
    return ext == 'mp4' || ext == 'mov' || ext == 'm4v' || ext == 'webm';
  }

  static Future<String> _copyWithGalleryName(String path, int index) async {
    final file = File(path);
    final parentDir = file.parent.path;
    final now = DateTime.now();
    final timestamp =
        '${now.year}${_twoDigits(now.month)}${_twoDigits(now.day)}_'
        '${_twoDigits(now.hour)}${_twoDigits(now.minute)}${_twoDigits(now.second)}_$index';
    final kind = isVideoPath(path) ? 'Video' : 'Image';
    final sourceExtension = _extension(path);
    final ext = sourceExtension.isEmpty
        ? (isVideoPath(path) ? 'mp4' : 'jpg')
        : sourceExtension;
    final prettyPath = '$parentDir/SlimShot_${kind}_$timestamp.$ext';

    await file.copy(prettyPath);
    return prettyPath;
  }

  static String _extension(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == name.length - 1) return '';
    return name.substring(dotIndex + 1).toLowerCase();
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}
