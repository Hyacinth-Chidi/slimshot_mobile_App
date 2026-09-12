import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/effects/effect_catalog.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/video_editor_timeline_composer.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

void main() {
  group('persistence', () {
    test('both fields round-trip through toJson/fromJson', () {
      final segment = VideoSegment(
        id: 'a',
        assetId: 'asset_main',
        sourceStart: 1,
        sourceEnd: 4,
        effectId: 'vhs',
        effectIntensity: 0.75,
      );

      final restored = VideoSegment.fromJson(segment.toJson());

      expect(restored.effectId, 'vhs');
      expect(restored.effectIntensity, 0.75);
    });

    test('a draft written before effects loads with no effect and no throw', () {
      // Exactly the clip JSON a build before this stage wrote: no `effectId`,
      // no `effectIntensity`. Reading either must fall back rather than throw,
      // or every saved project becomes a crash on open.
      final legacy = <String, dynamic>{
        'id': 'legacy',
        'assetId': 'asset_main',
        'sourceStart': 0.0,
        'sourceEnd': 5.0,
        'volume': 1.0,
        'speed': 1.0,
        'isReversed': false,
        'filterId': 'warm',
        'filterIntensity': 1.0,
      };

      final restored = VideoSegment.fromJson(legacy);

      expect(restored.effectId, isNull);
      expect(restored.effectIntensity, defaultEffectIntensity);
      // The rest of the clip must survive the new fields untouched.
      expect(restored.filterId, 'warm');
      expect(restored.sourceEnd, 5.0);
    });

    test('a null effectId survives a round trip as null', () {
      final segment = VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 2);
      expect(VideoSegment.fromJson(segment.toJson()).effectId, isNull);
    });

    test('an unknown persisted id resolves to no effect rather than throwing', () {
      // A draft from a newer build, or an id renamed without a migration. The
      // clip still loads; it simply draws unaffected.
      final restored = VideoSegment.fromJson({
        'id': 'a',
        'sourceStart': 0.0,
        'sourceEnd': 2.0,
        'effectId': 'effect_from_the_future',
        'effectIntensity': 0.5,
      });

      expect(restored.effectId, 'effect_from_the_future');
      expect(videoEffectById(restored.effectId), isNull);
      expect(restored.effect, isNull);
    });
  });

  group('copyWith', () {
    test('sets an effect', () {
      final segment = VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 2);
      final graded = segment.copyWith(effectId: 'glow', effectIntensity: 0.6);

      expect(graded.effectId, 'glow');
      expect(graded.effectIntensity, 0.6);
    });

    test('clears an effect through the clearValue convention', () {
      final segment = VideoSegment(
        id: 'a',
        sourceStart: 0,
        sourceEnd: 2,
        effectId: 'glitch',
      );

      expect(segment.copyWith(clearEffectId: true).effectId, isNull);
    });

    test('clearEffectId wins over a value passed alongside it', () {
      // The same precedence clearFilterId already follows, so a caller cannot
      // half-clear a field depending on argument order.
      final segment = VideoSegment(
        id: 'a',
        sourceStart: 0,
        sourceEnd: 2,
        effectId: 'glitch',
      );

      final cleared = segment.copyWith(effectId: 'vhs', clearEffectId: true);
      expect(cleared.effectId, isNull);
    });

    test('an untouched copy keeps the effect', () {
      final segment = VideoSegment(
        id: 'a',
        sourceStart: 0,
        sourceEnd: 2,
        effectId: 'ripple',
        effectIntensity: 0.3,
      );

      final moved = segment.copyWith(sourceStart: 1);
      expect(moved.effectId, 'ripple');
      expect(moved.effectIntensity, 0.3);
    });
  });

  group('effect resolution', () {
    test('resolves a known id to its catalog entry', () {
      final segment = VideoSegment(
        id: 'a',
        sourceStart: 0,
        sourceEnd: 2,
        effectId: 'blur',
      );

      expect(segment.effect?.id, 'blur');
      expect(segment.effect?.passCount, 2);
    });
  });

  group('split', () {
    test('copies the effect to both halves', () {
      // A split is a cut, not a reason to lose the look the user applied.
      const asset = MediaAsset(
        id: 'asset_main',
        path: '/source/video.mp4',
        type: MediaAssetType.video,
        durationSeconds: 60,
        width: 1920,
        height: 1080,
        hasAudio: true,
      );

      final notifier = VideoEditorNotifier(VideoEditorService());
      addTearDown(notifier.dispose);
      notifier.state = VideoEditorState(
        assets: const [asset],
        segments: [
          VideoSegment(
            id: 'whole',
            assetId: asset.id,
            sourceStart: 0,
            sourceEnd: 10,
            effectId: 'swirl',
            effectIntensity: 0.65,
          ),
        ],
      );

      notifier.splitAtPosition(5);

      final segments = notifier.state.segments;
      expect(segments, hasLength(2));
      for (final half in segments) {
        expect(half.effectId, 'swirl', reason: half.id);
        expect(half.effectIntensity, 0.65, reason: half.id);
      }
    });
  });

  group('timeline contract', () {
    const composer = VideoEditorTimelineComposer();

    VideoEditorState stateWith(List<VideoSegment> segments) {
      const asset = MediaAsset(
        id: 'asset_main',
        path: '/source/video.mp4',
        type: MediaAssetType.video,
        durationSeconds: 60,
        width: 1920,
        height: 1080,
        hasAudio: true,
      );
      return VideoEditorState(
        assets: const [asset],
        segments: segments
            .map((segment) => segment.copyWith(assetId: asset.id))
            .toList(),
      );
    }

    test('the composer serialises both fields into the clip', () {
      final timeline = composer.compose(
        stateWith([
          VideoSegment(
            id: 'a',
            sourceStart: 0,
            sourceEnd: 3,
            effectId: 'vignette',
            effectIntensity: 0.25,
          ),
        ]),
      );

      final clip = timeline.videoClips.single;
      expect(clip.effectId, 'vignette');
      expect(clip.effectIntensity, 0.25);

      final json = clip.toJson();
      expect(json['effectId'], 'vignette');
      expect(json['effectIntensity'], 0.25);
    });

    test('an unaffected clip crosses as a null effectId', () {
      final timeline = composer.compose(
        stateWith([VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 3)]),
      );

      expect(timeline.videoClips.single.effectId, isNull);
      expect(timeline.videoClips.single.toJson()['effectId'], isNull);
    });

    test('an unknown id is dropped at the boundary, not passed to the renderer',
        () {
      // The renderer would have no shader for it; sending it on would be a
      // warning about an effect the user cannot see or remove. Degrading here
      // keeps the id in the draft (so a build that knows it still resolves it)
      // while the frame simply draws unaffected.
      final timeline = composer.compose(
        stateWith([
          VideoSegment(
            id: 'a',
            sourceStart: 0,
            sourceEnd: 3,
            effectId: 'effect_from_the_future',
          ),
        ]),
      );

      expect(timeline.videoClips.single.effectId, isNull);
    });

    test('two clips with different effects are not merged for playback', () {
      // The merged media item can carry only one effect, so it would take the
      // first clip's for both — the same rule per-clip grades already follow.
      final timeline = composer.compose(
        stateWith([
          VideoSegment(
            id: 'left',
            sourceStart: 0,
            sourceEnd: 2,
            effectId: 'vhs',
          ),
          VideoSegment(
            id: 'right',
            sourceStart: 2,
            sourceEnd: 5,
            effectId: 'glitch',
          ),
        ]),
      );

      expect(timeline.videoClips, hasLength(2));
      expect(timeline.playbackClips, hasLength(2));
    });

    test('one effected clip and one plain clip are not merged', () {
      final timeline = composer.compose(
        stateWith([
          VideoSegment(
            id: 'left',
            sourceStart: 0,
            sourceEnd: 2,
            effectId: 'vhs',
          ),
          VideoSegment(id: 'right', sourceStart: 2, sourceEnd: 5),
        ]),
      );

      expect(timeline.playbackClips, hasLength(2));
    });

    test('the same effect at different intensities is not merged', () {
      // Intensity is as much a part of the look as the effect id: a merged
      // item would run both halves at the first clip's strength.
      final timeline = composer.compose(
        stateWith([
          VideoSegment(
            id: 'left',
            sourceStart: 0,
            sourceEnd: 2,
            effectId: 'vhs',
            effectIntensity: 0.2,
          ),
          VideoSegment(
            id: 'right',
            sourceStart: 2,
            sourceEnd: 5,
            effectId: 'vhs',
            effectIntensity: 0.9,
          ),
        ]),
      );

      expect(timeline.playbackClips, hasLength(2));
    });

    test('two clips carrying the same effect still merge', () {
      // The guard must not become "never merge anything with an effect" — an
      // ordinary split of one effected clip has to stay one media item.
      final timeline = composer.compose(
        stateWith([
          VideoSegment(
            id: 'left',
            sourceStart: 0,
            sourceEnd: 2,
            effectId: 'vhs',
            effectIntensity: 0.5,
          ),
          VideoSegment(
            id: 'right',
            sourceStart: 2,
            sourceEnd: 5,
            effectId: 'vhs',
            effectIntensity: 0.5,
          ),
        ]),
      );

      expect(timeline.playbackClips, hasLength(1));
      expect(timeline.playbackClips.single.effectId, 'vhs');
    });
  });
}
