import 'dart:async';
import 'dart:collection';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/utils/file_utils.dart';
import '../logic/preview_text/preview_text_atlas_key.dart';
import '../logic/preview_text/preview_text_rules.dart';
import '../models/editor_timeline.dart';
import '../models/text_overlay_model.dart';
import 'text_atlas_overlay.dart';
import 'text_overlay_rasterizer.dart';

/// Makes one text's atlas — `TextOverlayRasterizer.rasterizeAtlas` in the
/// app, a fake in tests.
typedef PreviewAtlasRasterizer = Future<RasterizedTextAtlas?> Function(
    TextOverlayModel text, Size canvasSize, double rasterScale);

/// How long the text list must stand still before atlases are made: a drag
/// or a word being typed changes it every frame, and an atlas made mid-word
/// is thrown away by the next keystroke.
const Duration kPreviewAtlasSettle = Duration(milliseconds: 250);

/// How long an atlas file outlives its last use, so the engine — which may
/// still be decoding it off its own thread — never has it pulled away.
const Duration kPreviewAtlasFileGrace = Duration(seconds: 2);

/// How many atlases are kept. Older looks stay so an undo finds its atlas
/// ready; the least recently used go first, never one being sent.
const int kPreviewAtlasCacheSize = 120;

/// The preview's text atlases, and who draws each text.
///
/// The engine draws a text in the same frame as the picture, at that frame's
/// own time — the export's drawing — so a caption cannot trail its words.
/// Flutter draws the text being edited, so every change shows the frame it is
/// made, and every text the engine has not confirmed. **No text is drawn by
/// nobody**: a text joins [engineDrawn] two frames after the engine reported
/// its current atlas, and leaves it the moment anything changes that.
///
/// Atlases are made in the background, one at a time with a frame between
/// them, nearest the playhead first, and only once the text list has stood
/// still for [kPreviewAtlasSettle].
class PreviewTextAtlases extends ChangeNotifier {
  PreviewTextAtlases({
    required PreviewAtlasRasterizer rasterize,
    required bool Function(String fontFamily) fontReady,
    Future<void> Function()? nextFrame,
    Future<void> Function(String path)? deleteFile,
    Duration settle = kPreviewAtlasSettle,
    Duration fileGrace = kPreviewAtlasFileGrace,
    int cacheSize = kPreviewAtlasCacheSize,
  })  : _rasterize = rasterize,
        _fontReady = fontReady,
        _nextFrame = nextFrame ?? (() => SchedulerBinding.instance.endOfFrame),
        _deleteFile = deleteFile ?? FileUtils.deleteFile,
        _settle = settle,
        _fileGrace = fileGrace,
        _cacheSize = cacheSize;

  final PreviewAtlasRasterizer _rasterize;
  final bool Function(String fontFamily) _fontReady;
  final Future<void> Function() _nextFrame;
  final Future<void> Function(String path) _deleteFile;
  final Duration _settle;
  final Duration _fileGrace;
  final int _cacheSize;

  // What the editor last said.
  List<TextOverlayModel> _texts = const [];
  double _playhead = 0;
  String? _selectedTextId;
  bool _isPlaying = false;
  Size? _canvas;
  Size _texture = Size.zero;
  bool _engineAvailable = false;

  /// By key, least recently used first.
  final LinkedHashMap<String, _Atlas> _atlases = LinkedHashMap();
  final Set<String> _failed = {};

  /// Per text object: an edited text is a new object — the editor never
  /// writes a text in place — so an update that only moves the playhead
  /// computes no key.
  final Expando<_KeyMemo> _keys = Expando();

  String? _inFlight;
  bool _settled = false;
  Timer? _settleTimer;
  final Map<Timer, String> _retired = {};
  bool _disposed = false;

  /// Atlas paths the engine has reported loaded and not yet lost. By path,
  /// not by entry: two texts of one look share an atlas, and one upload
  /// serves both.
  final Set<String> _engineHas = {};

  List<EditorTimelineOverlay> _payload = const [];
  final Map<String, _EntryMemo> _entries = {};

  /// The payload's visible texts: text id → its atlas path.
  Map<String, String> _shown = const {};

  final ValueNotifier<Set<String>> _engineDrawn = ValueNotifier(const {});

  /// Each text that is eligible for the engine, and which run of eligibility
  /// it is in — a join only lands if the run it waited in is unbroken.
  final Map<String, int> _eligibleRun = {};
  int _runs = 0;

  /// The texts the engine is told to draw — the export's own entries. Same
  /// instance until it changes, so callers compare by identity.
  List<EditorTimelineOverlay> get payload => _payload;

  /// Model ids of the texts the engine draws. The text layer paints nothing
  /// for them, and keeps every gesture and handle.
  ValueListenable<Set<String>> get engineDrawn => _engineDrawn;

  void update({
    required List<TextOverlayModel> texts,
    required double playhead,
    required String? selectedTextId,
    required bool isPlaying,
    required Size? canvasSize,
    required Size textureSize,
    required bool engineAvailable,
  }) {
    if (_disposed) return;
    final textsChanged = !identical(texts, _texts);
    _texts = texts;
    _playhead = playhead;
    _selectedTextId = selectedTextId;
    _isPlaying = isPlaying;
    _canvas = canvasSize;
    _texture = textureSize;
    _engineAvailable = engineAvailable;

    if (textsChanged) {
      _settled = false;
      _settleTimer?.cancel();
      _settleTimer = Timer(_settle, () {
        _settled = true;
        _pump();
      });
    }
    _refresh();
    _pump();
  }

  /// The engine has the atlas at [path] loaded and draws its text whenever
  /// it is on screen.
  void engineReady(String entryId, String path) {
    if (_disposed || !_engineHas.add(path)) return;
    _refresh();
  }

  /// The engine can no longer draw from [path] — released, evicted by an
  /// export, or unreadable. A report about an older atlas changes nothing.
  void engineGone(String entryId, String path) {
    if (_disposed || !_engineHas.remove(path)) return;
    _refresh();
  }

  // ---------------------------------------------------------------- keys

  String _keyOf(TextOverlayModel text) {
    final ready = _fontReady(text.fontFamily);
    final memo = _keys[text];
    if (memo != null && memo.texture == _texture && memo.fontReady == ready) {
      return memo.key;
    }
    final key = previewTextAtlasKey(text, textureSize: _texture, fontReady: ready);
    _keys[text] = _KeyMemo(_texture, ready, key);
    return key;
  }

  // ----------------------------------------------------------- the payload

  void _refresh() {
    final payloadChanged = _rebuildPayload();
    final drawnChanged = _refreshDrawn();
    if (payloadChanged || drawnChanged) notifyListeners();
  }

  bool _rebuildPayload() {
    final canvas = _canvas;
    final next = <EditorTimelineOverlay>[];
    final shown = <String, String>{};
    if (_engineAvailable && canvas != null && !canvas.isEmpty) {
      final near = textsNear(
        _texts,
        _playhead,
        behind: kPreviewTextSendBehindSeconds,
        ahead: kPreviewTextSendAheadSeconds,
      );
      for (final text in _texts) {
        if (!near.contains(text.id)) continue;
        final key = _keyOf(text);
        final atlas = _atlases.remove(key);
        if (atlas == null) continue;
        _atlases[key] = atlas; // most recently used
        final hidden = isTextBeingEdited(
          text.id,
          selectedTextId: _selectedTextId,
          isPlaying: _isPlaying,
        );
        next.add(_entryFor(text, atlas, hidden, canvas));
        if (!hidden) shown[text.id] = atlas.path;
      }
      _entries.removeWhere((id, _) => !near.contains(id));
    } else {
      _entries.clear();
    }
    _shown = shown;

    if (next.length == _payload.length) {
      var same = true;
      for (var i = 0; i < next.length && same; i++) {
        same = identical(next[i], _payload[i]);
      }
      if (same) return false;
    }
    _payload = List.unmodifiable(next);
    return true;
  }

  EditorTimelineOverlay _entryFor(
    TextOverlayModel text,
    _Atlas atlas,
    bool hidden,
    Size canvas,
  ) {
    final memo = _entries[text.id];
    if (memo != null &&
        identical(memo.text, text) &&
        memo.path == atlas.path &&
        memo.hidden == hidden &&
        memo.canvas == canvas) {
      return memo.entry;
    }
    final entry = textAtlasOverlayEntry(
      text,
      atlas.atlas,
      canvas,
      atlasCanvasSize: atlas.canvas,
      hidden: hidden,
    );
    _entries[text.id] = _EntryMemo(text, atlas.path, hidden, canvas, entry);
    return entry;
  }

  // ------------------------------------------------------------ who draws

  bool _refreshDrawn() {
    final eligible = <String>{
      for (final shown in _shown.entries)
        if (_engineHas.contains(shown.value)) shown.key,
    };
    _eligibleRun.removeWhere((id, _) => !eligible.contains(id));
    for (final id in eligible) {
      if (_eligibleRun.containsKey(id)) continue;
      final run = ++_runs;
      _eligibleRun[id] = run;
      unawaited(_join(id, run));
    }
    final kept = _engineDrawn.value.where(eligible.contains).toSet();
    return _setDrawn(kept);
  }

  /// Two frames after the engine confirmed it: by then the frame the engine
  /// drew the text into has reached the screen, so Flutter can stop drawing
  /// it without a frame in which nobody does.
  Future<void> _join(String id, int run) async {
    await _nextFrame();
    await _nextFrame();
    if (_disposed || _eligibleRun[id] != run) return;
    if (_setDrawn({..._engineDrawn.value, id})) notifyListeners();
  }

  bool _setDrawn(Set<String> next) {
    if (setEquals(next, _engineDrawn.value)) return false;
    _engineDrawn.value = Set.unmodifiable(next);
    return true;
  }

  // ---------------------------------------------------------- preparation

  void _pump() {
    if (_disposed || _inFlight != null || !_settled || !_engineAvailable) return;
    final canvas = _canvas;
    if (canvas == null || canvas.isEmpty) return;
    final next = _nextToPrepare();
    if (next == null) return;
    final (text, key) = next;
    _inFlight = key;

    final scale = previewRasterScale(textureSize: _texture, canvasSize: canvas);
    Future<RasterizedTextAtlas?> job;
    try {
      job = _rasterize(text.copyWith(scale: previewAtlasScale(text)), canvas, scale);
    } catch (_) {
      job = Future.value(null);
    }
    unawaited(
      job
          .catchError((Object _) => null)
          .then((atlas) => _landed(key, atlas, canvas)),
    );
  }

  (TextOverlayModel, String)? _nextToPrepare() {
    final ids = textsNear(
      _texts,
      _playhead,
      behind: kPreviewTextPrepareBehindSeconds,
      ahead: kPreviewTextPrepareAheadSeconds,
    );
    if (ids.isEmpty) return null;
    final byId = {
      for (final t in _texts)
        if (ids.contains(t.id)) t.id: t,
    };
    for (final id in previewAtlasOrder(byId.values, _playhead)) {
      final text = byId[id]!;
      final key = _keyOf(text);
      if (_atlases.containsKey(key) || _failed.contains(key)) continue;
      return (text, key);
    }
    return null;
  }

  Future<void> _landed(String key, RasterizedTextAtlas? atlas, Size canvas) async {
    if (_disposed) {
      if (atlas != null) unawaited(_deleteFile(atlas.pngPath));
      return;
    }
    if (!_isWanted(key)) {
      // The text changed while this was being drawn.
      if (atlas != null) unawaited(_deleteFile(atlas.pngPath));
    } else if (atlas == null || atlas.glyphs.isEmpty) {
      // Not retried until the text changes: drawing it again would fail
      // again, every frame. Flutter draws it meanwhile, as it always has.
      _failed.add(key);
      if (atlas != null) unawaited(_deleteFile(atlas.pngPath));
    } else {
      _atlases[key] = _Atlas(atlas, canvas);
      _refresh();
      _evict();
    }
    await _nextFrame();
    _inFlight = null;
    _pump();
  }

  bool _isWanted(String key) {
    final ids = textsNear(
      _texts,
      _playhead,
      behind: kPreviewTextPrepareBehindSeconds,
      ahead: kPreviewTextPrepareAheadSeconds,
    );
    for (final text in _texts) {
      if (ids.contains(text.id) && _keyOf(text) == key) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------- files

  /// Drops the least recently used atlases past the cache's size — never one
  /// the payload names — and deletes each file after the grace.
  void _evict() {
    if (_atlases.length <= _cacheSize) return;
    final sent = {for (final e in _payload) e.path};
    final victims = <String>[];
    var excess = _atlases.length - _cacheSize;
    for (final entry in _atlases.entries) {
      if (excess == 0) break;
      if (sent.contains(entry.value.path)) continue;
      victims.add(entry.key);
      excess--;
    }
    for (final key in victims) {
      _retire(_atlases.remove(key)!.path);
    }
  }

  void _retire(String path) {
    late final Timer timer;
    timer = Timer(_fileGrace, () {
      _retired.remove(timer);
      unawaited(_deleteFile(path));
    });
    _retired[timer] = path;
  }

  @override
  void dispose() {
    _disposed = true;
    _settleTimer?.cancel();
    for (final retired in _retired.entries) {
      retired.key.cancel();
      unawaited(_deleteFile(retired.value));
    }
    _retired.clear();
    for (final atlas in _atlases.values) {
      unawaited(_deleteFile(atlas.path));
    }
    _atlases.clear();
    _engineDrawn.dispose();
    super.dispose();
  }
}

class _Atlas {
  _Atlas(this.atlas, this.canvas);

  final RasterizedTextAtlas atlas;

  /// The canvas it was made at — its box is measured against it.
  final Size canvas;

  String get path => atlas.pngPath;
}

class _KeyMemo {
  const _KeyMemo(this.texture, this.fontReady, this.key);

  final Size texture;
  final bool fontReady;
  final String key;
}

class _EntryMemo {
  const _EntryMemo(this.text, this.path, this.hidden, this.canvas, this.entry);

  final TextOverlayModel text;
  final String path;
  final bool hidden;
  final Size canvas;
  final EditorTimelineOverlay entry;
}
