import '../../models/audio_track_model.dart';
import '../../models/image_overlay_model.dart';
import '../../models/text_overlay_model.dart';
import '../../models/video_overlay_model.dart';

/// Where things sit on the timeline's lanes, and the two rules that keep it
/// readable: **nothing overlaps anything else on its lane**, and **no lane is
/// left empty** between two that are not.
///
/// Text, photos, video overlays and audio share one set of lanes (a lane may
/// hold several kinds), so every rule here works on [LaneSpan]s — an id, a
/// lane and a timeline range — and knows nothing about what the item is.
/// Lane also decides paint order for the overlays (lower lanes first), so
/// moving an item onto a lane is how a user reorders layers.
class LaneSpan {
  const LaneSpan({
    required this.id,
    required this.lane,
    required this.start,
    required this.end,
  });

  final String id;
  final int lane;

  /// Timeline seconds.
  final double start;
  final double end;

  @override
  String toString() => 'LaneSpan($id, lane $lane, $start–$end)';
}

/// Below this, two edges count as touching rather than overlapping — times
/// travel through milliseconds and doubles, so exact equality is not a test.
const double _kEpsilon = 1e-6;

bool _overlaps(double aStart, double aEnd, double bStart, double bEnd) =>
    aStart < bEnd - _kEpsilon && bStart < aEnd - _kEpsilon;

/// Every item on every lane, as spans.
List<LaneSpan> laneSpansOf({
  required List<TextOverlayModel> texts,
  required List<ImageOverlayModel> images,
  required List<VideoOverlayModel> videos,
  required List<AudioTrackModel> audios,
}) {
  double s(Duration d) => d.inMicroseconds / 1e6;
  return [
    for (final t in texts)
      LaneSpan(
        id: t.id,
        lane: t.laneIndex,
        start: s(t.startTime),
        end: s(t.endTime),
      ),
    for (final i in images)
      LaneSpan(
        id: i.id,
        lane: i.laneIndex,
        start: s(i.startTime),
        end: s(i.endTime),
      ),
    for (final v in videos)
      LaneSpan(
        id: v.id,
        lane: v.laneIndex,
        start: s(v.timelineStart),
        end: s(v.timelineEnd),
      ),
    for (final a in audios)
      LaneSpan(
        id: a.id,
        lane: a.laneIndex,
        start: a.timelineStart,
        end: a.timelineEnd,
      ),
  ];
}

/// The first lane, from [fromLane] downward, where [start]–[end] overlaps
/// nothing. Always exists: one past the last occupied lane is empty.
int firstFreeLane(
  List<LaneSpan> spans,
  double start,
  double end, {
  String? excludeId,
  int fromLane = 0,
}) {
  var lane = fromLane < 0 ? 0 : fromLane;
  while (spans.any(
    (x) =>
        x.id != excludeId &&
        x.lane == lane &&
        _overlaps(start, end, x.start, x.end),
  )) {
    lane++;
  }
  return lane;
}

/// The deepest lane [id] may be dragged to: one below the last lane anything
/// *else* occupies.
///
/// So with company on the last lane, an item may open a new lane beneath it;
/// alone there, it may not go further, because the lane it left would be
/// empty. A drag can never make more than one new lane.
int maxMoveLane(List<LaneSpan> spans, String id) {
  var deepest = -1;
  for (final x in spans) {
    if (x.id != id && x.lane > deepest) deepest = x.lane;
  }
  return deepest + 1;
}

/// Where everything lands when [id] is dropped at [start]–[end] on
/// [targetLane]: new lanes by id, the dropped item always included.
///
/// - A free spot is taken as is.
/// - Onto an item it overlaps on another lane, the two **trade lanes** — the
///   layer reorder — but only if every occupant it displaces fits where the
///   dropped item came from.
/// - Otherwise the item takes the nearest free lane at or below the target,
///   which is also what happens when it is slid onto a neighbour on its own
///   lane.
///
/// The target is clamped to `0..`[maxMoveLane], and whatever is returned
/// leaves no overlap anywhere.
Map<String, int> resolveMove(
  List<LaneSpan> spans,
  String id,
  double start,
  double end,
  int targetLane,
) {
  final me = spans.where((x) => x.id == id).firstOrNull;
  if (me == null) return const {};
  final maxLane = maxMoveLane(spans, id);
  final target = targetLane < 0
      ? 0
      : (targetLane > maxLane ? maxLane : targetLane);

  final occupants = [
    for (final x in spans)
      if (x.id != id &&
          x.lane == target &&
          _overlaps(start, end, x.start, x.end))
        x,
  ];
  if (occupants.isEmpty) return {id: target};

  if (target != me.lane) {
    final occupantIds = {for (final o in occupants) o.id};
    final fits = occupants.every(
      (o) => !spans.any(
        (x) =>
            x.id != id &&
            !occupantIds.contains(x.id) &&
            x.lane == me.lane &&
            _overlaps(o.start, o.end, x.start, x.end),
      ),
    );
    if (fits) {
      return {id: target, for (final o in occupants) o.id: me.lane};
    }
  }
  return {
    id: firstFreeLane(spans, start, end, excludeId: id, fromLane: target),
  };
}

/// [start]–[end] for [id] with each edge stopped at its lane neighbour, so a
/// trim can never grow an item into the one beside it.
///
/// Neighbours are judged from where [id] sits now: whatever ends at or
/// before its start bounds the start, whatever begins at or after its end
/// bounds the end.
({double start, double end}) clampTrim(
  List<LaneSpan> spans,
  String id,
  double start,
  double end,
) {
  final me = spans.where((x) => x.id == id).firstOrNull;
  if (me == null) return (start: start, end: end);
  var floor = double.negativeInfinity;
  var ceiling = double.infinity;
  for (final x in spans) {
    if (x.id == id || x.lane != me.lane) continue;
    if (x.end <= me.start + _kEpsilon && x.end > floor) floor = x.end;
    if (x.start >= me.end - _kEpsilon && x.start < ceiling) ceiling = x.start;
  }
  return (
    start: start < floor ? floor : start,
    end: end > ceiling ? ceiling : end,
  );
}

/// New lanes for whatever must move up to close empty lanes, keeping every
/// item's order relative to the others. Empty when the layout is dense.
Map<String, int> compactLanes(List<LaneSpan> spans) {
  final used = {for (final x in spans) x.lane}.toList()..sort();
  final rank = {for (var i = 0; i < used.length; i++) used[i]: i};
  return {
    for (final x in spans)
      if (rank[x.lane] != x.lane) x.id: rank[x.lane]!,
  };
}

/// New lanes that bring a layout which breaks the rules back inside them:
/// every overlap separated, every empty lane closed. Empty for a valid one.
///
/// For projects saved before the rules held — a duplicate used to land
/// exactly on top of its original. Items are placed in paint order (lane,
/// then list order), each on its own lane if that is free there and
/// otherwise the nearest free one below, so of two stacked items the later,
/// which painted on top, still does.
Map<String, int> normalizeLanes(List<LaneSpan> spans) {
  final order = [for (var i = 0; i < spans.length; i++) i]
    ..sort((a, b) {
      final byLane = spans[a].lane.compareTo(spans[b].lane);
      return byLane != 0 ? byLane : a.compareTo(b);
    });
  final placed = <LaneSpan>[];
  for (final i in order) {
    final x = spans[i];
    placed.add(LaneSpan(
      id: x.id,
      lane: firstFreeLane(placed, x.start, x.end, fromLane: x.lane),
      start: x.start,
      end: x.end,
    ));
  }
  final compacted = compactLanes(placed);
  final original = {for (final x in spans) x.id: x.lane};
  return {
    for (final x in placed)
      if ((compacted[x.id] ?? x.lane) != original[x.id])
        x.id: compacted[x.id] ?? x.lane,
  };
}
