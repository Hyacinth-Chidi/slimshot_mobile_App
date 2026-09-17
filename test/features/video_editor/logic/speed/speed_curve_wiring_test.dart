import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/speed/speed_curve.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/timeline_geometry.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/video_editor_timeline_composer.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// A speed curve on a clip reaches everything that asks "how long" and "which
/// frame": the segment, the composed timeline, the geometry helper, and the
/// edits that create, replace and cut it.
void main() {
  const asset = MediaAsset(
    id: 'a',
    path: '/v.mp4',
    type: MediaAssetType.video,
    durationSeconds: 30,
    width: 1920,
    height: 1080,
    hasAudio: true,
  );

  final hero = speedCurvePresetById('hero')!.curve;

  VideoSegment clip(String id, {SpeedCurve? curve, double speed = 1.0}) =>
      VideoSegment(
        id: id,
        assetId: 'a',
        sourceStart: 2,
        sourceEnd: 12,
        speed: speed,
        speedCurve: curve,
      );

  VideoEditorNotifier notifierWith(List<VideoSegment> segments, {String? selected}) =>
      VideoEditorNotifier(VideoEditorService())
        ..state = VideoEditorState(
          assets: const [asset],
          segments: segments,
          selectedSegmentId: selected,
          isClipSelected: selected != null,
        );

  group('VideoSegment', () {
    test('duration is the source span times the curve\'s factor', () {
      final s = clip('a', curve: hero);
      expect(s.duration, closeTo(10 * hero.durationFactor, 1e-9));
      // The flat speed is ignored while a curve is set.
      expect(clip('a', curve: hero, speed: 2.0).duration, s.duration);
    });

    test('sourceAtOffset walks the curve\'s inverse, end to end', () {
      final s = clip('a', curve: hero);
      expect(s.sourceAtOffset(0), 2);
      expect(s.sourceAtOffset(s.duration), 12);
      // Hero is symmetric — fast, slow through the middle, fast — so the
      // timeline midpoint lands exactly on the footage's midpoint.
      expect(s.sourceAtOffset(s.duration / 2), closeTo(7, 1e-9));
      // A front-loaded curve does move the midpoint on: flash_in spends its
      // opening at 4x, so half the timeline is well past half the footage.
      final fast = clip('a', curve: speedCurvePresetById('flash_in')!.curve);
      expect(fast.sourceAtOffset(fast.duration / 2), greaterThan(7));
      var last = 2.0;
      for (var i = 1; i <= 50; i++) {
        final v = s.sourceAtOffset(s.duration * i / 50);
        expect(v, greaterThanOrEqualTo(last));
        last = v;
      }
    });

    test('a reversed clip mirrors the same walk', () {
      final s = clip('a', curve: hero).copyWith(isReversed: true);
      expect(s.sourceAtOffset(0), 12);
      expect(s.sourceAtOffset(s.duration), 2);
    });

    test('speedAtOffset reads the curve where the playhead is', () {
      final s = clip('a', curve: hero);
      expect(s.speedAtOffset(0), closeTo(2.0, 1e-9));
      expect(clip('a', speed: 1.5).speedAtOffset(3), 1.5);
    });

    test('JSON carries the curve only when set, and reads it back', () {
      expect(clip('a').toJson().containsKey('speedCurve'), isFalse);
      final back = VideoSegment.fromJson(clip('a', curve: hero).toJson());
      expect(back.speedCurve, hero);
      final junk = VideoSegment.fromJson({...clip('a').toJson(), 'speedCurve': 'x'});
      expect(junk.speedCurve, isNull);
    });
  });

  group('composer', () {
    test('the clip on the wire carries the curve and the curved duration', () {
      final timeline = const VideoEditorTimelineComposer().compose(
        VideoEditorState(assets: const [asset], segments: [clip('a', curve: hero)]),
      );
      final wire = timeline.videoClips.single;
      expect(wire.speedCurve, hero);
      expect(wire.timelineEnd - wire.timelineStart,
          closeTo(10 * hero.durationFactor, 1e-6));
      expect(wire.toJson()['speedCurve'], hero.toJson());
      // And resolves source through it, like the segment.
      expect(wire.sourceAt(wire.timelineEnd), closeTo(12, 1e-9));
    });

    test('adjacent cuts are not merged across a curve', () {
      final timeline = const VideoEditorTimelineComposer().compose(
        VideoEditorState(
          assets: const [asset],
          segments: [
            clip('a', curve: hero),
            VideoSegment(id: 'b', assetId: 'a', sourceStart: 12, sourceEnd: 20),
          ],
        ),
      );
      expect(timeline.playbackClips.length, 2);
    });
  });

  test('timelineTimeToSourceTime agrees with the segment', () {
    final segments = [
      VideoSegment(id: 'x', assetId: 'a', sourceStart: 0, sourceEnd: 4),
      clip('a', curve: hero),
    ];
    for (final t in [4.0, 5.0, 6.5, 8.0]) {
      expect(
        timelineTimeToSourceTime(t, segments),
        closeTo(segments[1].sourceAtOffset(t - 4), 1e-9),
        reason: '@ $t',
      );
    }
  });

  group('notifier', () {
    test('setClipSpeedCurve writes the curve and resets the flat speed', () {
      final n = notifierWith([clip('a', speed: 2.0), clip('b')], selected: 'a');
      n.setClipSpeedCurve(hero);
      expect(n.state.segments[0].speedCurve, hero);
      expect(n.state.segments[0].speed, 1.0);
      expect(n.state.segments[1].speedCurve, isNull);
      n.undo();
      expect(n.state.segments[0].speedCurve, isNull);
      expect(n.state.segments[0].speed, 2.0);
    });

    test('null removes the curve; the same curve is not an undo step', () {
      final n = notifierWith([clip('a', curve: hero)], selected: 'a');
      expect(n.state.canUndo, isFalse);
      n.setClipSpeedCurve(hero);
      // The same curve again is not an edit, so it is not an undo step either.
      expect(n.state.canUndo, isFalse);
      n.setClipSpeedCurve(null);
      expect(n.state.segments[0].speedCurve, isNull);
    });

    test('committing a flat speed clears the curve', () {
      final n = notifierWith([clip('a', curve: hero)], selected: 'a');
      n.setPreviewSpeed(1.5);
      n.commitPreviewSpeed();
      expect(n.state.segments[0].speedCurve, isNull);
      expect(n.state.segments[0].speed, 1.5);
    });

    test('a split hands each half its own piece of the curve', () {
      final n = notifierWith([clip('a', curve: hero)], selected: 'a');
      final whole = n.state.segments[0];
      final cutAt = whole.duration * 0.4;
      final seamSource = whole.sourceAtOffset(cutAt);

      n.splitAtPosition(cutAt);

      final left = n.state.segments[0];
      final right = n.state.segments[1];
      expect(left.speedCurve, isNotNull);
      expect(right.speedCurve, isNotNull);
      // The halves add up to the whole and meet at the same rate.
      expect(left.duration + right.duration, closeTo(whole.duration, 1e-6));
      expect(left.speedAtOffset(left.duration),
          closeTo(right.speedAtOffset(0), 1e-6));
      expect(left.sourceAtOffset(left.duration), closeTo(seamSource, 1e-6));
      expect(right.sourceAtOffset(0), closeTo(seamSource, 1e-6));
      // Neither half claims to be a preset any more.
      expect(left.speedCurve!.presetId, isNull);
    });
  });
}
