import 'dart:async';
import 'dart:typed_data';

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

/// The transitions sheet's tile frames, drawn by the engine and kept for the
/// session.
///
/// **One at a time**: the renderer draws them on the GL thread the live
/// preview runs on, so a whole category asked at once would queue a burst of
/// work in front of the canvas. Each transition is drawn once, a second ask
/// while it is drawing shares the first, and one that could not be drawn is
/// remembered — its tile keeps the icon rather than asking again on every
/// rebuild.
class TransitionPreviewFrames {
  TransitionPreviewFrames(this._render);

  final TransitionPreviewRenderer _render;
  final Map<String, List<Uint8List>> _frames = {};
  final Map<String, Future<List<Uint8List>?>> _inFlight = {};
  final Set<String> _failed = {};
  Future<void> _queue = Future<void>.value();

  /// The frames already drawn for [name], or null.
  List<Uint8List>? peek(String name) => _frames[name];

  /// Whether [name] was asked for and could not be drawn.
  bool hasFailed(String name) => _failed.contains(name);

  /// [name]'s frames, drawing them if this session has not yet.
  Future<List<Uint8List>?> request(String name) {
    final ready = _frames[name];
    if (ready != null) return Future.value(ready);
    if (_failed.contains(name)) return Future.value(null);
    final running = _inFlight[name];
    if (running != null) return running;

    final result = Completer<List<Uint8List>?>();
    _inFlight[name] = result.future;
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
      }
    });
    return result.future;
  }
}
