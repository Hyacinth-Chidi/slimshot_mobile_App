import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/timeline_geometry.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';

/// Where a seam's transition sits on the timeline — what the transitions
/// sheet plays on the canvas when a tile is tapped.
void main() {
  VideoSegment clip(String id, double length, {String? transition}) =>
      VideoSegment(
        id: id,
        sourceStart: 0,
        sourceEnd: length,
        transitionType: transition,
        transitionDuration: transition == null ? null : 1.0,
      );

  test('the window opens where the next clip starts and closes where this one ends', () {
    final segments = [
      clip('a', 4),
      clip('b', 5, transition: 'swirl'),
      clip('c', 6),
    ];
    final window = transitionWindowFor(segments, 'b')!;
    // a: 0..4, b: 4..9 overlapping c by 1s, so c starts at 8.
    expect(window.start, closeTo(8, 1e-9));
    expect(window.end, closeTo(9, 1e-9));
  });

  test('a seam with no transition, the last clip, or an unknown id has none', () {
    final segments = [clip('a', 4), clip('b', 5, transition: 'swirl')];
    expect(transitionWindowFor(segments, 'a'), isNull);
    expect(transitionWindowFor(segments, 'b'), isNull);
    expect(transitionWindowFor(segments, 'zzz'), isNull);
  });
}
