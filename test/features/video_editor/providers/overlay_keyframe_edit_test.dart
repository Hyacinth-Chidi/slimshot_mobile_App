import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/animation/overlay_keyframes.dart';
import 'package:slimshotai/features/video_editor/models/image_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/text_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// Keyframes on overlays, through the notifier: the same plus button, the same
/// edit rule, the same undo, as clips.
///
/// Every overlay here spans 2s–6s of the timeline, so a playhead at 4s is
/// progress 0.5 and the 0.05s hit tolerance is progress 0.0125.
void main() {
  const start = Duration(seconds: 2);
  const end = Duration(seconds: 6);

  VideoEditorNotifier project() => VideoEditorNotifier(VideoEditorService())
    ..state = VideoEditorState(
      segments: [VideoSegment(id: 'c', sourceStart: 0, sourceEnd: 10)],
      textOverlays: [
        TextOverlayModel(id: 't', text: 'Hi', startTime: start, endTime: end),
      ],
      imageOverlays: [
        ImageOverlayModel(
          id: 'i',
          imagePath: '/p.png',
          startTime: start,
          endTime: end,
        ),
      ],
      videoOverlays: [
        VideoOverlayModel(
          id: 'v',
          videoPath: '/v.mp4',
          timelineStart: start,
          timelineEnd: end,
          sourceStart: 0,
          sourceEnd: 20,
        ),
      ],
    );

  /// Each kind: how to select it, how to read it back, and how to copy it.
  /// A duplicate is appended, so the original stays first.
  final kinds = <String, ({
    void Function(VideoEditorNotifier) select,
    OverlayMotion Function(VideoEditorNotifier) motion,
    void Function(VideoEditorNotifier) duplicate,
    OverlayMotion Function(VideoEditorNotifier) copy,
  })>{
    'text': (
      select: (n) => n.selectTextOverlay('t'),
      motion: (n) => n.state.textOverlays.first.motion,
      duplicate: (n) => n.duplicateTextOverlay('t'),
      copy: (n) => n.state.textOverlays.last.motion,
    ),
    'photo': (
      select: (n) => n.selectImageOverlay('i'),
      motion: (n) => n.state.imageOverlays.first.motion,
      duplicate: (n) => n.duplicateImageOverlay('i'),
      copy: (n) => n.state.imageOverlays.last.motion,
    ),
    'video': (
      select: (n) => n.selectVideoOverlay('v'),
      motion: (n) => n.state.videoOverlays.first.motion,
      duplicate: (n) => n.duplicateVideoOverlay('v'),
      copy: (n) => n.state.videoOverlays.last.motion,
    ),
  };

  void seek(VideoEditorNotifier n, double seconds) =>
      n.state = n.state.copyWith(currentPlaybackPosition: seconds);

  List<double> diamondsOf(OverlayMotion m) =>
      keyframeTimesOf(m).map((p) => double.parse(p.toStringAsFixed(4))).toList();

  for (final MapEntry(key: kind, value: k) in kinds.entries) {
    group('$kind overlay', () {
      VideoEditorNotifier selected({double at = 4}) {
        final n = project();
        k.select(n);
        seek(n, at);
        return n;
      }

      test('is the keyframe target, with its own progress', () {
        final n = selected();
        expect(n.state.hasKeyframeTarget, isTrue);
        expect(n.state.keyframeTargetProgress, closeTo(0.5, 1e-9));
        seek(n, 7);
        expect(n.state.keyframeTargetProgress, isNull,
            reason: 'outside its span, never clamped');
      });

      test('with no diamonds, an edit writes the base', () {
        final n = selected();
        n.beginOverlayEdit();
        n.setOverlayMotionLive(position: const Offset(5, 6), scale: 2);
        final m = k.motion(n);
        expect(m.position, const Offset(5, 6));
        expect(m.scale, 2);
        expect(m.hasKeyframes, isFalse);
      });

      test('the plus button places a diamond that changes nothing', () {
        final n = selected();
        final before = k.motion(n);
        n.addKeyframeAtPlayhead();
        final after = k.motion(n);
        expect(diamondsOf(after), [0.5]);
        expect(n.state.keyframeDiamonds.single, closeTo(0.5, 1e-9));
        expect(after.at(0.5).position, before.position);
        expect(after.at(0.5).opacity, before.opacity);
      });

      test('on a diamond, an edit writes that keyframe, not the base', () {
        final n = selected();
        n.addKeyframeAtPlayhead();
        n.beginOverlayEdit();
        n.setOverlayMotionLive(scale: 2);
        final m = k.motion(n);
        expect(m.at(0.5).scale, 2);
        expect(m.scale, 1, reason: 'the base is untouched');
      });

      test('between diamonds, an edit places exactly one more', () {
        final n = selected(at: 2.5);
        n.addKeyframeAtPlayhead();
        seek(n, 5.5);
        n.addKeyframeAtPlayhead();
        seek(n, 4);
        n.beginOverlayEdit();
        n.setOverlayMotionLive(opacity: 0.5);
        final m = k.motion(n);
        expect(diamondsOf(m), [0.125, 0.5, 0.875]);
        expect(m.at(0.5).opacity, 0.5);
      });

      test('the minus button removes it; the last hands its value to the base',
          () {
        final n = selected();
        n.addKeyframeAtPlayhead();
        n.beginOverlayEdit();
        n.setOverlayMotionLive(scale: 3);
        expect(n.state.playheadIsOnKeyframe, isTrue);
        n.removeKeyframeAtPlayhead();
        final m = k.motion(n);
        expect(m.hasKeyframes, isFalse);
        expect(m.scale, 3, reason: 'what the user was looking at stays');
      });

      test('the curve sheet eases the segment, placing nothing', () {
        final n = selected(at: 2.5);
        n.addKeyframeAtPlayhead();
        seek(n, 5.5);
        n.addKeyframeAtPlayhead();
        seek(n, 4);
        expect(n.state.canEditKeyframeCurve, isTrue);
        n.setKeyframeCurve(KeyframeInterpolation.cubicInOut);
        expect(n.state.keyframeCurve, KeyframeInterpolation.cubicInOut);
        expect(diamondsOf(k.motion(n)), [0.125, 0.875]);
      });

      test('a tapped diamond seeks onto it, and a dragged one moves', () {
        final n = selected(at: 3);
        n.addKeyframeAtPlayhead(); // progress 0.25
        seek(n, 5);
        n.seekToKeyframe(0.25);
        expect(n.state.currentPlaybackPosition, closeTo(3, 1e-9));
        final moved = n.moveKeyframeLive(0.25, 0.75);
        expect(moved, 0.75);
        expect(diamondsOf(k.motion(n)), [0.75]);
        expect(n.state.currentPlaybackPosition, closeTo(5, 1e-9),
            reason: 'the playhead rides along');
      });

      test('a control shows the value its write will target', () {
        // Review Focus 2: grabbing a keyframed overlay must start from where
        // it is drawn, not from its base.
        final n = selected(at: 2);
        n.addKeyframeAtPlayhead();
        seek(n, 6);
        n.beginOverlayEdit();
        n.setOverlayMotionLive(opacity: 0);
        seek(n, 4);
        expect(n.state.overlayEditValue(OverlayProperty.opacity),
            closeTo(0.5, 1e-9));
        expect(k.motion(n).opacity, 1, reason: 'while the base stays 1');
      });

      test('a duplicate lands beside the original through its whole motion',
          () {
        // The duplicate is nudged so the user can see there are two. On a
        // keyframed overlay the tracks decide where it is drawn, so nudging
        // only the base would put the copy exactly on top of the original.
        final n = selected(at: 2);
        n.addKeyframeAtPlayhead();
        seek(n, 6);
        n.beginOverlayEdit();
        n.setOverlayMotionLive(position: const Offset(100, 50));
        final original = k.motion(n);
        k.duplicate(n);
        final copy = k.copy(n);
        expect(copy.hasKeyframes, isTrue);
        for (final p in [0.0, 0.25, 0.5, 1.0]) {
          final o = original.at(p).position, c = copy.at(p).position;
          expect(c.dx, closeTo(o.dx + 20, 1e-9), reason: 'x at $p');
          expect(c.dy, closeTo(o.dy + 20, 1e-9), reason: 'y at $p');
        }
      });
    });
  }

  group('a command that changes nothing leaves no undo step', () {
    // The plus button flips to minus once the playhead is on a diamond, so a
    // second plus is a double tap landing before the rebuild. An undo entry
    // that undoes nothing is a lie — on a clip as on an overlay.
    for (final target in ['clip', 'text']) {
      test(target, () {
        final n = project();
        target == 'clip' ? n.selectSegment('c') : n.selectTextOverlay('t');
        seek(n, 4);
        n.addKeyframeAtPlayhead();
        expect(n.state.keyframeDiamonds, hasLength(1));
        expect(n.state.canUndo, isTrue);

        n.addKeyframeAtPlayhead(); // already on it
        seek(n, 5);
        n.removeKeyframeAtPlayhead(); // nothing under the playhead
        seek(n, 11);
        n.addKeyframeAtPlayhead(); // off the target altogether
        expect(n.state.keyframeDiamonds, hasLength(1));

        n.undo();
        expect(n.state.canUndo, isFalse, reason: 'one real edit, one step');
      });
    }
  });

  test('with nothing selected there is no keyframe target', () {
    final n = project();
    seek(n, 4);
    expect(n.state.hasKeyframeTarget, isFalse);
    expect(n.state.keyframeTargetProgress, isNull);
    expect(n.state.keyframeDiamonds, isEmpty);
    n.beginOverlayEdit();
    expect(n.state.canUndo, isFalse, reason: 'nothing to edit, no snapshot');
  });

  test('a live write for an overlay that is no longer selected is dropped', () {
    // A second finger can select another overlay mid-drag, and the first
    // gesture's stale callback may still fire once before its layer rebuilds.
    final n = project();
    n.selectTextOverlay('t');
    n.beginOverlayEdit();
    n.selectImageOverlay('i');
    n.setOverlayMotionLive(id: 't', position: const Offset(50, 50));
    expect(n.state.imageOverlays.single.position, Offset.zero);
    expect(n.state.textOverlays.single.position, Offset.zero);
  });

  test('a bad gesture frame cannot poison the draft', () {
    // NaN or infinity in a keyframe is a draft jsonEncode refuses to write —
    // every later save would fail. Opacity outside 0..1 means nothing.
    final n = project();
    n.selectImageOverlay('i');
    seek(n, 3);
    n.addKeyframeAtPlayhead();
    seek(n, 5);
    n.beginOverlayEdit();
    n.setOverlayMotionLive(
      position: const Offset(double.infinity, 3),
      scale: double.nan,
      opacity: 1.4,
    );
    final overlay = n.state.imageOverlays.single;
    final m = overlay.motion;
    expect(m.at(0.75).position.dx, 0);
    expect(m.at(0.75).position.dy, 3);
    expect(m.at(0.75).scale, 1);
    expect(m.at(0.75).opacity, 1);
    expect(() => jsonEncode(overlay.toJson()), returnsNormally);
    n.setOverlayMotionLive(opacity: -0.3);
    expect(n.state.imageOverlays.single.motion.at(0.75).opacity, 0);
  });

  test('a clip keeps its diamonds when an overlay gets one', () {
    final n = project();
    n.selectSegment('c');
    seek(n, 4);
    n.addKeyframeAtPlayhead();
    final clipBefore = n.state.segments.single;
    n.selectTextOverlay('t');
    seek(n, 5);
    n.addKeyframeAtPlayhead();
    expect(n.state.segments.single, same(clipBefore));
    expect(n.state.textOverlays.single.keyframes.isEmpty, isFalse);
    expect(n.state.keyframeDiamonds.single, closeTo(0.75, 1e-9),
        reason: "the text's own diamond, on its own span");
    n.selectSegment('c');
    expect(n.state.keyframeDiamonds.single, closeTo(0.4, 1e-9),
        reason: 'reselecting the clip shows its diamond again');
  });

  test('a drag while playing pauses, adds one diamond, and undoes in one step',
      () {
    // Review Focus 1: the playhead moves every frame while playing; a live
    // edit writing at a moving playhead would leave a trail of diamonds.
    final n = project();
    n.selectTextOverlay('t');
    seek(n, 2.5);
    n.addKeyframeAtPlayhead();
    seek(n, 5.5);
    n.addKeyframeAtPlayhead();
    seek(n, 4);
    n.state = n.state.copyWith(isPlaying: true);
    final undoDepthBefore = n.state.canUndo;

    n.beginOverlayEdit();
    expect(n.state.isPlaying, isFalse);
    for (var i = 1; i <= 30; i++) {
      n.setOverlayMotionLive(position: Offset(i.toDouble(), 0));
    }
    expect(diamondsOf(n.state.textOverlays.single.motion),
        [0.125, 0.5, 0.875]);

    n.undo();
    expect(diamondsOf(n.state.textOverlays.single.motion), [0.125, 0.875]);
    expect(undoDepthBefore, isTrue);
  });

  test('✕ on the Opacity panel puts a text back — keyframes included', () {
    // Review Focus 5: the discard record knew clips and photo/video overlays
    // only, so a text's ✕ kept the drag.
    final n = project();
    n.selectTextOverlay('t');
    seek(n, 3);
    n.addKeyframeAtPlayhead();
    seek(n, 4);
    final before = n.state.textOverlays.single.toJson();
    final canUndoBefore = n.state.canUndo;

    n.openRevertibleTool('opacity');
    n.saveStateForUndo(); // the panel's onChangeStart
    n.setOverlayOpacity(0.3, takeUndoSnapshot: false);
    expect(n.state.textOverlays.single.toJson(), isNot(before));

    n.discardActiveTool();
    expect(n.state.textOverlays.single.toJson(), before);
    expect(n.state.canUndo, canUndoBefore);
  });

  test('the Opacity panel keyframes a keyframed overlay', () {
    final n = project();
    n.selectImageOverlay('i');
    seek(n, 3);
    n.addKeyframeAtPlayhead();
    seek(n, 5);
    n.setOverlayOpacity(0.2);
    final m = n.state.imageOverlays.single.motion;
    expect(diamondsOf(m), [0.25, 0.75]);
    expect(m.at(0.75).opacity, closeTo(0.2, 1e-9));
    expect(m.opacity, 1, reason: 'the base is untouched');
  });

  test('splitting a keyframed video overlay keeps the motion seamless', () {
    final n = project();
    n.selectVideoOverlay('v');
    seek(n, 2);
    n.addKeyframeAtPlayhead();
    seek(n, 6);
    n.beginOverlayEdit();
    n.setOverlayMotionLive(position: const Offset(100, 0));
    // x runs 0 → 100 over 2s–6s; cut at 3s, where x is 25.
    n.splitVideoOverlay(3);

    final halves = n.state.videoOverlays;
    expect(halves, hasLength(2));
    final left = halves.first.motion, right = halves.last.motion;
    expect(left.at(1).position.dx, closeTo(25, 1e-9));
    expect(right.at(0).position.dx, closeTo(25, 1e-9));
    expect(right.at(1).position.dx, closeTo(100, 1e-9));
    expect(left.at(0).position.dx, closeTo(0, 1e-9));
  });

}

/// The diamonds an overlay's motion shows, as progresses.
List<double> keyframeTimesOf(OverlayMotion m) {
  final out = <double>{};
  for (final p in OverlayProperty.values) {
    for (final k in m.keyframes.of(p)) {
      out.add(k.progress);
    }
  }
  return out.toList()..sort();
}
