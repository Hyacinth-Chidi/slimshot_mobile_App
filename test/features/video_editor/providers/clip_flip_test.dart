import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/video_editor_timeline_composer.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// Flip: a clip mirrored across its own vertical or horizontal axis.
///
/// Not a rotation. Rotating by 180° turns the picture upside down *and*
/// back-to-front; a mirror does only the second, which is what selfie footage
/// needs. Two booleans on the clip, applied to the fitted coordinate in the
/// shader before the content rect — so they mirror the picture inside its own
/// frame and leave the frame where it sits on the canvas.
void main() {
  const asset = MediaAsset(
    id: 'a',
    path: '/v.mp4',
    type: MediaAssetType.video,
    durationSeconds: 60,
    width: 1920,
    height: 1080,
    hasAudio: true,
  );

  VideoSegment clip(String id, {double start = 0, double end = 10}) =>
      VideoSegment(id: id, assetId: 'a', sourceStart: start, sourceEnd: end);

  VideoEditorNotifier notifierWith(List<VideoSegment> segments,
      {String? selected, double position = 0}) {
    return VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        assets: const [asset],
        segments: segments,
        selectedSegmentId: selected,
        isClipSelected: selected != null,
        currentPlaybackPosition: position,
      );
  }

  group('the model', () {
    test('defaults to unflipped and writes nothing for it', () {
      final s = clip('a');
      expect(s.flipHorizontal, isFalse);
      expect(s.flipVertical, isFalse);
      // Absent keys, not `false`: a project nobody flipped writes exactly what
      // it always wrote, and an older build reads it unchanged.
      final json = s.toJson();
      expect(json.containsKey('flipHorizontal'), isFalse);
      expect(json.containsKey('flipVertical'), isFalse);
    });

    test('round-trips each axis on its own', () {
      final h = clip('a').copyWith(flipHorizontal: true);
      final restoredH = VideoSegment.fromJson(jsonDecode(jsonEncode(h.toJson())));
      expect(restoredH.flipHorizontal, isTrue);
      expect(restoredH.flipVertical, isFalse);

      final v = clip('a').copyWith(flipVertical: true);
      final restoredV = VideoSegment.fromJson(jsonDecode(jsonEncode(v.toJson())));
      expect(restoredV.flipHorizontal, isFalse);
      expect(restoredV.flipVertical, isTrue);
    });

    test('junk reads as unflipped', () {
      final s = VideoSegment.fromJson(const {
        'id': 'a',
        'sourceStart': 0.0,
        'sourceEnd': 5.0,
        'flipHorizontal': 'yes',
        'flipVertical': 1,
      });
      expect(s.flipHorizontal, isFalse);
      expect(s.flipVertical, isFalse);
    });
  });

  group('the notifier', () {
    test('toggles an axis on the selected clip as one undo step', () {
      final n = notifierWith([clip('a')], selected: 'a');
      n.toggleClipFlip(horizontal: true);
      expect(n.state.segments.single.flipHorizontal, isTrue);
      expect(n.state.segments.single.flipVertical, isFalse);

      n.toggleClipFlip(horizontal: true);
      expect(n.state.segments.single.flipHorizontal, isFalse);

      n.undo();
      expect(n.state.segments.single.flipHorizontal, isTrue);
    });

    test('does nothing with no clip selected', () {
      final n = notifierWith([clip('a')]);
      n.toggleClipFlip(horizontal: false);
      expect(n.state.segments.single.flipVertical, isFalse);
      expect(n.state.canUndo, isFalse);
    });

    test('resetting the transform clears the flips too', () {
      // Double-tap on the canvas means "put the clip back the way it came",
      // and a mirrored clip did not come mirrored.
      final n = notifierWith([clip('a')], selected: 'a');
      n.toggleClipFlip(horizontal: true);
      n.toggleClipFlip(horizontal: false);
      n.resetClipCanvasTransform();
      expect(n.state.segments.single.flipHorizontal, isFalse);
      expect(n.state.segments.single.flipVertical, isFalse);
    });

    test('a split carries the flips to both halves', () {
      final n = notifierWith([clip('a')], selected: 'a', position: 5.0);
      n.toggleClipFlip(horizontal: true);
      n.splitAtPosition(5.0);
      expect(n.state.segments, hasLength(2));
      for (final s in n.state.segments) {
        expect(s.flipHorizontal, isTrue, reason: s.id);
      }
    });
  });

  group('the timeline contract', () {
    const composer = VideoEditorTimelineComposer();

    test('carries the flips, and only when set', () {
      final flipped = composer
          .compose(notifierWith([clip('a').copyWith(flipVertical: true)]).state)
          .toJson();
      final json = (flipped['videoClips'] as List).single as Map<String, dynamic>;
      expect(json['flipVertical'], isTrue);
      expect(json.containsKey('flipHorizontal'), isFalse);

      final plain =
          composer.compose(notifierWith([clip('a')]).state).toJson();
      final plainJson =
          (plain['videoClips'] as List).single as Map<String, dynamic>;
      expect(plainJson.containsKey('flipHorizontal'), isFalse);
      expect(plainJson.containsKey('flipVertical'), isFalse);
    });

    test('differently flipped neighbours are not merged for playback', () {
      final timeline = composer.compose(notifierWith([
        clip('a', start: 0, end: 4).copyWith(flipHorizontal: true),
        clip('b', start: 4, end: 8),
      ]).state);
      expect(timeline.playbackClips, hasLength(2));
    });

    test('the clip under the crop handles shows unflipped', () {
      // Plain means plain: the handles map through the fit alone, and a
      // mirrored picture would put the user\'s rectangle on the wrong side.
      final state = notifierWith([clip('a').copyWith(flipHorizontal: true)],
              selected: 'a')
          .state
          .copyWith(activeToolId: 'clip_crop');
      final timeline = composer.compose(state);
      expect(timeline.videoClips.single.flipHorizontal, isFalse);
    });
  });
}
