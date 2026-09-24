import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/lane_layout.dart';
import 'package:slimshotai/features/video_editor/models/audio_track_model.dart';
import 'package:slimshotai/features/video_editor/models/image_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// The timeline's lanes, as the notifier keeps them.
///
/// Device-reported: a duplicate landed exactly on top of its original, and
/// nothing could be dragged onto a new lane below the last. Reading the code
/// turned up more: every frame of a timeline drag or trim pushed an undo
/// entry (Undo walked a move back a frame at a time), a clip trim could not
/// be undone at all (its only snapshot was taken *after* the trim), and
/// nothing stopped a move or a trim from overlapping a neighbour.
void main() {
  Duration sec(num s) => Duration(milliseconds: (s * 1000).round());

  TextOverlayModel text(String id, int lane, num start, num end) =>
      TextOverlayModel(
        id: id,
        text: id,
        startTime: sec(start),
        endTime: sec(end),
        laneIndex: lane,
      );

  VideoEditorNotifier notifier({
    List<TextOverlayModel> texts = const [],
    List<ImageOverlayModel> images = const [],
    List<VideoOverlayModel> videos = const [],
    List<AudioTrackModel> audios = const [],
  }) =>
      VideoEditorNotifier(VideoEditorService())
        ..state = VideoEditorState(
          assets: const [
            MediaAsset(
              id: 'asset',
              path: '/v.mp4',
              type: MediaAssetType.video,
              durationSeconds: 60,
              width: 1920,
              height: 1080,
              hasAudio: true,
            ),
          ],
          segments: [
            VideoSegment(
              id: 'c',
              assetId: 'asset',
              sourceStart: 0,
              sourceEnd: 20,
            ),
          ],
          textOverlays: texts,
          imageOverlays: images,
          videoOverlays: videos,
          audioTracks: audios,
        );

  List<LaneSpan> spans(VideoEditorNotifier n) => laneSpansOf(
        texts: n.state.textOverlays,
        images: n.state.imageOverlays,
        videos: n.state.videoOverlays,
        audios: n.state.audioTracks,
      );

  bool anyOverlap(VideoEditorNotifier n) {
    final all = spans(n);
    for (var i = 0; i < all.length; i++) {
      for (var j = i + 1; j < all.length; j++) {
        final a = all[i], b = all[j];
        if (a.lane == b.lane && a.start < b.end - 1e-6 && b.start < a.end - 1e-6) {
          return true;
        }
      }
    }
    return false;
  }

  int laneOf(VideoEditorNotifier n, String id) =>
      spans(n).firstWhere((s) => s.id == id).lane;

  group('duplicating', () {
    test('a text goes to the next free lane, at the same time', () {
      final n = notifier(texts: [text('a', 0, 2, 5)]);
      n.duplicateTextOverlay('a');

      final copy = n.state.textOverlays.firstWhere((t) => t.id != 'a');
      expect(copy.laneIndex, 1);
      expect(copy.startTime, sec(2));
      expect(anyOverlap(n), isFalse);
    });

    test('past a lane that is busy at that time, never leaving a gap', () {
      final n = notifier(texts: [text('a', 0, 2, 5), text('b', 1, 3, 4)]);
      n.duplicateTextOverlay('a');

      final copy = n.state.textOverlays.firstWhere((t) => t.id.length > 1);
      expect(copy.laneIndex, 2);
      expect(anyOverlap(n), isFalse);
    });

    test('a photo and a video overlay the same way', () {
      final n = notifier(
        images: [
          ImageOverlayModel(
            id: 'i',
            imagePath: '/p.png',
            startTime: sec(0),
            endTime: sec(3),
          ),
        ],
        videos: [
          VideoOverlayModel(
            id: 'v',
            videoPath: '/v.mp4',
            timelineStart: sec(0),
            timelineEnd: sec(3),
            laneIndex: 1,
          ),
        ],
      );
      n.duplicateImageOverlay('i');
      n.duplicateVideoOverlay('v');
      expect(anyOverlap(n), isFalse);
    });

    test('an audio track right after itself, on its own lane when free', () {
      final n = notifier(audios: [
        const AudioTrackModel(
          id: 'm',
          filePath: '/m.mp3',
          sourceDuration: 30,
          sourceStart: 0,
          sourceEnd: 4,
          timelineStart: 1,
          laneIndex: 1,
        ),
        const AudioTrackModel(
          id: 'x',
          filePath: '/x.mp3',
          sourceDuration: 30,
          sourceStart: 0,
          sourceEnd: 4,
          timelineStart: 1,
        ),
      ]);
      n.duplicateAudioTrack('m');

      final copy = n.state.audioTracks.firstWhere((a) => a.id.length > 1);
      expect(copy.timelineStart, 5);
      expect(copy.laneIndex, 1);
      expect(n.state.selectedAudioId, copy.id);
      expect(anyOverlap(n), isFalse);
    });
  });

  group('moving on the timeline', () {
    test('one lane below the last, when the last lane has company', () {
      final n = notifier(texts: [text('a', 0, 0, 3), text('b', 0, 5, 8)]);
      n.beginTimelineGesture();
      n.moveLaneItem('b', start: 5, targetLane: 4);
      n.endTimelineGesture();

      expect(laneOf(n, 'b'), 1);
    });

    test('never below its own lane when it is alone on the last one', () {
      final n = notifier(texts: [text('a', 0, 0, 3), text('b', 1, 5, 8)]);
      n.beginTimelineGesture();
      n.moveLaneItem('b', start: 5, targetLane: 2);
      n.endTimelineGesture();

      expect(laneOf(n, 'b'), 1);
    });

    test('slid onto a neighbour, it steps down rather than overlapping', () {
      final n = notifier(texts: [text('a', 0, 0, 3), text('b', 0, 5, 8)]);
      n.beginTimelineGesture();
      n.moveLaneItem('b', start: 1, targetLane: 0);

      expect(anyOverlap(n), isFalse);
      expect(laneOf(n, 'b'), 1);
    });

    test('a lane emptied by a move closes when the drag ends', () {
      final n = notifier(texts: [
        text('a', 0, 0, 3),
        text('b', 1, 0, 3),
        text('c', 2, 0, 3),
        text('d', 2, 5, 8),
      ]);
      n.beginTimelineGesture();
      n.moveLaneItem('b', start: 10, targetLane: 3);
      n.endTimelineGesture();

      expect({for (final s in spans(n)) s.lane}, {0, 1, 2});
      expect(laneOf(n, 'c'), 1);
    });

    test('a whole drag is one undo step', () {
      final n = notifier(texts: [text('a', 0, 0, 3), text('b', 0, 5, 8)]);
      n.beginTimelineGesture();
      for (final s in [5.5, 6.0, 7.0, 9.0]) {
        n.moveLaneItem('b', start: s, targetLane: 0);
      }
      n.endTimelineGesture();
      expect(n.state.textOverlays[1].startTime, sec(9));

      n.undo();
      expect(n.state.textOverlays[1].startTime, sec(5));
      expect(n.state.canUndo, isFalse);
    });

    test('a gesture that changed nothing leaves no undo entry', () {
      final n = notifier(texts: [text('a', 0, 0, 3)]);
      n.beginTimelineGesture();
      n.endTimelineGesture();
      expect(n.state.canUndo, isFalse);
    });

    test('an audio track moves on the shared lanes too', () {
      final n = notifier(
        texts: [text('a', 0, 0, 3)],
        audios: [
          const AudioTrackModel(
            id: 'm',
            filePath: '/m.mp3',
            sourceDuration: 30,
            sourceStart: 0,
            sourceEnd: 4,
            timelineStart: 10,
          ),
        ],
      );
      n.beginTimelineGesture();
      n.moveLaneItem('m', start: 1, targetLane: 0);

      expect(anyOverlap(n), isFalse);
      expect(n.state.audioTracks.single.timelineStart, 1);
    });
  });

  group('trimming on the timeline', () {
    test('an edge stops at the neighbour on its lane', () {
      final n = notifier(texts: [text('a', 0, 0, 3), text('b', 0, 5, 8)]);
      n.beginTimelineGesture();
      n.trimLaneItem('b', start: 1, end: 8);
      expect(n.state.textOverlays[1].startTime, sec(3));

      n.trimLaneItem('a', start: 0, end: 7);
      expect(n.state.textOverlays[0].endTime, sec(3));
      expect(anyOverlap(n), isFalse);
    });

    test("a video overlay's left edge cuts into its footage", () {
      // It used to move only the timeline start: trimming the head left the
      // footage starting from its first frame, just later.
      final n = notifier(videos: [
        VideoOverlayModel(
          id: 'v',
          videoPath: '/v.mp4',
          timelineStart: sec(2),
          timelineEnd: sec(8),
          sourceStart: 1,
          sourceEnd: 7,
          speed: 2,
        ),
      ]);
      n.beginTimelineGesture();
      n.trimLaneItem('v', start: 3, end: 8);

      final v = n.state.videoOverlays.single;
      expect(v.timelineStart, sec(3));
      // One timeline second at 2× is two seconds of footage.
      expect(v.sourceStart, closeTo(3, 1e-9));
    });

    test('and neither edge runs past the footage it has', () {
      final n = notifier(videos: [
        VideoOverlayModel(
          id: 'v',
          videoPath: '/v.mp4',
          timelineStart: sec(2),
          timelineEnd: sec(4),
          sourceStart: 1,
          sourceEnd: 5,
        ),
      ]);
      n.beginTimelineGesture();
      n.trimLaneItem('v', start: 0, end: 4);
      expect(n.state.videoOverlays.single.timelineStart, sec(1));
      expect(n.state.videoOverlays.single.sourceStart, closeTo(0, 1e-9));

      n.trimLaneItem('v', start: 1, end: 20);
      // Footage 0..5 from timeline 1 ends at timeline 6.
      expect(n.state.videoOverlays.single.timelineEnd, sec(6));
    });

    test("an audio track's trim stops at a neighbour, source following", () {
      final n = notifier(
        texts: [text('a', 0, 0, 3)],
        audios: [
          const AudioTrackModel(
            id: 'm',
            filePath: '/m.mp3',
            sourceDuration: 30,
            sourceStart: 5,
            sourceEnd: 9,
            timelineStart: 4,
          ),
        ],
      );
      n.beginTimelineGesture();
      n.trimAudioTrackLive('m',
          timelineStart: 1, sourceStart: 2, sourceEnd: 9);

      final m = n.state.audioTracks.single;
      expect(m.timelineStart, 3);
      expect(m.sourceStart, closeTo(4, 1e-9));
      expect(m.sourceEnd, 9);
    });

    test("a clip trim can be undone", () {
      // Its only snapshot used to be taken after the trim, so Undo restored
      // the trimmed state and the trim was permanent.
      final n = notifier();
      n.selectSegment('c');
      n.beginTimelineGesture();
      n.setTrimRange(const RangeValues(2, 15));
      n.endTimelineGesture();
      expect(n.state.segments.single.sourceStart, 2);

      n.undo();
      expect(n.state.segments.single.sourceStart, 0);
    });
  });

  test('the timeline brackets every gesture with the one-snapshot pair', () {
    // The screen and the timeline cannot be pumped without a native texture,
    // so the wiring is pinned by reading it. `onDragEnd` used to be
    // `saveStateForUndo` — a snapshot of the *finished* state.
    final screen =
        File('lib/screens/video_editor_screen.dart').readAsStringSync();
    expect(screen, contains('onDragStart: notifier.beginTimelineGesture'));
    expect(screen, contains('onDragEnd: notifier.endTimelineGesture'));
    expect(screen, isNot(contains('onDragEnd: notifier.saveStateForUndo')));

    final timeline = File(
      'lib/features/video_editor/widgets/timeline/scrollable_timeline.dart',
    ).readAsStringSync();
    final starts = 'widget.onDragStart?.call()'.allMatches(timeline).length;
    final ends = 'widget.onDragEnd?.call()'.allMatches(timeline).length;
    // Clip trim, four lane moves, audio trim and six overlay trim handles.
    expect(starts, 12);
    expect(ends, starts, reason: 'every gesture that begins must end');
  });

  test('deleting the last thing on a lane closes the lane', () {
    final n = notifier(texts: [
      text('a', 0, 0, 3),
      text('b', 1, 0, 3),
      text('c', 2, 0, 3),
    ]);
    n.deleteTextOverlay('b');
    expect(laneOf(n, 'c'), 1);
  });
}
