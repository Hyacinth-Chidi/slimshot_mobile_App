import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../../models/editor_timeline.dart';
import 'effect_catalog.dart';
import 'effect_preview_layout.dart';

/// Decodes an effect's atlas into a picture the tile owns.
///
/// Deliberately not `Image.memory`, which puts every decoded picture into
/// Flutter's shared image cache — up to 100 MB held until something evicts
/// it. A `ui.Image` decoded here has one owner, the stage, and one `dispose`.
typedef EffectAtlasDecoder = Future<ui.Image> Function(Uint8List bytes);

/// The default decoder: the bytes, whole, no resize — an atlas is already
/// drawn at its final size.
Future<ui.Image> decodeEffectAtlas(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}

/// What the engine answers when asked to draw an effect's preview atlas.
sealed class EffectPreviewResult {
  const EffectPreviewResult();
}

/// The atlas, as an encoded picture.
final class EffectPreviewAtlas extends EffectPreviewResult {
  const EffectPreviewAtlas(this.bytes);
  final Uint8List bytes;
}

/// This effect cannot be drawn on this phone — a program that would not
/// build, a buffer refused, an effect the engine does not know. Remembered:
/// asking again would only fail again.
final class EffectPreviewFailed extends EffectPreviewResult {
  const EffectPreviewFailed();
}

/// Not now — no renderer yet, an export holding it, the editor closing.
/// Never remembered: the next ask draws it.
final class EffectPreviewBusy extends EffectPreviewResult {
  const EffectPreviewBusy();
}

/// Draws [bar]'s preview atlas.
typedef EffectPreviewRenderer = Future<EffectPreviewResult> Function(
  EditorTimelineEffect bar,
);

/// One tile's claim on an effect's atlas. [atlas] completes with the encoded
/// picture, or null when there is none to show — failed, busy, timed out, or
/// withdrawn before it was drawn.
class EffectPreviewTicket {
  EffectPreviewTicket._(this.atlas, this._onWithdraw);

  final Future<Uint8List?> atlas;
  final void Function() _onWithdraw;
  bool _withdrawn = false;

  /// The tile no longer wants it. An ask nobody wants any more is dropped
  /// before it is drawn; one already drawing finishes and is kept.
  void withdraw() {
    if (_withdrawn) return;
    _withdrawn = true;
    _onWithdraw();
  }
}

class _Ask {
  _Ask(this.effectId);
  final String effectId;
  final Completer<Uint8List?> completer = Completer<Uint8List?>();
  int tickets = 0;
  bool started = false;
}

/// The Effects sheet's preview atlases, drawn by the engine and kept for the
/// session.
///
/// **One drawing at a time**: the engine draws on the GL thread the live
/// canvas runs on, so a category asked at once would queue a burst in front
/// of it. A second ask for an effect shares the first. An ask whose tiles are
/// all gone before it starts is dropped, so scrolling through a category or
/// closing the sheet never leaves effects being drawn for nobody. A drawing
/// that does not answer within [timeout] counts as busy, so one lost answer
/// cannot stop every tile after it.
///
/// **Failed is remembered, busy is not**: an effect that cannot be drawn
/// keeps its icon for the session; one the engine was too busy for is drawn
/// the next time a tile asks.
class EffectPreviewAtlases {
  EffectPreviewAtlases(
    this._render, {
    this.timeout = const Duration(seconds: 10),
  });

  final EffectPreviewRenderer _render;
  final Duration timeout;

  final Map<String, Uint8List> _atlases = {};
  final Set<String> _failed = {};
  final Map<String, _Ask> _asks = {};
  final List<String> _queue = [];
  bool _drawing = false;

  /// [effectId]'s atlas if this session has drawn it.
  Uint8List? peek(String effectId) => _atlases[effectId];

  /// Whether [effectId] could not be drawn.
  bool hasFailed(String effectId) => _failed.contains(effectId);

  /// A claim on [effectId]'s atlas, drawing it if this session has not.
  EffectPreviewTicket request(String effectId) {
    final ready = _atlases[effectId];
    if (ready != null) return EffectPreviewTicket._(Future.value(ready), () {});
    if (_failed.contains(effectId)) {
      return EffectPreviewTicket._(Future.value(null), () {});
    }
    if (videoEffectById(effectId) == null) {
      _failed.add(effectId);
      return EffectPreviewTicket._(Future.value(null), () {});
    }
    final ask = _asks.putIfAbsent(effectId, () {
      _queue.add(effectId);
      return _Ask(effectId);
    });
    ask.tickets++;
    final ticket =
        EffectPreviewTicket._(ask.completer.future, () => _withdraw(ask));
    _pump();
    return ticket;
  }

  /// Drops every atlas held — for memory pressure. Tiles on screen keep the
  /// pictures they decoded; failures are kept, since they would fail again.
  void clear() => _atlases.clear();

  void _withdraw(_Ask ask) {
    ask.tickets--;
    if (ask.tickets > 0 || ask.started) return;
    _queue.remove(ask.effectId);
    _asks.remove(ask.effectId);
    ask.completer.complete(null);
  }

  void _pump() {
    if (_drawing || _queue.isEmpty) return;
    final ask = _asks[_queue.removeAt(0)]!;
    ask.started = true;
    _drawing = true;
    unawaited(_draw(ask));
  }

  Future<void> _draw(_Ask ask) async {
    EffectPreviewResult result;
    try {
      // Re-wrapped as a future of exactly this type: a renderer that answers
      // with a narrower one (`Future<Never>` from a closure that throws) would
      // make `timeout`'s fallback a type error, and the drawing's own error
      // would then reach nothing and escape. (`Future.sync` hands such a
      // future back untouched, so it cannot do this.)
      final Future<EffectPreviewResult> drawing =
          _render(effectPreviewSampleBar(videoEffectById(ask.effectId)!))
              .then((answer) => answer);
      result = await drawing.timeout(
        timeout,
        onTimeout: () => const EffectPreviewBusy(),
      );
    } catch (_) {
      result = const EffectPreviewBusy();
    }
    _asks.remove(ask.effectId);
    switch (result) {
      case EffectPreviewAtlas(:final bytes):
        _atlases[ask.effectId] = bytes;
        ask.completer.complete(bytes);
      case EffectPreviewFailed():
        _failed.add(ask.effectId);
        ask.completer.complete(null);
      case EffectPreviewBusy():
        ask.completer.complete(null);
    }
    _drawing = false;
    _pump();
  }
}
