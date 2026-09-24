import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/lane_layout.dart';

/// The lane rules: nothing on the timeline overlaps anything else on its
/// lane, and no lane is left empty between two that are not.
void main() {
  LaneSpan s(String id, int lane, double start, double end) =>
      LaneSpan(id: id, lane: lane, start: start, end: end);

  /// Whether any two spans on one lane overlap — the invariant every rule
  /// here exists to keep.
  bool anyOverlap(List<LaneSpan> spans) {
    for (var i = 0; i < spans.length; i++) {
      for (var j = i + 1; j < spans.length; j++) {
        final a = spans[i], b = spans[j];
        if (a.lane == b.lane && a.start < b.end && b.start < a.end) {
          return true;
        }
      }
    }
    return false;
  }

  List<LaneSpan> apply(
    List<LaneSpan> spans,
    Map<String, int> lanes, {
    String? movedId,
    double? start,
    double? end,
  }) =>
      [
        for (final x in spans)
          LaneSpan(
            id: x.id,
            lane: lanes[x.id] ?? x.lane,
            start: x.id == movedId ? start! : x.start,
            end: x.id == movedId ? end! : x.end,
          ),
      ];

  group('firstFreeLane', () {
    test('touching ends do not collide', () {
      expect(firstFreeLane([s('a', 0, 0, 3)], 3, 5), 0);
    });

    test('an overlap goes to the next lane, and past the last to a new one',
        () {
      final spans = [s('a', 0, 0, 3), s('b', 1, 2, 6)];
      expect(firstFreeLane(spans, 1, 2), 1);
      expect(firstFreeLane(spans, 2, 4), 2);
    });

    test('starts searching from the lane it is given', () {
      expect(firstFreeLane([s('a', 0, 0, 3)], 5, 6, fromLane: 1), 1);
    });
  });

  group('maxMoveLane — one lane below the last, never an empty one', () {
    test('two things on the last lane: either may go one below', () {
      final spans = [s('a', 0, 0, 2), s('b', 1, 0, 2), s('c', 1, 3, 5)];
      expect(maxMoveLane(spans, 'b'), 2);
    });

    test('alone on the last lane: going below would leave it empty', () {
      final spans = [s('a', 0, 0, 2), s('b', 1, 0, 2)];
      expect(maxMoveLane(spans, 'b'), 1);
    });

    test('a lone item has lane 0 and nowhere else', () {
      expect(maxMoveLane([s('a', 0, 0, 2)], 'a'), 0);
    });
  });

  group('resolveMove', () {
    test('into a free lane, it simply goes there', () {
      final spans = [s('a', 0, 0, 3), s('b', 0, 4, 6)];
      expect(resolveMove(spans, 'b', 4, 6, 1), {'b': 1});
    });

    test('onto something it overlaps, the two trade lanes — layer order',
        () {
      // Lane decides which overlay paints on top, so a drag onto an occupied
      // lane is how a user reorders layers.
      final spans = [s('a', 0, 0, 3), s('b', 1, 1, 4)];
      expect(resolveMove(spans, 'b', 1, 4, 0), {'b': 0, 'a': 1});
    });

    test('never swaps an occupant into a lane where it would overlap', () {
      // `a` would land on `c` in lane 1, so no swap: `b` takes the nearest
      // free lane at or below where it was dropped instead.
      final spans = [s('a', 0, 0, 5), s('b', 1, 1, 2), s('c', 1, 4, 6)];
      final lanes = resolveMove(spans, 'b', 1, 2, 0);
      expect(lanes, {'b': 1});
      expect(anyOverlap(apply(spans, lanes)), isFalse);
    });

    test('slid onto a neighbour on its own lane, it steps down a lane', () {
      final spans = [s('a', 0, 0, 3), s('b', 0, 5, 8)];
      final lanes = resolveMove(spans, 'b', 2, 5, 0);
      expect(lanes, {'b': 1});
    });

    test('is clamped to one lane past the last, however far it is dragged',
        () {
      final spans = [s('a', 0, 0, 3), s('b', 0, 4, 6)];
      expect(resolveMove(spans, 'b', 4, 6, 9), {'b': 1});
    });

    test('no move ever leaves an overlap — swept', () {
      final spans = [
        s('a', 0, 0, 4),
        s('b', 0, 5, 9),
        s('c', 1, 2, 6),
        s('d', 2, 0, 3),
        s('e', 2, 7, 10),
      ];
      for (final id in ['a', 'b', 'c', 'd', 'e']) {
        final me = spans.firstWhere((x) => x.id == id);
        final length = me.end - me.start;
        for (var start = 0.0; start <= 10; start += 0.5) {
          for (var lane = 0; lane <= 4; lane++) {
            final lanes = resolveMove(spans, id, start, start + length, lane);
            final after = apply(spans, lanes,
                movedId: id, start: start, end: start + length);
            expect(anyOverlap(after), isFalse,
                reason: '$id to lane $lane at $start');
          }
        }
      }
    });
  });

  group('clampTrim — a trimmed edge stops at its neighbour', () {
    final spans = [s('a', 0, 0, 3), s('b', 0, 5, 8), s('c', 0, 10, 12)];

    test('the start stops at the previous item\'s end', () {
      expect(clampTrim(spans, 'b', 1, 8), (start: 3.0, end: 8.0));
    });

    test('the end stops at the next item\'s start', () {
      expect(clampTrim(spans, 'b', 5, 11), (start: 5.0, end: 10.0));
    });

    test('an item on another lane is no neighbour', () {
      final other = [s('a', 1, 0, 3), s('b', 0, 5, 8)];
      expect(clampTrim(other, 'b', 1, 8), (start: 1.0, end: 8.0));
    });
  });

  group('normalizeLanes — a saved project that broke the rules', () {
    test('separates a stack and closes the gaps', () {
      // What the old duplicate left: a copy exactly on top of its original.
      final spans = [s('a', 0, 2, 5), s('copy', 0, 2, 5), s('b', 3, 0, 1)];
      final lanes = normalizeLanes(spans);
      final after = apply(spans, lanes);

      expect(anyOverlap(after), isFalse);
      // Dense: `b`, alone on lane 3, closes up to lane 2.
      expect({for (final x in after) x.lane}, {0, 1, 2});
    });

    test('keeps paint order: the later of two stacked items stays on top',
        () {
      final spans = [s('a', 0, 2, 5), s('copy', 0, 2, 5)];
      final after = apply(spans, normalizeLanes(spans));
      int lane(String id) => after.firstWhere((x) => x.id == id).lane;
      expect(lane('copy'), greaterThan(lane('a')));
    });

    test('a valid layout is left alone', () {
      final spans = [s('a', 0, 0, 3), s('b', 0, 3, 5), s('c', 1, 1, 4)];
      expect(normalizeLanes(spans), isEmpty);
    });
  });

  group('compactLanes', () {
    test('closes the gap an emptied lane leaves, keeping the order', () {
      final spans = [s('a', 0, 0, 2), s('b', 2, 0, 2), s('c', 3, 0, 2)];
      expect(compactLanes(spans), {'b': 1, 'c': 2});
    });

    test('a dense layout is left alone', () {
      expect(compactLanes([s('a', 0, 0, 2), s('b', 1, 0, 2)]), isEmpty);
    });
  });
}
