import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/services/preview_text_atlases.dart';
import 'package:slimshotai/features/video_editor/services/text_overlay_rasterizer.dart';

/// The preview's text atlases: made in the background, nearest the playhead
/// first, and handed to the engine without a text ever being drawn by
/// nobody.
void main() {
  const canvas = Size(270, 480);
  const texture = Size(720, 1280);

  TextOverlayModel text(String id, double start, double end, {String? words}) =>
      TextOverlayModel(
        id: id,
        text: words ?? id,
        startTime: Duration(milliseconds: (start * 1000).round()),
        endTime: Duration(milliseconds: (end * 1000).round()),
        referenceCanvasSize: canvas,
      );

  late _FakeRasterizer raster;
  late List<Completer<void>> waiting;
  late List<String> deleted;
  late bool fontReady;

  Future<void> nextFrame() {
    final c = Completer<void>();
    waiting.add(c);
    return c.future;
  }

  /// One frame passes: every wait on the next frame ends.
  Future<void> frame(WidgetTester tester) async {
    final now = List.of(waiting);
    waiting.clear();
    for (final c in now) {
      c.complete();
    }
    await tester.pump();
  }

  PreviewTextAtlases make({int cacheSize = kPreviewAtlasCacheSize}) => PreviewTextAtlases(
        rasterize: raster.call,
        fontReady: (_) => fontReady,
        nextFrame: nextFrame,
        deleteFile: (path) async => deleted.add(path),
        cacheSize: cacheSize,
      );

  void push(
    PreviewTextAtlases atlases,
    List<TextOverlayModel> texts, {
    double playhead = 1,
    String? selected,
    bool playing = false,
    Size? canvasSize = canvas,
    bool engine = true,
    bool scrubbing = false,
  }) =>
      atlases.update(
        texts: texts,
        playhead: playhead,
        selectedTextId: selected,
        isPlaying: playing,
        canvasSize: canvasSize,
        textureSize: texture,
        engineAvailable: engine,
        scrubbing: scrubbing,
      );

  /// Prepares [texts] and lets every frame the work waits on pass.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 260));
    for (var i = 0; i < 10; i++) {
      await frame(tester);
    }
  }

  /// The engine reports the text's current atlas, and two frames pass.
  Future<void> engineTakes(WidgetTester tester, PreviewTextAtlases atlases, String id) async {
    final entry = atlases.payload.singleWhere((e) => e.id == 'text_$id');
    atlases.engineReady(entry.id, entry.path);
    await frame(tester);
    await frame(tester);
  }

  setUp(() {
    raster = _FakeRasterizer();
    waiting = [];
    deleted = [];
    fontReady = true;
  });

  testWidgets('nothing is prepared before the edits settle', (tester) async {
    final atlases = make();
    push(atlases, [text('a', 0, 3)]);
    await tester.pump(const Duration(milliseconds: 200));
    expect(raster.calls, isEmpty);
    await tester.pump(const Duration(milliseconds: 60));
    expect(raster.calls, hasLength(1));
    atlases.dispose();
  });

  testWidgets('typing never prepares mid-word', (tester) async {
    final atlases = make();
    final a = text('a', 0, 3);
    for (var i = 0; i < 10; i++) {
      push(atlases, [a.copyWith(text: 'word$i')]);
      await tester.pump(const Duration(milliseconds: 100));
      expect(raster.calls, isEmpty, reason: 'keystroke $i');
    }
    await tester.pump(const Duration(milliseconds: 160));
    expect(raster.calls.map((t) => t.text), ['word9']);
    atlases.dispose();
  });

  testWidgets('one atlas at a time, a frame between them', (tester) async {
    raster.instant = false;
    final atlases = make();
    push(atlases, [text('a', 0, 3), text('b', 0.5, 3)]);
    await tester.pump(const Duration(milliseconds: 260));
    expect(raster.calls, hasLength(1));

    raster.completeNext();
    await tester.pump();
    expect(raster.calls, hasLength(1), reason: 'the next waits for a frame');

    await frame(tester);
    expect(raster.calls, hasLength(2));
    raster.completeNext();
    await tester.pump();
    atlases.dispose();
  });

  testWidgets('nearest first', (tester) async {
    final atlases = make();
    push(atlases, [text('c', 5, 6), text('b', 2, 3), text('a', 0.5, 1.5)], playhead: 1);
    await settle(tester);
    expect(raster.calls.map((t) => t.id), ['a', 'b', 'c']);
    atlases.dispose();
  });

  testWidgets('far texts are neither prepared nor sent', (tester) async {
    final atlases = make();
    push(atlases, [text('near', 20, 21), text('far', 60, 61)], playhead: 0);
    await settle(tester);
    expect(raster.calls.map((t) => t.id), ['near']);
    expect(atlases.payload, isEmpty, reason: '20 s is past the send window');
    atlases.dispose();
  });

  testWidgets('a prepared text rides the payload but Flutter draws it until the engine has it',
      (tester) async {
    final atlases = make();
    push(atlases, [text('a', 0, 3)]);
    await settle(tester);
    expect(atlases.payload.map((e) => e.id), ['text_a']);
    expect(atlases.engineDrawn.value, isEmpty);

    final entry = atlases.payload.single;
    atlases.engineReady(entry.id, entry.path);
    await frame(tester);
    expect(atlases.engineDrawn.value, isEmpty, reason: 'one frame is not yet two');
    await frame(tester);
    expect(atlases.engineDrawn.value, {'a'});
    atlases.dispose();
  });

  testWidgets('the edited text stays Flutter\'s and is sent hidden', (tester) async {
    final atlases = make();
    final texts = [text('a', 0, 3)];
    push(atlases, texts, selected: 'a');
    await settle(tester);
    expect(atlases.payload.single.opacity.baseValue, 0);
    await engineTakes(tester, atlases, 'a');
    expect(atlases.engineDrawn.value, isEmpty);

    push(atlases, texts, selected: 'a', playing: true);
    expect(atlases.payload.single.opacity.baseValue, 1);
    await frame(tester);
    await frame(tester);
    expect(atlases.engineDrawn.value, {'a'});
    atlases.dispose();
  });

  testWidgets('a look change hands the text back to Flutter at once', (tester) async {
    final atlases = make();
    final a = text('a', 0, 3);
    push(atlases, [a]);
    await settle(tester);
    await engineTakes(tester, atlases, 'a');
    final oldPath = atlases.payload.single.path;
    expect(atlases.engineDrawn.value, {'a'});

    push(atlases, [a.copyWith(color: const Color(0xFF00FF00))]);
    expect(atlases.engineDrawn.value, isEmpty);
    expect(atlases.payload.where((e) => e.path == oldPath), isEmpty);

    await settle(tester);
    expect(raster.calls, hasLength(2));
    atlases.dispose();
  });

  testWidgets('moving a text needs no new atlas', (tester) async {
    final atlases = make();
    final a = text('a', 0, 3);
    push(atlases, [a]);
    await settle(tester);
    final before = atlases.payload.single.centerX.baseValue;

    push(atlases, [a.copyWith(position: const Offset(40, 0), rotation: 0.5, opacity: 0.4)]);
    await settle(tester);
    expect(raster.calls, hasLength(1));
    expect(atlases.payload.single.centerX.baseValue, isNot(before));
    atlases.dispose();
  });

  testWidgets('a canvas resize keeps every atlas', (tester) async {
    final atlases = make();
    final texts = [text('a', 0, 3)];
    push(atlases, texts);
    await settle(tester);
    await engineTakes(tester, atlases, 'a');

    push(atlases, texts, canvasSize: const Size(225, 400));
    expect(atlases.engineDrawn.value, {'a'});
    await settle(tester);
    expect(raster.calls, hasLength(1));
    expect(atlases.engineDrawn.value, {'a'});
    atlases.dispose();
  });

  testWidgets('a jump into new texts draws them with Flutter until the engine has them',
      (tester) async {
    final atlases = make();
    final texts = [text('a', 0, 3), text('j', 40, 42)];
    push(atlases, texts, playhead: 1);
    await settle(tester);
    await engineTakes(tester, atlases, 'a');

    push(atlases, texts, playhead: 41);
    await settle(tester);
    expect(atlases.payload.map((e) => e.id), ['text_j']);
    expect(atlases.engineDrawn.value, isEmpty, reason: 'j is not the engine\'s yet');

    await engineTakes(tester, atlases, 'j');
    expect(atlases.engineDrawn.value, {'j'});
    atlases.dispose();
  });

  testWidgets('the engine losing an atlas gives the text back to Flutter', (tester) async {
    final atlases = make();
    push(atlases, [text('a', 0, 3)]);
    await settle(tester);
    await engineTakes(tester, atlases, 'a');

    atlases.engineGone('text_a', '/an/older/atlas.png');
    expect(atlases.engineDrawn.value, {'a'});
    atlases.engineGone('text_a', atlases.payload.single.path);
    expect(atlases.engineDrawn.value, isEmpty);
    atlases.dispose();
  });

  testWidgets('a failed atlas stays with Flutter until the text changes', (tester) async {
    raster.answer = (_) => null;
    final atlases = make();
    final a = text('a', 0, 3);
    push(atlases, [a]);
    await settle(tester);
    expect(raster.calls, hasLength(1));

    final texts = [a];
    for (var i = 0; i < 10; i++) {
      push(atlases, texts, playhead: 1 + i * 0.1);
      await frame(tester);
    }
    await settle(tester);
    expect(raster.calls, hasLength(1));
    expect(atlases.payload, isEmpty);

    raster.answer = null;
    push(atlases, [a.copyWith(text: 'changed')]);
    await settle(tester);
    expect(raster.calls, hasLength(2));
    expect(atlases.payload, hasLength(1));
    atlases.dispose();
  });

  testWidgets('a font arriving prepares the text again', (tester) async {
    fontReady = false;
    final atlases = make();
    final texts = [text('a', 0, 3)];
    push(atlases, texts);
    await settle(tester);
    expect(raster.calls, hasLength(1));

    fontReady = true;
    push(atlases, texts);
    await settle(tester);
    expect(raster.calls, hasLength(2));
    atlases.dispose();
  });

  testWidgets('a stale result is thrown away', (tester) async {
    raster.instant = false;
    final atlases = make();
    final a = text('a', 0, 3);
    push(atlases, [a]);
    await tester.pump(const Duration(milliseconds: 260));
    expect(raster.calls, hasLength(1));

    push(atlases, [a.copyWith(text: 'newer')]);
    final stalePath = raster.completeNext();
    await tester.pump();
    expect(deleted, [stalePath]);
    expect(atlases.payload, isEmpty);
    atlases.dispose();
  });

  testWidgets('files go when nothing uses them', (tester) async {
    final atlases = make(cacheSize: 1);
    final a = text('a', 0, 3);
    push(atlases, [a]);
    await settle(tester);
    final first = atlases.payload.single.path;

    push(atlases, [a.copyWith(text: 'again')]);
    await settle(tester);
    final second = atlases.payload.single.path;
    expect(second, isNot(first));
    expect(deleted, isEmpty, reason: 'evicted, but within the grace');

    await tester.pump(const Duration(seconds: 2));
    expect(deleted, [first]);

    atlases.dispose();
    expect(deleted, [first, second]);
  });

  testWidgets('a call landing after dispose deletes its own file', (tester) async {
    raster.instant = false;
    final atlases = make();
    push(atlases, [text('a', 0, 3)]);
    await tester.pump(const Duration(milliseconds: 260));
    atlases.dispose();
    final path = raster.completeNext();
    await tester.pump();
    expect(deleted, [path]);
  });

  testWidgets('while the timeline is dragged Flutter draws every text and the engine none',
      (tester) async {
    // Device-reported: captions stacked on each other while scrubbing. Flutter
    // follows the finger in the frame it moves; the engine hears of the drag
    // as seeks and draws a frame or more later — so a caption Flutter held
    // and one the engine held showed together. One drawer while dragging.
    final atlases = make();
    final texts = [text('a', 0, 3)];
    push(atlases, texts);
    await settle(tester);
    await engineTakes(tester, atlases, 'a');
    expect(atlases.engineDrawn.value, {'a'});

    push(atlases, texts, scrubbing: true);
    expect(atlases.engineDrawn.value, isEmpty, reason: 'Flutter draws it at once');
    expect(atlases.payload.single.opacity.baseValue, 0,
        reason: 'still sent, so the engine keeps it loaded, but drawn there by nobody');

    // Let go: the engine still holds the atlas, so it takes the text back
    // without loading anything — two frames, as any hand-over.
    push(atlases, texts);
    expect(atlases.payload.single.opacity.baseValue, 1);
    expect(atlases.engineDrawn.value, isEmpty);
    await frame(tester);
    await frame(tester);
    expect(atlases.engineDrawn.value, {'a'});
    atlases.dispose();
  });

  testWidgets('no engine, nothing sent and Flutter draws everything', (tester) async {
    final atlases = make();
    final texts = [text('a', 0, 3)];
    push(atlases, texts);
    await settle(tester);
    await engineTakes(tester, atlases, 'a');

    push(atlases, texts, engine: false);
    expect(atlases.payload, isEmpty);
    expect(atlases.engineDrawn.value, isEmpty);
    atlases.dispose();
  });
}

/// Answers with a one-glyph atlas at a fresh path, at once or when told.
class _FakeRasterizer {
  final calls = <TextOverlayModel>[];
  final _pending = <(Completer<RasterizedTextAtlas?>, TextOverlayModel)>[];
  bool instant = true;
  RasterizedTextAtlas? Function(TextOverlayModel text)? answer;
  var _n = 0;

  Future<RasterizedTextAtlas?> call(TextOverlayModel text, Size canvas, double scale) {
    calls.add(text);
    if (!instant) {
      final c = Completer<RasterizedTextAtlas?>();
      _pending.add((c, text));
      return c.future;
    }
    return Future.value(_answerFor(text));
  }

  /// Completes the oldest pending call with an atlas; returns its path.
  String completeNext() {
    final (completer, text) = _pending.removeAt(0);
    final atlas = _atlas(text);
    completer.complete(atlas);
    return atlas.pngPath;
  }

  RasterizedTextAtlas? _answerFor(TextOverlayModel text) {
    final custom = answer;
    return custom != null ? custom(text) : _atlas(text);
  }

  RasterizedTextAtlas _atlas(TextOverlayModel text) => RasterizedTextAtlas(
        pngPath: '/tmp/text_overlay_${text.id}_${_n++}.png',
        canvasPxSize: const Size(100, 30),
        atlasPxSize: const Size(200, 60),
        glyphs: const [
          RasterizedGlyph(
            atlasRect: Rect.fromLTWH(0, 0, 20, 30),
            boxRect: Rect.fromLTWH(0, 0, 20, 30),
            srcRect: Rect.fromLTWH(0, 0, 1, 1),
          ),
        ],
        backgroundRect: null,
        borderRadius: 0,
      );
}
