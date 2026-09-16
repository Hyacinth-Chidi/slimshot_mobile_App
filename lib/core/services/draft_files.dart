import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Where a draft's own files live, and how they die with it.
///
/// A draft is JSON in preferences that *points at* files: the proxies its
/// reversed or gap-cut clips play from, its cover, its frozen frames, its
/// background photo. Those used to be scattered — proxies in the temp
/// directory, which a startup cleanup sweeps by prefix, so a draft reopened a
/// week later pointed at nothing — and none of them went when the draft did.
///
/// Now a draft owns a folder under the documents directory, `drafts/<id>/`,
/// and everything rendered *for* it lives there or is named for it, so one
/// call deletes all of it with the draft. Documents, not temp, because the OS
/// may reclaim temp whenever it likes and a draft is the user's work.
class DraftFiles {
  DraftFiles._();

  /// The documents directory, or [root] when a test supplies one.
  static Future<Directory> _root(Directory? root) async =>
      root ?? await getApplicationDocumentsDirectory();

  /// The draft's own folder, created if absent.
  static Future<Directory> draftDir(String draftId, {Directory? root}) async {
    final dir = Directory('${(await _root(root)).path}/drafts/$draftId');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Where the draft's playback and reverse proxies are rendered to.
  static Future<Directory> proxiesDir(String draftId, {Directory? root}) async {
    final dir = Directory('${(await draftDir(draftId, root: root)).path}/proxies');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Root-level files named for a draft: the cover, frozen frames and the
  /// background photo, which predate the folder and are named
  /// `<kind>_<draftId>_<stamp>.<ext>`.
  static const List<String> _rootPrefixes = ['cover_', 'freeze_', 'bg_'];

  /// Deletes the draft's folder and every root-level file named for it.
  /// Nothing else: another draft's files, or a file whose name merely contains
  /// the id, are left alone.
  static Future<void> deleteAll(String draftId, {Directory? root}) async {
    final base = await _root(root);
    final dir = Directory('${base.path}/drafts/$draftId');
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
    try {
      await for (final entity in base.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = entity.uri.pathSegments.last;
        final ours = _rootPrefixes.any((p) => name.startsWith('$p${draftId}_'));
        if (ours) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  /// Whether a stored path still points at a file. A null path is not a file.
  static bool exists(String? path) => path != null && File(path).existsSync();
}
