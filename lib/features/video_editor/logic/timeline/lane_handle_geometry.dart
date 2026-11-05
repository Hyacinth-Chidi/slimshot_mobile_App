import 'dart:math' as math;

/// Where a lane item's trim handle catches a finger.
///
/// A handle claims the pointer the moment it lands (a handle that waited out
/// the scroll's touch slop lost the first third of a second of every trim),
/// so whatever part of an item its touch area covers can only ever be
/// trimmed there, never moved. The area used to straddle the item's edge,
/// half of it — 22 px at each end — over the item: a one-second text at the
/// 50 px a second the timeline opens at was 50 px wide and 44 of them were
/// handle, so a drag meant to move it trimmed it instead (device-reported).
///
/// So the touch area keeps its full width but lies **outside** the item,
/// reaching in only a sliver — [kLaneHandleInwardReach], and never more than
/// [kLaneHandleInwardFraction] of a narrow item. At 0:00 nothing left of the
/// edge can be touched (the lanes begin there), so a start handle there
/// reaches a little further in, [kLaneHandleStartInwardReach].
class LaneHandleBox {
  const LaneHandleBox({
    required this.left,
    required this.width,
    required this.edgeX,
  });

  /// The touch area's left, in the lane's own coordinates.
  final double left;

  /// The touch area's width.
  final double width;

  /// The item's edge, measured from [left]: where the handle's bar is drawn.
  final double edgeX;
}

/// A handle's touch area: large, so the handle is easy to catch.
const double kLaneHandleTouchWidth = 44.0;

/// How far a handle's touch area reaches over its item.
const double kLaneHandleInwardReach = 6.0;

/// The most of a narrow item a handle may cover.
const double kLaneHandleInwardFraction = 0.15;

/// How far a start handle reaches in at 0:00, where it cannot reach out.
const double kLaneHandleStartInwardReach = 14.0;

/// The most of a narrow item a start handle at 0:00 may cover.
const double kLaneHandleStartInwardFraction = 0.25;

LaneHandleBox laneHandleBox({
  required double edgePx,
  required double itemWidthPx,
  required bool isStart,
}) {
  final atTimelineStart = isStart && edgePx < 0.5;
  final width = math.max(0.0, itemWidthPx);
  final inward = atTimelineStart
      ? math.min(kLaneHandleStartInwardReach,
          width * kLaneHandleStartInwardFraction)
      : math.min(kLaneHandleInwardReach, width * kLaneHandleInwardFraction);
  final outward = kLaneHandleTouchWidth - inward;
  return isStart
      ? LaneHandleBox(
          left: edgePx - outward,
          width: kLaneHandleTouchWidth,
          edgeX: outward,
        )
      : LaneHandleBox(
          left: edgePx - inward,
          width: kLaneHandleTouchWidth,
          edgeX: inward,
        );
}
