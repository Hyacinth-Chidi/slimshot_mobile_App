import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// Replace clip: swap the media under a clip and keep the edit.
///
/// Everything the user did to the clip — trims where they still fit, speed,
/// placement and its keyframes, crop, mirror, opacity, adjustments, filter,
/// effect, transition — is about the *slot* on the timeline, not the file, and
/// survives. What cannot survive is what belonged to the old file: a proxy
/// rendered from it, and a reversal that depended on that proxy.
void main() {
  const original = MediaAsset(
    id: 'old',
    path: '/old.mp4',
    type: MediaAssetType.video,
    durationSeconds: 30,
    width: 1920,
    height: 1080,
    hasAudio: true,
  );
  const longer = MediaAsset(
    id: 'new',
    path: '/new.mp4',
    type: MediaAssetType.video,
    durationSeconds: 60,
    width: 1080,
    height: 1920,
    hasAudio: true,
  );
  const shorter = MediaAsset(
    id: 'short',
    path: '/short.mp4',
    type: MediaAssetType.video,
    durationSeconds: 6,
    width: 1080,
    height: 1920,
    hasAudio: false,
  );
  const photo = MediaAsset(
    id: 'photo',
    path: '/p.jpg',
    type: MediaAssetType.image,
    durationSeconds: 0,
    width: 1000,
    height: 1000,
    hasAudio: false,
  );

  VideoEditorNotifier notifierWith(VideoSegment segment, {bool selected = true}) {
    return VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        assets: const [original],
        segments: [segment],
        selectedSegmentId: selected ? segment.id : null,
        isClipSelected: selected,
      );
  }

  final edited = VideoSegment(
    id: 'a',
    assetId: 'old',
    sourceStart: 4,
    sourceEnd: 12,
    speed: 2.0,
    canvasScale: const AnimatableDouble(baseValue: 1.0, keyframes: [
      Keyframe(progress: 0.0, value: 1.0),
      Keyframe(progress: 1.0, value: 1.5),
    ]),
    cropRect: const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8),
    flipHorizontal: true,
    filterId: 'warm',
    effectId: 'vignette',
    transitionType: 'dissolve',
    transitionDuration: 0.5,
    overrideVideoPath: '/proxy_of_old.mp4',
  );

  test('the clip keeps its slot and its edit, on the new file', () {
    final n = notifierWith(edited);
    n.replaceClipAsset(longer);

    final s = n.state.segments.single;
    expect(s.id, 'a');
    expect(s.assetId, 'new');
    expect(s.sourceStart, 4);
    expect(s.sourceEnd, 12);
    expect(s.speed, 2.0);
    expect(s.canvasScale.keyframes, hasLength(2));
    expect(s.cropRect, const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8));
    expect(s.flipHorizontal, isTrue);
    expect(s.filterId, 'warm');
    expect(s.effectId, 'vignette');
    expect(s.transitionType, 'dissolve');
    // The proxy was rendered from the old file.
    expect(s.overrideVideoPath, isNull);
    // The new file joined the pool; the old stays for anything else using it.
    expect(n.state.assets.map((a) => a.id), containsAll(['old', 'new']));
    expect(n.state.selectedSegmentId, 'a');
  });

  test('a shorter file pulls the trim in, keeping as much length as it can',
      () {
    // 4..12 of a 30s file, onto a 6s file: the end is clamped to 6 and the
    // start slides back to keep the 8s of source the clip had, as far as the
    // file allows — 0..6.
    final n = notifierWith(edited);
    n.replaceClipAsset(shorter);
    final s = n.state.segments.single;
    expect(s.sourceStart, 0);
    expect(s.sourceEnd, 6);
  });

  test('a reversal does not survive, because its proxy did not', () {
    final n = notifierWith(edited.copyWith(isReversed: true));
    n.replaceClipAsset(longer);
    expect(n.state.segments.single.isReversed, isFalse);
  });

  test('a photo takes the clip\'s on-screen length', () {
    // 4..12 at 2× is 4s on the timeline; a photo has no source length, so it
    // is given that 4s and plays at 1×.
    final n = notifierWith(edited);
    n.replaceClipAsset(photo);
    final s = n.state.segments.single;
    expect(s.assetId, 'photo');
    expect(s.sourceStart, 0);
    expect(s.speed, 1.0);
    expect(s.duration, closeTo(4.0, 1e-9));
  });

  test('replacing with a file already in the pool adds no duplicate', () {
    final n = notifierWith(edited)
      ..state = notifierWith(edited).state.copyWith(assets: const [original, longer]);
    n.replaceClipAsset(longer);
    expect(n.state.assets.where((a) => a.id == 'new'), hasLength(1));
  });

  test('is one undo step, and nothing with no clip selected', () {
    final n = notifierWith(edited);
    n.replaceClipAsset(longer);
    n.undo();
    expect(n.state.segments.single.assetId, 'old');
    expect(n.state.assets.map((a) => a.id), ['old']);

    final none = notifierWith(edited, selected: false);
    none.replaceClipAsset(longer);
    expect(none.state.segments.single.assetId, 'old');
    expect(none.state.canUndo, isFalse);
  });
}
