import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/timeline_geometry.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/video_editor_timeline_composer.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';

void main() {
  group('videoTimelineDuration', () {
    test('sums plain cuts', () {
      final segments = [
        VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 3),
        VideoSegment(id: 'b', sourceStart: 3, sourceEnd: 8),
      ];

      expect(videoTimelineDuration(segments), 8);
    });

    test('shortens by each transition overlap', () {
      final segments = [
        VideoSegment(
          id: 'a',
          sourceStart: 0,
          sourceEnd: 5,
          transitionType: 'dissolve',
          transitionDuration: 1.0,
        ),
        VideoSegment(id: 'b', sourceStart: 5, sourceEnd: 10),
      ];

      expect(videoTimelineDuration(segments), closeTo(9.0, 1e-9));
    });

    test('accounts for clip speed', () {
      final segments = [
        VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 8, speed: 2),
      ];

      expect(videoTimelineDuration(segments), closeTo(4.0, 1e-9));
    });

    test('is empty for no segments', () {
      expect(videoTimelineDuration(const []), 0.0);
    });
  });

  group('segmentTimelineStarts', () {
    test('pulls each clip after a transition earlier', () {
      final segments = [
        VideoSegment(
          id: 'a',
          sourceStart: 0,
          sourceEnd: 3,
          transitionType: 'dissolve',
          transitionDuration: 0.8,
        ),
        VideoSegment(
          id: 'b',
          sourceStart: 3,
          sourceEnd: 6,
          transitionType: 'wipe',
          transitionDuration: 0.8,
        ),
        VideoSegment(id: 'c', sourceStart: 6, sourceEnd: 9),
      ];

      final starts = segmentTimelineStarts(segments);
      expect(starts[0], 0);
      expect(starts[1], closeTo(2.2, 1e-9));
      expect(starts[2], closeTo(4.4, 1e-9));
    });

    test('agrees with the timeline the native engine is handed', () {
      // The UI lays out from segmentTimelineStarts while the engine plays from
      // the composer. If these two ever disagree the playhead drifts against
      // the clips, so they are pinned together here.
      final segments = [
        VideoSegment(
          id: 'a',
          sourceStart: 0,
          sourceEnd: 4,
          transitionType: 'smoothLeft',
          transitionDuration: 0.6,
        ),
        VideoSegment(
          id: 'b',
          sourceStart: 4,
          sourceEnd: 9,
          transitionType: 'zoomIn',
          transitionDuration: 1.2,
        ),
        VideoSegment(id: 'c', sourceStart: 9, sourceEnd: 12, speed: 1.5),
      ];

      final starts = segmentTimelineStarts(segments);
      final timeline = const VideoEditorTimelineComposer().compose(
        VideoEditorState(
          assets: const [
            MediaAsset(
              id: 'asset_main',
              path: '/source/video.mp4',
              type: MediaAssetType.video,
              durationSeconds: 60,
              width: 1920,
              height: 1080,
              hasAudio: true,
            ),
          ],
          segments: segments,
        ),
      );

      for (var i = 0; i < segments.length; i++) {
        expect(
          timeline.videoClips[i].timelineStart,
          closeTo(starts[i], 1e-9),
          reason: 'clip $i start must match the composer',
        );
      }
      expect(
        timeline.durationSeconds,
        closeTo(videoTimelineDuration(segments), 1e-9),
      );
    });
  });

  group('VideoSegment.sourceAtOffset', () {
    // The filmstrip indexes tiles through this, so it has to agree with what
    // playback shows or thumbnails drift away from the playhead.
    test('walks forward from sourceStart', () {
      final segment = VideoSegment(id: 'a', sourceStart: 4, sourceEnd: 9);

      expect(segment.sourceAtOffset(0), 4);
      expect(segment.sourceAtOffset(2.5), closeTo(6.5, 1e-9));
      expect(segment.sourceAtOffset(5), 9);
    });

    test('consumes source faster when sped up', () {
      final segment = VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 8, speed: 2);

      expect(segment.sourceAtOffset(1), closeTo(2.0, 1e-9));
      expect(segment.sourceAtOffset(4), closeTo(8.0, 1e-9));
    });

    test('walks backward through a reversed clip', () {
      final segment = VideoSegment(
        id: 'r',
        sourceStart: 2,
        sourceEnd: 6,
        isReversed: true,
      );

      expect(segment.sourceAtOffset(0), 6);
      expect(segment.sourceAtOffset(1), closeTo(5.0, 1e-9));
      expect(segment.sourceAtOffset(4), 2);
    });

    test('clamps outside the clip', () {
      final segment = VideoSegment(id: 'a', sourceStart: 3, sourceEnd: 5);

      expect(segment.sourceAtOffset(-10), 3);
      expect(segment.sourceAtOffset(99), 5);
    });

    test('agrees with the whole-timeline mapping inside a clip', () {
      final segments = [
        VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 3),
        VideoSegment(id: 'b', sourceStart: 10, sourceEnd: 14),
      ];
      final starts = segmentTimelineStarts(segments);

      // 1.5s into clip b, reached two ways.
      final viaSegment = segments[1].sourceAtOffset(1.5);
      final viaTimeline = timelineTimeToSourceTime(starts[1] + 1.5, segments);
      expect(viaSegment, closeTo(viaTimeline, 1e-9));
    });
  });

  group('segmentDisplayDurations', () {
    // The timeline draws clips abutting, with the transition at the seam. If a
    // clip were drawn at its full duration it would overlap the next one and
    // the two filmstrips would stack â€” which is exactly what happened before.
    test('a clip is drawn up to where the next one starts', () {
      final segments = [
        VideoSegment(
          id: 'a',
          sourceStart: 0,
          sourceEnd: 5,
          transitionType: 'dissolve',
          transitionDuration: 1.0,
        ),
        VideoSegment(id: 'b', sourceStart: 5, sourceEnd: 10),
      ];

      final displays = segmentDisplayDurations(segments);
      // 'a' runs 5s but hands over at 4s, so only 4s is drawn.
      expect(displays[0], closeTo(4.0, 1e-9));
      // The last clip has no seam after it, so it is drawn whole.
      expect(displays[1], closeTo(5.0, 1e-9));
    });

    test('drawn boxes tile the timeline exactly, with no overlap or gap', () {
      final segments = [
        VideoSegment(
          id: 'a',
          sourceStart: 0,
          sourceEnd: 3,
          transitionType: 'dissolve',
          transitionDuration: 0.8,
        ),
        VideoSegment(
          id: 'b',
          sourceStart: 3,
          sourceEnd: 6,
          transitionType: 'wipe',
          transitionDuration: 0.5,
        ),
        VideoSegment(id: 'c', sourceStart: 6, sourceEnd: 9),
      ];

      final starts = segmentTimelineStarts(segments);
      final displays = segmentDisplayDurations(segments);

      for (var i = 0; i < segments.length - 1; i++) {
        expect(
          starts[i] + displays[i],
          closeTo(starts[i + 1], 1e-9),
          reason: 'clip $i must end exactly where clip ${i + 1} starts',
        );
      }
      expect(
        starts.last + displays.last,
        closeTo(videoTimelineDuration(segments), 1e-9),
      );
    });

    test('plain cuts are drawn at their full duration', () {
      final segments = [
        VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 3),
        VideoSegment(id: 'b', sourceStart: 3, sourceEnd: 7),
      ];

      expect(segmentDisplayDurations(segments), [3.0, 4.0]);
    });

    test('is empty for no segments', () {
      expect(segmentDisplayDurations(const []), isEmpty);
    });
  });

  group('timelineTimeToSourceTime', () {
    test('maps through a plain cut', () {
      final segments = [
        VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 3),
        VideoSegment(id: 'b', sourceStart: 10, sourceEnd: 13),
      ];

      expect(timelineTimeToSourceTime(1.0, segments), closeTo(1.0, 1e-9));
      // Second clip starts at timeline 3 but source 10.
      expect(timelineTimeToSourceTime(4.0, segments), closeTo(11.0, 1e-9));
    });

    test('resolves an overlap to the incoming clip', () {
      final segments = [
        VideoSegment(
          id: 'a',
          sourceStart: 0,
          sourceEnd: 5,
          transitionType: 'dissolve',
          transitionDuration: 1.0,
        ),
        VideoSegment(id: 'b', sourceStart: 20, sourceEnd: 25),
      ];

      // The window runs 4.0 -> 5.0; inside it the incoming clip owns the
      // instant, matching how the native engine picks the current clip.
      expect(timelineTimeToSourceTime(4.5, segments), closeTo(20.5, 1e-9));
    });

    test('reads backwards through a reversed clip', () {
      final segments = [
        VideoSegment(
          id: 'r',
          sourceStart: 2,
          sourceEnd: 6,
          isReversed: true,
        ),
      ];

      expect(timelineTimeToSourceTime(0.0, segments), closeTo(6.0, 1e-9));
      expect(timelineTimeToSourceTime(1.0, segments), closeTo(5.0, 1e-9));
      expect(timelineTimeToSourceTime(4.0, segments), closeTo(2.0, 1e-9));
    });

    test('clamps past the end', () {
      final segments = [
        VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 3),
      ];

      expect(timelineTimeToSourceTime(99.0, segments), closeTo(3.0, 1e-9));
    });
  });

  group('segmentIndexAt', () {
    // The bug this pins: a timeline instant is not a source instant. Split used
    // to treat the playhead's timeline seconds as source seconds, so it cut in
    // the wrong place the moment a project had more than one clip.
    test('finds the clip that owns a timeline instant', () {
      final segments = [
        VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 3),
        VideoSegment(id: 'b', sourceStart: 0, sourceEnd: 5),
        VideoSegment(id: 'c', sourceStart: 0, sourceEnd: 4),
      ];

      expect(segmentIndexAt(0.0, segments), 0);
      expect(segmentIndexAt(2.9, segments), 0);
      expect(segmentIndexAt(3.0, segments), 1);
      expect(segmentIndexAt(7.9, segments), 1);
      expect(segmentIndexAt(8.0, segments), 2);
      expect(segmentIndexAt(11.5, segments), 2);
    });

    test('a trimmed clip is found by where it sits, not by its source range', () {
      // Clip b reads source 40..45 but occupies timeline 3..8. Asking for
      // timeline 5 must give b, and never fall outside the clip because 5 is
      // nowhere near its source range.
      final segments = [
        VideoSegment(id: 'a', sourceStart: 10, sourceEnd: 13),
        VideoSegment(id: 'b', sourceStart: 40, sourceEnd: 45),
      ];

      expect(segmentIndexAt(5.0, segments), 1);
      expect(
        timelineTimeToSourceTime(5.0, segments),
        closeTo(42.0, 1e-9),
      );
    });

    test('resolves an overlap to the incoming clip, like the engine', () {
      final segments = [
        VideoSegment(
          id: 'a',
          sourceStart: 0,
          sourceEnd: 5,
          transitionType: 'dissolve',
          transitionDuration: 1.0,
        ),
        VideoSegment(id: 'b', sourceStart: 0, sourceEnd: 5),
      ];

      // b starts at 4.0 because the transition overlaps them by a second.
      expect(segmentIndexAt(3.9, segments), 0);
      expect(segmentIndexAt(4.1, segments), 1);
    });

    test('clamps below the start and past the end', () {
      final segments = [
        VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 3),
        VideoSegment(id: 'b', sourceStart: 0, sourceEnd: 3),
      ];

      expect(segmentIndexAt(-1.0, segments), 0);
      expect(segmentIndexAt(99.0, segments), 1);
    });

    test('reports nothing for an empty timeline', () {
      expect(segmentIndexAt(0.0, const []), -1);
    });
  });

  group('split geometry', () {
    // What the notifier does when the blade lands: find the clip, convert the
    // timeline instant to a source instant *within that clip*.
    test('a speed-changed clip converts the playhead correctly', () {
      // 8s of source at 2x occupies 4s of timeline. Halfway along the box
      // (timeline 2.0) is source 4.0, not 2.0.
      final segments = [
        VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 8, speed: 2),
      ];

      final index = segmentIndexAt(2.0, segments);
      final starts = segmentTimelineStarts(segments);
      expect(index, 0);
      expect(
        segments[index].sourceAtOffset(2.0 - starts[index]),
        closeTo(4.0, 1e-9),
      );
    });

    test('a reversed clip converts from the source end', () {
      final segments = [
        VideoSegment(id: 'a', sourceStart: 10, sourceEnd: 20, isReversed: true),
      ];

      final starts = segmentTimelineStarts(segments);
      // 3s into a reversed clip is 3s back from its source end.
      expect(
        segments[0].sourceAtOffset(3.0 - starts[0]),
        closeTo(17.0, 1e-9),
      );
    });

    test('the two halves of a split tile the original exactly', () {
      final segment = VideoSegment(id: 'a', sourceStart: 4, sourceEnd: 10);
      final split = segment.sourceAtOffset(2.5);

      final left = segment.copyWith(sourceEnd: split);
      final right = segment.copyWith(sourceStart: split);

      expect(split, closeTo(6.5, 1e-9));
      expect(left.duration + right.duration, closeTo(segment.duration, 1e-9));
      expect(left.sourceEnd, right.sourceStart);
    });
  });


  group('snapping', () {
    // Snapping is a pull within a *pixel* tolerance, expressed in whatever
    // unit the caller measures in — timeline seconds for a scrub release,
    // source seconds for a trim — so one helper serves both.
    test('pulls onto the nearest candidate within tolerance', () {
      expect(snapToNearest(4.9, [2.0, 5.0, 9.0], 0.2), 5.0);
      expect(snapToNearest(5.1, [2.0, 5.0, 9.0], 0.2), 5.0);
    });

    test('leaves a value alone outside tolerance', () {
      expect(snapToNearest(4.5, [2.0, 5.0, 9.0], 0.2), 4.5);
      expect(snapToNearest(4.5, const <double>[], 0.2), 4.5);
    });

    test('a tie goes to the earlier candidate', () {
      expect(snapToNearest(3.5, [3.0, 4.0], 0.6), 3.0);
    });

    test('clip boundaries are every seam plus the two ends', () {
      // 3s, then 4s dissolving for 1s into 4s: the third clip starts 1s
      // early, so the seams are 3 and 6 and the end is 10 — the overlap has
      // already been applied, which is where the cut is drawn.
      final segments = [
        VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 3),
        VideoSegment(
          id: 'b',
          sourceStart: 0,
          sourceEnd: 4,
          transitionType: 'dissolve',
          transitionDuration: 1.0,
        ),
        VideoSegment(id: 'c', sourceStart: 0, sourceEnd: 4),
      ];
      expect(clipBoundaryTimes(segments), [0.0, 3.0, 6.0, 10.0]);
    });

    test('the tolerance is a fixed number of pixels', () {
      // 8px at the timeline's 50px/s is 0.16s: close enough to feel magnetic,
      // far enough not to steal an intended near miss.
      expect(kSnapTolerancePx, 8.0);
    });
  });
}
