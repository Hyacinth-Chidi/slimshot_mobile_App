import 'dart:async';
import 'dart:typed_data';

import '../tile_preview_store.dart';

/// Draws one transition's tile frames — encoded pictures, first to last — or
/// answers null when it could not.
typedef TransitionPreviewRenderer = Future<List<Uint8List>?> Function(
  String transitionName,
);

/// How many frames a tile plays a transition in.
const int kTransitionPreviewFrameCount = 16;

/// A tile's frame size in pixels, a little wider than tall like the grid.
const int kTransitionPreviewWidth = 192;
const int kTransitionPreviewHeight = 176;

/// How a tile's loop is shared out, as fractions of one turn of the clock:
/// a rest on the first picture, the transition, then a rest on the second —
/// so the eye sees where it starts and where it lands, not only the motion.
const double kTransitionPreviewLead = 0.2;
const double kTransitionPreviewPlay = 0.6;

/// The frame a tile shows at [phase] (0..1) of its loop.
int previewFrameAt(double phase, int frameCount) {
  if (frameCount <= 1) return 0;
  final t = ((phase - kTransitionPreviewLead) / kTransitionPreviewPlay)
      .clamp(0.0, 1.0);
  return (t * (frameCount - 1)).round();
}

/// The transitions sheet's tile frames, drawn by the engine — once per build
/// of the app, given a [TilePreviewStore] — and held for the session.
///
/// **One at a time**: the renderer draws them on the GL thread the live
/// preview runs on, so a whole category asked at once would queue a burst of
/// work in front of the canvas. Each transition is drawn once, a second ask
/// while it is drawing shares the first, and one that could not be drawn is
/// remembered — its tile keeps the icon rather than asking again on every
/// rebuild.
///
/// **Kept on the phone**: frames drawn are handed to the store, and a launch
/// that finds a transition's frames there reads them back instead of asking
/// the engine — straight away, never queued behind a drawing, since reading a
/// file takes nothing from the canvas. Frames that will not read back are
/// forgotten and drawn again. A failure is never kept: the next launch tries
/// again.
class TransitionPreviewFrames {
  TransitionPreviewFrames(this._render, {TilePreviewStore? store})
      : _store = store;

  final TransitionPreviewRenderer _render;
  final TilePreviewStore? _store;
  final Map<String, List<Uint8List>> _frames = {};
  final Map<String, Future<List<Uint8List>?>> _inFlight = {};
  final Set<String> _failed = {};
  Future<void> _queue = Future<void>.value();

  /// The frames already drawn for [name], or null.
  List<Uint8List>? peek(String name) => _frames[name];

  /// Whether [name] was asked for and could not be drawn.
  bool hasFailed(String name) => _failed.contains(name);

  /// Whether [name]'s frames are kept on the phone: a tile waiting for them
  /// waits on a file, not on the engine, and shows no icon meanwhile.
  bool isSaved(String name) =>
      _store?.has(TilePreviewKind.transitions, name) ?? false;

  /// [name]'s frames: held, read back from the phone, or drawn.
  Future<List<Uint8List>?> request(String name) {
    final ready = _frames[name];
    if (ready != null) return Future.value(ready);
    if (_failed.contains(name)) return Future.value(null);
    final running = _inFlight[name];
    if (running != null) return running;

    final result = Completer<List<Uint8List>?>();
    _inFlight[name] = result.future;
    final store = _store;
    if (store != null && store.has(TilePreviewKind.transitions, name)) {
      unawaited(_readBack(name, store, result));
    } else {
      _draw(name, result);
    }
    return result.future;
  }

  Future<void> _readBack(
    String name,
    TilePreviewStore store,
    Completer<List<Uint8List>?> result,
  ) async {
    final bytes = await store.read(TilePreviewKind.transitions, name);
    final frames = bytes == null ? null : unpackTransitionFrames(bytes);
    if (frames == null) {
      await store.forget(TilePreviewKind.transitions, name);
      _draw(name, result);
      return;
    }
    _inFlight.remove(name);
    _frames[name] = frames;
    result.complete(frames);
  }

  void _draw(String name, Completer<List<Uint8List>?> result) {
    _queue = _queue.then((_) async {
      List<Uint8List>? frames;
      try {
        frames = await _render(name);
      } catch (_) {
        frames = null;
      }
      _inFlight.remove(name);
      if (frames == null || frames.isEmpty) {
        _failed.add(name);
        result.complete(null);
      } else {
        _frames[name] = frames;
        result.complete(frames);
        final store = _store;
        if (store != null) {
          unawaited(store.write(
            TilePreviewKind.transitions,
            name,
            packTransitionFrames(frames),
          ));
        }
      }
    });
  }
}

/// A transition's frames as the one file the store keeps: each frame's
/// length as four big-endian bytes, then the frame.
Uint8List packTransitionFrames(List<Uint8List> frames) {
  final packed = BytesBuilder(copy: false);
  for (final frame in frames) {
    packed.add((ByteData(4)..setUint32(0, frame.length)).buffer.asUint8List());
    packed.add(frame);
  }
  return packed.takeBytes();
}

/// [packTransitionFrames] undone — null for a file that is not whole: cut
/// short, run long, or holding no frame or an empty one.
List<Uint8List>? unpackTransitionFrames(Uint8List bytes) {
  final lengths = ByteData.sublistView(bytes);
  final frames = <Uint8List>[];
  var at = 0;
  while (at < bytes.length) {
    if (at + 4 > bytes.length) return null;
    final length = lengths.getUint32(at);
    at += 4;
    if (length == 0 || at + length > bytes.length) return null;
    frames.add(bytes.sublist(at, at + length));
    at += length;
  }
  return frames.isEmpty ? null : frames;
}
