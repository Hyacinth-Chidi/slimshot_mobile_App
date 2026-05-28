import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class FileUtils {
  static const String filePrefix = 'slimshot_temp_';

  static String formatFileSize(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (log(bytes) / log(1024)).floor();
    return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }

  static double calculateCompressionRatio(
    int originalSize,
    int compressedSize,
  ) {
    if (originalSize == 0) return 0;
    return (1 - (compressedSize / originalSize)) * 100;
  }

  /// --------------------------------------------------------------------------
  /// CACHE MANAGEMENT
  /// --------------------------------------------------------------------------

  /// Runs safely in background.
  /// Deletes [slimshot_temp_] files older than 24 hours.
  static Future<void> cleanupStartup() async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (!tempDir.existsSync()) return;

      final now = DateTime.now();
      final files = tempDir.listSync();

      int deletedCount = 0;

      for (var file in files) {
        if (file is File) {
          final filename = file.uri.pathSegments.last;
          if (filename.startsWith(filePrefix)) {
            final lastModified = await file.lastModified();
            final difference = now.difference(lastModified);

            if (difference.inHours >= 1) {
              await file.delete();
              deletedCount++;
            }
          }
        }
      }
      debugPrint("🧹 Startup cleanup: Removed $deletedCount old temp files.");
    } catch (e) {
      debugPrint("⚠️ Startup cleanup failed: $e");
    }
  }

  /// Deletes a specific file safely.
  static Future<void> deleteFile(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        debugPrint("🗑️ Deleted temp file: $path");
      }
    } catch (e) {
      debugPrint("⚠️ Failed to delete file: $e");
    }
  }

  /// Deletes ALL slimshot temp files (for Settings > Clear Cache).
  static Future<int> clearCache() async {
    int count = 0;
    try {
      final tempDir = await getTemporaryDirectory();
      if (!tempDir.existsSync()) return 0;

      final files = tempDir.listSync();
      for (var file in files) {
        if (file is File) {
          final filename = file.uri.pathSegments.last;
          if (filename.startsWith(filePrefix) || filename.contains('ffmpeg')) {
            await file.delete();
            count++;
          }
        }
      }
      debugPrint("🧹 Manual cache clear: Removed $count files.");
    } catch (e) {
      debugPrint("⚠️ Clear cache failed: $e");
    }
    return count;
  }
}
