import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Deletes paths among the app's own temporary files — [FileUtils.deleteTempFiles],
/// or a test's stand-in.
typedef TempFileDeleter = Future<void> Function(Iterable<String> paths);

class FileUtils {
  static const String filePrefix = 'slimshot_temp_';

  /// What an exported video is named; with [filePrefix], the app's own
  /// temporary files.
  static const String exportPrefix = 'slimshot_export_';

  /// The folder the share plugin copies a file into before handing it to
  /// the app it is shared with, emptied only by the next share.
  static const String shareCopiesFolder = 'share_plus';

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
  ///
  /// The app's temporary files — compressions, stripped photos, exports — are
  /// of no use once off screen: a saved one is in the gallery, a shared one
  /// the share plugin copied first. A result deletes its own when it is left
  /// ([deleteTempFiles]), and the launch clears what a previous session left
  /// ([cleanupStartup]). The picker's copies of a user's photos and videos
  /// are never swept by name: a draft's clips play from them.
  /// --------------------------------------------------------------------------

  /// Whether [name] is one of the app's own temporary files.
  static bool isAppTempName(String name) =>
      name.startsWith(filePrefix) || name.startsWith(exportPrefix);

  /// Clears what the previous session left — every one of the app's own
  /// temporary files and the share plugin's copies — since nothing from a
  /// previous session is on screen any more. Only what was written before
  /// [launchedAt] (this launch, by default) goes, so a compression begun the
  /// moment the app opened keeps its file. Runs in the background; never
  /// throws.
  static Future<void> cleanupStartup({
    DateTime? launchedAt,
    Directory? tempDir,
  }) async {
    final before = launchedAt ?? DateTime.now();
    var deleted = 0;
    try {
      final dir = tempDir ?? await getTemporaryDirectory();
      if (!await dir.exists()) return;
      await for (final entry in dir.list()) {
        if (entry is File &&
            isAppTempName(_name(entry.path)) &&
            (await entry.lastModified()).isBefore(before)) {
          if (await _delete(entry)) deleted++;
        }
      }
      final copies = Directory('${dir.path}/$shareCopiesFolder');
      if (await copies.exists()) {
        await for (final entry in copies.list()) {
          if (entry is File && (await entry.lastModified()).isBefore(before)) {
            if (await _delete(entry)) deleted++;
          }
        }
      }
      debugPrint("🧹 Startup cleanup: Removed $deleted files from last time.");
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

  /// Deletes the [paths] that lie inside the app's temporary folder — a
  /// result's files, the picker's copies a screen was handed — and nothing
  /// else: a path outside it is the user's own photo or video, never the
  /// app's to remove. A picked copy's own folder goes with it once empty.
  /// Never throws.
  static Future<void> deleteTempFiles(
    Iterable<String> paths, {
    Directory? tempDir,
  }) async {
    try {
      final dir = tempDir ?? await getTemporaryDirectory();
      final root = _comparable(await dir.resolveSymbolicLinks());
      for (final path in paths.toSet()) {
        final file = File(path);
        if (!await file.exists()) continue;
        final resolved = _comparable(await file.resolveSymbolicLinks());
        if (!resolved.startsWith('$root/')) continue;
        await _delete(file);
        final folder = file.parent;
        final folderPath = _comparable(await folder.resolveSymbolicLinks());
        if (folderPath != root &&
            folderPath.startsWith('$root/') &&
            await folder.list().isEmpty) {
          await _delete(folder);
        }
      }
    } catch (e) {
      debugPrint("⚠️ Deleting temp files failed: $e");
    }
  }

  /// Deletes every one of the app's temporary files and the share plugin's
  /// copies (Settings > Clear Cache); how many went.
  static Future<int> clearCache({Directory? tempDir}) async {
    var count = 0;
    try {
      final dir = tempDir ?? await getTemporaryDirectory();
      if (!await dir.exists()) return 0;
      await for (final entry in dir.list()) {
        if (entry is! File) continue;
        final name = _name(entry.path);
        if (isAppTempName(name) || name.contains('ffmpeg')) {
          if (await _delete(entry)) count++;
        }
      }
      final copies = Directory('${dir.path}/$shareCopiesFolder');
      if (await copies.exists()) {
        await for (final entry in copies.list()) {
          if (entry is File && await _delete(entry)) count++;
        }
      }
      debugPrint("🧹 Manual cache clear: Removed $count files.");
    } catch (e) {
      debugPrint("⚠️ Clear cache failed: $e");
    }
    return count;
  }

  static Future<bool> _delete(FileSystemEntity entry) async {
    try {
      await entry.delete(recursive: entry is Directory);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// The last part of [path], whichever separator it was written with.
  static String _name(String path) {
    final cut = path.lastIndexOf(RegExp(r'[/\\]'));
    return cut < 0 ? path : path.substring(cut + 1);
  }

  /// [path] in one form for comparing: forward slashes, no trailing slash,
  /// and on Windows (where tests run) one case.
  static String _comparable(String path) {
    var normal = path.replaceAll(r'\', '/');
    while (normal.length > 1 && normal.endsWith('/')) {
      normal = normal.substring(0, normal.length - 1);
    }
    return Platform.isWindows ? normal.toLowerCase() : normal;
  }
}
