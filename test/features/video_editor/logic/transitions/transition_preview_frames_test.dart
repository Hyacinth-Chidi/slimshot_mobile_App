import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/tile_preview_store.dart';
import 'package:slimshotai/features/video_editor/logic/transitions/transition_preview_frames.dart';

void main() {
  List<Uint8List> framesFor(String type) =>
      [Uint8List.fromList(type.codeUnits)];

  test('a transition is rendered once and then served from the cache', () async {
    final asked = <String>[];
    final cache = TransitionPreviewFrames((type) async {
      asked.add(type);
      return framesFor(type);
    });

    expect(cache.peek('swirl'), isNull);
    final first = await cache.request('swirl');
    final second = await cache.request('swirl');

    expect(first, framesFor('swirl'));
    expect(identical(first, second), isTrue);
    expect(cache.peek('swirl'), same(first));
    expect(asked, ['swirl']);
  });

  test('requests are drawn one at a time, in the order asked', () async {
    final pending = <String, Completer<List<Uint8List>?>>{};
    final started = <String>[];
    final cache = TransitionPreviewFrames((type) {
      started.add(type);
      return (pending[type] = Completer<List<Uint8List>?>()).future;
    });

    final a = cache.request('swirl');
    final b = cache.request('bounce');
    await Future<void>.delayed(Duration.zero);
    // The renderer shares its thread with the live preview: one tile at a time.
    expect(started, ['swirl']);

    pending['swirl']!.complete(framesFor('swirl'));
    await a;
    await Future<void>.delayed(Duration.zero);
    expect(started, ['swirl', 'bounce']);
    pending['bounce']!.complete(framesFor('bounce'));
    expect(await b, framesFor('bounce'));
  });

  test('asking twice while drawing draws once', () async {
    var calls = 0;
    final gate = Completer<List<Uint8List>?>();
    final cache = TransitionPreviewFrames((type) {
      calls++;
      return gate.future;
    });
    final a = cache.request('swirl');
    final b = cache.request('swirl');
    gate.complete(framesFor('swirl'));
    expect(await a, await b);
    expect(calls, 1);
  });

  test('a transition that could not be drawn answers null and is not retried', () async {
    var calls = 0;
    final cache = TransitionPreviewFrames((type) async {
      calls++;
      return null;
    });
    expect(await cache.request('swirl'), isNull);
    expect(await cache.request('swirl'), isNull);
    expect(cache.hasFailed('swirl'), isTrue);
    expect(calls, 1);
  });

  test('a renderer that throws is a transition that could not be drawn', () async {
    final cache = TransitionPreviewFrames((type) async => throw StateError('gone'));
    expect(await cache.request('swirl'), isNull);
    expect(cache.hasFailed('swirl'), isTrue);
  });

  test('an empty answer is a failure, never a tile with no frames', () async {
    final cache = TransitionPreviewFrames((type) async => const []);
    expect(await cache.request('swirl'), isNull);
    expect(cache.hasFailed('swirl'), isTrue);
  });

  // Drawn once per build of the app, not once per launch: the icon a tile
  // shows while the engine draws it is then seen the first time only.
  group('kept on the phone', () {
    late Directory support;

    setUp(() async {
      support = await Directory.systemTemp.createTemp('transition_frames_test');
    });

    tearDown(() async {
      if (await support.exists()) await support.delete(recursive: true);
    });

    TilePreviewStore store() => TilePreviewStore(
          version: () async => '7-100',
          supportDirectory: () async => support,
        );

    List<Uint8List> drawn(String name) => [
          Uint8List.fromList([1, ...name.codeUnits]),
          Uint8List.fromList([2, ...name.codeUnits]),
        ];

    test('frames drawn once are kept, and the next launch shows them '
        'without drawing', () async {
      final firstStore = store();
      final first = TransitionPreviewFrames(
        (name) async => drawn(name),
        store: firstStore,
      );
      await first.request('swirl');
      await firstStore.flush();

      final nextStore = store();
      await nextStore.prepare();
      var draws = 0;
      final next = TransitionPreviewFrames((name) async {
        draws++;
        return null;
      }, store: nextStore);
      expect(next.isSaved('swirl'), isTrue);
      expect(next.isSaved('bounce'), isFalse);
      expect(await next.request('swirl'), drawn('swirl'));
      expect(next.peek('swirl'), drawn('swirl'));
      expect(draws, 0);
    });

    test('a transition that could not be drawn is not kept', () async {
      final firstStore = store();
      final first =
          TransitionPreviewFrames((name) async => null, store: firstStore);
      expect(await first.request('swirl'), isNull);
      await firstStore.flush();

      final nextStore = store();
      await nextStore.prepare();
      expect(
        TransitionPreviewFrames((_) async => null, store: nextStore)
            .isSaved('swirl'),
        isFalse,
        reason: 'the next launch tries again',
      );
    });

    test('frames kept but unreadable are drawn again, and kept anew',
        () async {
      final kept = store();
      // A file that says nine bytes follow and holds one.
      await kept.write(TilePreviewKind.transitions, 'swirl',
          Uint8List.fromList([0, 0, 0, 9, 1]));
      await kept.flush();
      var draws = 0;
      final frames = TransitionPreviewFrames((name) async {
        draws++;
        return drawn(name);
      }, store: kept);
      expect(await frames.request('swirl'), drawn('swirl'));
      expect(draws, 1);
      await kept.flush();

      final nextStore = store();
      await nextStore.prepare();
      expect(
        await TransitionPreviewFrames((_) async => null, store: nextStore)
            .request('swirl'),
        drawn('swirl'),
      );
    });

    test('frames on the phone are not kept waiting behind a drawing',
        () async {
      final kept = store();
      await kept.write(TilePreviewKind.transitions, 'swirl',
          packTransitionFrames(drawn('swirl')));
      await kept.flush();
      final gate = Completer<List<Uint8List>?>();
      final frames =
          TransitionPreviewFrames((name) => gate.future, store: kept);
      final bounce = frames.request('bounce');
      expect(await frames.request('swirl'), drawn('swirl'));
      gate.complete(drawn('bounce'));
      expect(await bounce, drawn('bounce'));
      // Its frames are being kept; the folder is not removed under them.
      await kept.flush();
    });
  });

  group('a transition kept as one file', () {
    test('packed and unpacked, its frames come back as they were', () {
      final frames = [
        Uint8List.fromList([1, 2, 3]),
        Uint8List.fromList([4]),
        Uint8List.fromList(List.filled(300, 9)),
      ];
      expect(unpackTransitionFrames(packTransitionFrames(frames)), frames);
    });

    test('a file cut short, run long, empty or holding an empty frame is no '
        'frames', () {
      final packed = packTransitionFrames([
        Uint8List.fromList([1, 2, 3]),
        Uint8List.fromList([4, 5]),
      ]);
      expect(
        unpackTransitionFrames(
            Uint8List.sublistView(packed, 0, packed.length - 1)),
        isNull,
      );
      expect(unpackTransitionFrames(Uint8List.fromList([...packed, 0])),
          isNull);
      expect(unpackTransitionFrames(Uint8List(0)), isNull);
      expect(unpackTransitionFrames(Uint8List.fromList([0, 0, 0, 0])), isNull);
    });
  });

  group('previewFrameAt', () {
    test('rests on the first frame, plays, then rests on the last', () {
      expect(previewFrameAt(0.0, 16), 0);
      expect(previewFrameAt(kTransitionPreviewLead - 0.01, 16), 0);
      expect(previewFrameAt(kTransitionPreviewLead + kTransitionPreviewPlay, 16), 15);
      expect(previewFrameAt(0.999, 16), 15);
    });

    test('walks forward through every frame', () {
      var last = -1;
      final seen = <int>{};
      for (var i = 0; i <= 1000; i++) {
        final frame = previewFrameAt(i / 1000, 16);
        expect(frame, greaterThanOrEqualTo(last));
        last = frame;
        seen.add(frame);
      }
      expect(seen, {for (var i = 0; i < 16; i++) i});
    });

    test('a single frame is that frame', () {
      expect(previewFrameAt(0.5, 1), 0);
    });
  });
}
