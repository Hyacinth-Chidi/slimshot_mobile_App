import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../../core/services/draft_service.dart';
import 'camera_roll.dart';

/// At launch: what a killed app left in the camera folder goes — a photo
/// caught on its way to the gallery — except every shot a draft points at
/// (matched against each draft's whole saved form, so a shot used as a clip,
/// an overlay or anything later is kept alike) and every shot the camera's
/// roll keeps there because storage access was off.
Future<void> sweepCameraFiles() async {
  final launch = DateTime.now();
  try {
    final files = await CameraFiles.open();
    if (!await files.directory.exists()) return;
    final drafts = await DraftService.getDrafts();
    final referenced = drafts.map((draft) => jsonEncode(draft.toJson())).join('\n');
    final rolled = await CameraRoll.storedPaths();
    await files.sweep(
      keep: (path) => referenced.contains(path) || rolled.contains(path),
      before: launch,
    );
  } catch (_) {
    // A sweep that cannot run leaves the files for the next launch.
  }
}

/// Where the camera writes: `<documents>/camera/`, the app's own folder.
///
/// Not the temporary folder, because a shot opened in the editor becomes a
/// draft's clip and must outlive the launch cleanup there; not a draft's
/// folder, because there is no draft until the editor makes one. A shot the
/// review leaves without editing is deleted then ([delete]); what a killed
/// app left behind goes at the next launch ([sweep]), keeping every shot a
/// draft points at.
class CameraFiles {
  CameraFiles(this.directory);

  final Directory directory;

  static Future<CameraFiles> open() async {
    final documents = await getApplicationDocumentsDirectory();
    return CameraFiles(Directory('${documents.path}/camera'));
  }

  /// A path for a new shot — `IMG_…jpg`, `VID_…mp4` — named for the moment,
  /// never one already there.
  Future<String> newShotPath(String extension, {DateTime? now}) async {
    await directory.create(recursive: true);
    final at = now ?? DateTime.now();
    final kind = extension == 'jpg' ? 'IMG' : 'VID';
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${at.year}${two(at.month)}${two(at.day)}_'
        '${two(at.hour)}${two(at.minute)}${two(at.second)}_'
        '${at.millisecond.toString().padLeft(3, '0')}';
    var path = '${directory.path}/${kind}_$stamp.$extension';
    for (var n = 2; await File(path).exists(); n++) {
      path = '${directory.path}/${kind}_${stamp}_$n.$extension';
    }
    return path;
  }

  /// Deletes [paths] that lie inside the camera folder; anything outside it
  /// is the user's and is left alone.
  Future<void> delete(Iterable<String> paths) async {
    final inside = await _insidePrefix();
    if (inside == null) return;
    for (final path in paths) {
      try {
        final file = File(path);
        if (!await file.exists()) continue;
        if (!(await file.resolveSymbolicLinks()).startsWith(inside)) continue;
        await file.delete();
      } on FileSystemException {
        // Gone already, or not ours to delete: nothing to say.
      }
    }
  }

  /// Deletes every shot written before [before] that [keep] does not claim:
  /// what a killed app left behind. A shot newer than the launch is one this
  /// session is still using.
  Future<void> sweep({
    required bool Function(String path) keep,
    required DateTime before,
  }) async {
    if (!await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      try {
        // Named as [newShotPath] names it, so a draft's copy of the path
        // matches whatever separator the listing joined with.
        if (keep('${directory.path}/${entity.uri.pathSegments.last}')) continue;
        if (!(await entity.lastModified()).isBefore(before)) continue;
        await entity.delete();
      } on FileSystemException {
        // Taken in the meantime: nothing left to do.
      }
    }
  }

  Future<String?> _insidePrefix() async {
    if (!await directory.exists()) return null;
    final resolved = await directory.resolveSymbolicLinks();
    return resolved.endsWith(Platform.pathSeparator) ? resolved : '$resolved${Platform.pathSeparator}';
  }
}
