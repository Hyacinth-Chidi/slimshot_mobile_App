import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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
