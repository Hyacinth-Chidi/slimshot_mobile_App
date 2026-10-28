import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// What a kept drawing is a picture of — each kind in a folder of its own,
/// so a transition and an effect sharing a name never collide.
enum TilePreviewKind { transitions, effects }

/// How a tile's picture arrives the first time the engine draws it: faded in
/// over the icon that stood in for it, never switched in. One read back from
/// the phone replaces a bare stage and needs no fade.
const Duration kTilePictureFadeIn = Duration(milliseconds: 150);

/// The Transitions and Effects sheets' tile drawings, kept on the phone so
/// each is drawn once per build of the app rather than once per launch — the
/// icon a tile shows while the engine draws it is then seen the first time
/// only.
///
/// Kept in `<app support>/tile_previews/<build>/<kind>/<name>.bin`, beside
/// the font previews and, like them, left alone by Clear Cache. **One build's
/// drawings are never another's**: the folder is named for the build that
/// drew them — its version code, when it was installed, and what a drawing
/// is made of (`kTilePreviewFormat`) — and every other build's folder is
/// cleared away when this one is found. So an update, or a debug rebuild with
/// a changed shader, draws its tiles afresh once, and a phone keeps one
/// build's worth. Without a build to name the folder by, nothing is kept or
/// served.
///
/// **Nothing waits on it**: [has] answers at once, false until [prepare] has
/// read the folder, so a tile asked for before then is simply drawn, as it
/// always was. Written whole or not at all (`.part`, then renamed); a
/// leftover `.part` from a launch that died mid-write is cleared. It never
/// throws: a phone that will not keep the drawings draws them each launch.
class TilePreviewStore {
  TilePreviewStore({
    required Future<String?> Function() version,
    Future<Directory> Function()? supportDirectory,
  })  : _version = version,
        _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final Future<String?> Function() _version;
  final Future<Directory> Function() _supportDirectory;

  Future<void>? _prepared;
  Directory? _dir;
  final Map<TilePreviewKind, Set<String>> _saved = {
    for (final kind in TilePreviewKind.values) kind: <String>{},
  };
  final Set<Future<void>> _writing = {};

  /// Finds this build's folder and what it holds, then clears every other
  /// build's away. Run once; every later call shares the first.
  Future<void> prepare() => _prepared ??= _prepare();

  Future<void> _prepare() async {
    final Directory root;
    final String version;
    try {
      final named = await _version();
      if (named == null || !isPlainTileName(named)) return;
      version = named;
      root = Directory('${(await _supportDirectory()).path}/tile_previews');
      final dir = Directory('${root.path}/$version');
      final found = <TilePreviewKind, Set<String>>{};
      for (final kind in TilePreviewKind.values) {
        final folder = Directory('${dir.path}/${kind.name}');
        await folder.create(recursive: true);
        final names = found[kind] = <String>{};
        await for (final entry in folder.list()) {
          final name = _baseName(entry.path);
          if (entry is File && name.endsWith('.bin')) {
            names.add(name.substring(0, name.length - '.bin'.length));
          } else {
            // A drawing a launch died part-way through writing.
            await _delete(entry);
          }
        }
      }
      for (final kind in TilePreviewKind.values) {
        _saved[kind]!.addAll(found[kind]!);
      }
      _dir = dir;
    } catch (_) {
      return;
    }
    // Known now; what other builds left behind can go at its own pace.
    try {
      await for (final entry in root.list()) {
        if (_baseName(entry.path) != version) await _delete(entry);
      }
    } catch (_) {}
  }

  /// Whether [name]'s drawing is on the phone. False until [prepare] has
  /// read the folder.
  bool has(TilePreviewKind kind, String name) =>
      _dir != null && _saved[kind]!.contains(name);

  /// [name]'s kept drawing, or null.
  Future<Uint8List?> read(TilePreviewKind kind, String name) async {
    await prepare();
    final dir = _dir;
    if (dir == null || !has(kind, name)) return null;
    try {
      return await _file(dir, kind, name).readAsBytes();
    } catch (_) {
      _saved[kind]!.remove(name);
      return null;
    }
  }

  /// Keeps [bytes] as [name]'s drawing. A drawing that cannot be kept is
  /// drawn again next launch; nothing waits on this.
  Future<void> write(TilePreviewKind kind, String name, Uint8List bytes) {
    final writing = _write(kind, name, bytes);
    _writing.add(writing);
    return writing.whenComplete(() => _writing.remove(writing));
  }

  Future<void> _write(
    TilePreviewKind kind,
    String name,
    Uint8List bytes,
  ) async {
    if (!isPlainTileName(name) || bytes.isEmpty) return;
    await prepare();
    final dir = _dir;
    if (dir == null) return;
    try {
      final file = _file(dir, kind, name);
      final part = File('${file.path}.part');
      await part.writeAsBytes(bytes, flush: true);
      await part.rename(file.path);
      _saved[kind]!.add(name);
    } catch (_) {}
  }

  /// Drops [name]'s kept drawing — one that did not read back as a picture.
  Future<void> forget(TilePreviewKind kind, String name) async {
    _saved[kind]!.remove(name);
    final dir = _dir;
    if (dir == null || !isPlainTileName(name)) return;
    await _delete(_file(dir, kind, name));
  }

  /// Completes once every drawing handed to [write] so far is on the phone.
  Future<void> flush() => Future.wait([..._writing]);

  File _file(Directory dir, TilePreviewKind kind, String name) =>
      File('${dir.path}/${kind.name}/$name.bin');

  static Future<void> _delete(FileSystemEntity entry) async {
    try {
      await entry.delete(recursive: true);
    } catch (_) {}
  }

  /// The last part of [path], whichever separator the platform listed it
  /// with.
  static String _baseName(String path) {
    final cut = path.lastIndexOf(RegExp(r'[/\\]'));
    return cut < 0 ? path : path.substring(cut + 1);
  }
}

/// Whether [name] is safe as a file or folder name: letters, digits, `_`
/// and `-` only — as every transition and effect id is.
bool isPlainTileName(String name) => RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(name);
