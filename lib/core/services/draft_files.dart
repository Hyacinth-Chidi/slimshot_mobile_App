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

  /// Where the draft's own sound lives: audio taken out of a video and
  /// voiceovers recorded for it. Never temp, never a picker's cache — the
  /// track points here for as long as the draft exists.
  static Future<Directory> audioDir(String draftId, {Directory? root}) async {
    final dir = Directory('${(await draftDir(draftId, root: root)).path}/audio');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// The prefix of a voice Text to speech made (`tts_<textId>_<ms>.mp3`).
  /// Not `voice_`: Record names its takes `voice_<ms>.m4a`, in the same
  /// folder.
  static const String voiceFilePrefix = 'tts_';

  /// Deletes the draft's voices from text that no track in [keep] uses —
  /// called when the editor closes, after its last save.
  ///
  /// Voicing a text again takes its earlier clip off the timeline at once,
  /// but not its file: Undo brings the clip back and it must still play. Once
  /// the editor closes there is no undo left, so a voice no track points at
  /// is nobody's. Only `tts_` files are touched — a recorded take or a video's
  /// sound in the same folder is left alone — and a `.part` a download left
  /// behind goes with them. Compared by file name, so a path stored with
  /// other separators still keeps its file.
  static Future<void> sweepVoices(
    String draftId, {
    required Set<String> keep,
    Directory? root,
  }) async {
    final kept = {for (final path in keep) _nameOf(path)};
    final dir = Directory('${(await _root(root)).path}/drafts/$draftId/audio');
    try {
      if (!await dir.exists()) return;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = _nameOf(entity.path);
        if (!name.startsWith(voiceFilePrefix) || kept.contains(name)) continue;
        try {
          await entity.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  static String _nameOf(String path) => path.split(RegExp(r'[/\\]')).last;

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
