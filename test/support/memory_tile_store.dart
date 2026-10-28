import 'dart:typed_data';

import 'package:slimshotai/features/video_editor/logic/tile_preview_store.dart';

/// A [TilePreviewStore] held in memory, for widget tests: under the test
/// clock a real file never finishes reading, so a tile kept "on the phone"
/// is kept here instead. Every answer arrives on a microtask.
class MemoryTileStore implements TilePreviewStore {
  final Map<TilePreviewKind, Map<String, Uint8List>> saved = {
    for (final kind in TilePreviewKind.values) kind: <String, Uint8List>{},
  };

  @override
  Future<void> prepare() async {}

  @override
  bool has(TilePreviewKind kind, String name) =>
      saved[kind]!.containsKey(name);

  @override
  Future<Uint8List?> read(TilePreviewKind kind, String name) async =>
      saved[kind]![name];

  @override
  Future<void> write(TilePreviewKind kind, String name, Uint8List bytes) async {
    saved[kind]![name] = bytes;
  }

  @override
  Future<void> forget(TilePreviewKind kind, String name) async {
    saved[kind]!.remove(name);
  }

  @override
  Future<void> flush() async {}
}
