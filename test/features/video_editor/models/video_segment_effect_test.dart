import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/effects/effect_catalog.dart';
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
        effectIntensity: const AnimatableDouble(baseValue: 0.75),
      );

      final restored = VideoSegment.fromJson(segment.toJson());

      expect(restored.effectId, 'vhs');
      expect(restored.effectIntensity.baseValue, 0.75);
      // A flat parameter round-trips as the bare number it always was, so a
      // draft written here still opens in a build that predates this model.
      expect(segment.toJson()['effectIntensity'], 0.75);
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
      expect(restored.effectIntensity.baseValue, defaultEffectIntensity);
      expect(restored.effectIntensity.isAnimated, isFalse);
      // The rest of the clip must survive the new fields untouched.
      expect(restored.filterId, 'warm');
      expect(restored.sourceEnd, 5.0);
    });

    test('a draft holding a bare number loads as a flat value', () {
      // **Every draft saved before this stage stores a bare number here** — it
      // was read as `(json['effectIntensity'] as num?)?.toDouble()`. It must
      // load as a plain value with no envelope and no keyframes, and it must
      // never throw: a saved project turning into a crash on open is the worst
      // failure this read could have.
      final restored = VideoSegment.fromJson({
        'id': 'a',
        'sourceStart': 0.0,
        'sourceEnd': 2.0,
        'effectId': 'vhs',
        'effectIntensity': 0.35,
      });

      expect(restored.effectIntensity.baseValue, 0.35);
      expect(restored.effectIntensity.envelope, isNull);
      expect(restored.effectIntensity.keyframes, isEmpty);
      expect(restored.effectIntensity.isAnimated, isFalse);
      // And it resolves flat, which is what makes the render identical to the
      // scalar's: the same value at every progress.
      for (final p in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        expect(restored.effectIntensityAt(p), 0.35, reason: 'at p=$p');
      }
    });

    test('a whole number in a draft loads without throwing', () {
      // `jsonDecode` gives back an `int` for a value written as `1.0` with no
      // fractional part, so the read cannot assume `double`.
      final restored = VideoSegment.fromJson({
        'id': 'a',
        'sourceStart': 0.0,
        'sourceEnd': 2.0,
        'effectIntensity': 1,
      });

      expect(restored.effectIntensity.baseValue, 1.0);
      expect(restored.effectIntensity.isAnimated, isFalse);
    });

    test('a junk intensity falls back rather than throwing', () {
      // A hand-edited or truncated draft. The clip loses its intensity, never
      // the project.
      for (final junk in <Object?>[null, 'loud', <String, dynamic>{}, []]) {
        final restored = VideoSegment.fromJson({
          'id': 'a',
          'sourceStart': 0.0,
          'sourceEnd': 2.0,
          'effectIntensity': junk,
        });
        expect(
          restored.effectIntensity.baseValue,
          defaultEffectIntensity,
          reason: 'junk: $junk',
        );
      }
    });

    test('an animated intensity round-trips through the draft', () {
      final segment = VideoSegment(
        id: 'a',
        sourceStart: 0,
        sourceEnd: 4,
        effectId: 'glitch',
        effectIntensity: AnimatableDouble.sorted(
          baseValue: 0.7,
          envelope: 'pulse',
          keyframes: const [
            Keyframe(progress: 0.2, value: 0.1),
            Keyframe(
              progress: 0.9,
              value: 0.95,
              interpolation: KeyframeInterpolation.linear,
            ),
          ],
        ),
      );

      final restored = VideoSegment.fromJson(segment.toJson());

      expect(restored.effectIntensity, segment.effectIntensity);
      // An animated parameter grows the map; only then.
      expect(segment.toJson()['effectIntensity'], isA<Map>());
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
      final graded = segment.copyWith(
        effectId: 'glow',
        effectIntensity: const AnimatableDouble(baseValue: 0.6),
      );

      expect(graded.effectId, 'glow');
      expect(graded.effectIntensity.baseValue, 0.6);
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
        effectIntensity: const AnimatableDouble(baseValue: 0.3),
      );

      final moved = segment.copyWith(sourceStart: 1);
      expect(moved.effectId, 'ripple');
      expect(moved.effectIntensity.baseValue, 0.3);
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
            // Carrying an envelope, so the split is pinned to copy the whole
            // parameter rather than just its strength — halves that kept the
            // number and lost the shape would stop animating at the cut.
            effectIntensity: const AnimatableDouble(
              baseValue: 0.65,
              envelope: 'throb',
            ),
          ),
        ],
      );

      notifier.splitAtPosition(5);

      final segments = notifier.state.segments;
      expect(segments, hasLength(2));
      for (final half in segments) {
        expect(half.effectId, 'swirl', reason: half.id);
        expect(half.effectIntensity.baseValue, 0.65, reason: half.id);
        expect(half.effectIntensity.envelope, 'throb', reason: half.id);
      }
    });
  });
}
