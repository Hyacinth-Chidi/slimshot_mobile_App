import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// "Apply to all" for the placement, the crop and the effect: one tap copies
/// the selected clip's onto every other clip, as one undo step.
///
/// **A copy, not a mode.** Filters and transitions toggle into a live
/// apply-to-all because their edits are single choices. A placement is a drag
/// on a ruler, and a live all-clips mode would write a keyframe into every clip
/// at the same *relative* instant on each drag — which nobody means. Set one
/// clip up, then copy it.
void main() {
  VideoSegment clip(String id) =>
      VideoSegment(id: id, sourceStart: 0, sourceEnd: 10);

  VideoEditorNotifier notifierWith(List<VideoSegment> segments, {String? selected}) {
    return VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        segments: segments,
        selectedSegmentId: selected,
        isClipSelected: selected != null,
      );
  }

  group('the placement', () {
    test('copies scale, position, rotation, their keyframes, and the mirror',
        () {
      final placed = clip('a').copyWith(
        canvasScale: const AnimatableDouble(baseValue: 1.0, keyframes: [
          Keyframe(progress: 0.0, value: 1.0),
          Keyframe(progress: 1.0, value: 2.0),
        ]),
        canvasOffsetX: const AnimatableDouble(baseValue: 0.2),
        canvasRotation: const AnimatableDouble(baseValue: 15.0),
        flipHorizontal: true,
      );
      final n = notifierWith([placed, clip('b'), clip('c')], selected: 'a');

      expect(n.applyTransformToAllClips(), 2);

      for (final s in n.state.segments.skip(1)) {
        expect(s.canvasScale.keyframes, hasLength(2), reason: s.id);
        expect(s.canvasOffsetXAt(0.5), closeTo(0.2, 1e-9), reason: s.id);
        expect(s.canvasRotationAt(0.5), closeTo(15.0, 1e-9), reason: s.id);
        expect(s.flipHorizontal, isTrue, reason: s.id);
      }
    });

    test('leaves everything that is not placement alone', () {
      final n = notifierWith(
        [
          clip('a').copyWith(canvasScale: const AnimatableDouble(baseValue: 2.0)),
          clip('b').copyWith(
            cropRect: const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8),
            effectId: 'vignette',
            opacity: const AnimatableDouble(baseValue: 0.5),
          ),
        ],
        selected: 'a',
      );
      n.applyTransformToAllClips();
      final b = n.state.segments[1];
      expect(b.canvasScale.baseValue, 2.0);
      expect(b.cropRect, const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8));
      expect(b.effectId, 'vignette');
      expect(b.opacity.baseValue, 0.5);
    });
  });

  group('the crop', () {
    test('copies the rect onto every other clip', () {
      final n = notifierWith(
        [
          clip('a').copyWith(cropRect: const Rect.fromLTWH(0.25, 0, 0.5, 1)),
          clip('b'),
        ],
        selected: 'a',
      );
      expect(n.applyCropToAllClips(), 1);
      expect(n.state.segments[1].cropRect, const Rect.fromLTWH(0.25, 0, 0.5, 1));
    });
  });

  group('the effect', () {
    test('copies the effect and its intensity onto every other clip', () {
      final n = notifierWith(
        [
          clip('a').copyWith(
            effectId: 'vignette',
            effectIntensity: const AnimatableDouble(baseValue: 0.7),
          ),
          clip('b').copyWith(effectId: 'glow'),
        ],
        selected: 'a',
      );
      expect(n.applyEffectToAllClips(), 1);
      expect(n.state.segments[1].effectId, 'vignette');
      expect(n.state.segments[1].effectIntensity.baseValue, 0.7);
    });

    test('an unaffected clip clears the others', () {
      final n = notifierWith(
        [clip('a'), clip('b').copyWith(effectId: 'glow')],
        selected: 'a',
      );
      n.applyEffectToAllClips();
      expect(n.state.segments[1].effectId, isNull);
    });
  });

  group('every one of them', () {
    test('is one undo step', () {
      final n = notifierWith(
        [
          clip('a').copyWith(canvasScale: const AnimatableDouble(baseValue: 2.0)),
          clip('b'),
          clip('c'),
        ],
        selected: 'a',
      );
      n.applyTransformToAllClips();
      n.undo();
      expect(n.state.segments[1].canvasScale.baseValue, 1.0);
      expect(n.state.segments[2].canvasScale.baseValue, 1.0);
      expect(n.state.canUndo, isFalse);
    });

    test('does nothing with no clip selected, or nothing else to write', () {
      final none = notifierWith([clip('a'), clip('b')]);
      expect(none.applyTransformToAllClips(), 0);
      expect(none.applyCropToAllClips(), 0);
      expect(none.applyEffectToAllClips(), 0);
      expect(none.state.canUndo, isFalse);

      final alone = notifierWith([clip('a')], selected: 'a');
      expect(alone.applyTransformToAllClips(), 0);
      expect(alone.state.canUndo, isFalse);
    });
  });
}
