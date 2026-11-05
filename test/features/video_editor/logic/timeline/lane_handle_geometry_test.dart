import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/lane_handle_geometry.dart';

/// Where a lane item's trim handle catches a finger. It used to straddle the
/// item's edge, 22 px each side, so on a narrow item the two handles covered
/// most of it and a drag meant to move it trimmed it instead
/// (device-reported, worst at the zoom the timeline opens at).
void main() {
  group('away from 0:00 a handle reaches outward', () {
    test('a start handle lies left of the edge, but for a sliver', () {
      final box = laneHandleBox(edgePx: 300, itemWidthPx: 200, isStart: true);
      expect(box.width, kLaneHandleTouchWidth);
      expect(box.left + box.width - 300, kLaneHandleInwardReach,
          reason: 'only the sliver lies over the item');
      expect(box.left + box.edgeX, 300, reason: 'the bar marks the edge');
    });

    test('an end handle lies right of the edge, but for a sliver', () {
      final box = laneHandleBox(edgePx: 500, itemWidthPx: 200, isStart: false);
      expect(box.width, kLaneHandleTouchWidth);
      expect(500 - box.left, kLaneHandleInwardReach);
      expect(box.left + box.edgeX, 500);
    });
  });

  test('the two handles leave most of any item free to drag', () {
    for (final width in [8.0, 20.0, 50.0, 60.0, 120.0, 400.0]) {
      final start = laneHandleBox(edgePx: 300, itemWidthPx: width, isStart: true);
      final end =
          laneHandleBox(edgePx: 300 + width, itemWidthPx: width, isStart: false);
      final covered = (start.left + start.width - 300) + (300 + width - end.left);
      expect(covered, lessThanOrEqualTo(width * 0.4 + 1e-9),
          reason: '$width px wide: $covered px is handle');
    }
  });

  test('at 0:00, where nothing left of the edge can be touched, the start '
      'handle reaches further in, still leaving the item draggable', () {
    final box = laneHandleBox(edgePx: 0, itemWidthPx: 50, isStart: true);
    final inward = box.left + box.width;
    expect(inward, greaterThan(kLaneHandleInwardReach));
    expect(inward, lessThanOrEqualTo(50 * 0.3));
    expect(box.left + box.edgeX, 0);
  });
}
