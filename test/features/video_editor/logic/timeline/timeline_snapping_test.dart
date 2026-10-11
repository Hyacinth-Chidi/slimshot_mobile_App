import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/lane_layout.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/timeline_snapping.dart';

/// One snapping rule for everything on the timeline: the playhead, the cuts,
/// the other items' edges and 0:00 pull a move or a trim within a few pixels.
void main() {
  const items = [
    LaneSpan(id: 'music', lane: 0, start: 2.0, end: 9.0),
    LaneSpan(id: 'title', lane: 1, start: 4.5, end: 6.0),
  ];

  List<double> targets({String? exclude}) => timelineSnapTargets(
        playheadSeconds: 3.3,
        clipBoundaries: const [0.0, 5.0, 12.0],
        items: items,
        excludeId: exclude,
      );

  group('targets', () {
    test('are the playhead, the cuts, every other item\'s edges and 0:00', () {
      expect(targets(), [0.0, 2.0, 3.3, 4.5, 5.0, 6.0, 9.0, 12.0]);
    });

    test('never include the item being moved', () {
      expect(targets(exclude: 'title'), isNot(contains(4.5)));
      expect(targets(exclude: 'title'), isNot(contains(6.0)));
    });
  });

  group('moving a span', () {
    test('its start lands on a target within reach', () {
      final r = snapMovingSpan(start: 4.95, length: 1.0, targets: targets(), tolerance: 0.1);
      expect(r.value, 5.0);
      expect(r.guide, 5.0);
    });

    test('its end lands on a target within reach', () {
      // End at 8.96 is 0.04 from the music's end at 9.0.
      final r = snapMovingSpan(start: 7.96, length: 1.0, targets: targets(), tolerance: 0.1);
      expect(r.value, closeTo(8.0, 1e-9));
      expect(r.guide, 9.0);
    });

    test('the nearer edge wins when both are in reach', () {
      // Start 4.48 is 0.02 from 4.5; end 5.03 is 0.03 from 5.0.
      final r = snapMovingSpan(start: 4.48, length: 0.55, targets: targets(), tolerance: 0.1);
      expect(r.value, closeTo(4.5, 1e-9));
      expect(r.guide, 4.5);
    });

    test('out of reach, it stays where the finger put it', () {
      final r = snapMovingSpan(start: 7.0, length: 0.5, targets: targets(), tolerance: 0.1);
      expect(r.value, 7.0);
      expect(r.guide, isNull);
    });

    test('never snaps before 0:00', () {
      final r = snapMovingSpan(start: 0.0, length: 1.95, targets: const [2.0], tolerance: 0.1);
      expect(r.value, greaterThanOrEqualTo(0));
    });
  });

  group('one edge', () {
    test('lands on a target within reach and says where', () {
      final r = snapEdge(value: 11.93, targets: targets(), tolerance: 0.1);
      expect(r.value, 12.0);
      expect(r.guide, 12.0);
    });

    test('stays put out of reach', () {
      final r = snapEdge(value: 7.5, targets: targets(), tolerance: 0.1);
      expect(r.value, 7.5);
      expect(r.guide, isNull);
    });
  });

  test('the reach is pixels, so it shrinks in seconds as the timeline zooms in', () {
    expect(snapToleranceSeconds(50), closeTo(8 / 50, 1e-12));
    expect(snapToleranceSeconds(400), closeTo(8 / 400, 1e-12));
  });
}
