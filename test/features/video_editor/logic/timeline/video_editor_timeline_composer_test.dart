import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/effects/effect_catalog.dart';
import 'package:slimshotai/features/video_editor/logic/timeline/video_editor_timeline_composer.dart';
import 'package:slimshotai/features/video_editor/models/audio_track_model.dart';
import 'package:slimshotai/features/video_editor/models/image_overlay_model.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';

void main() {
  const composer = VideoEditorTimelineComposer();

  /// A single-video project whose clips all come from one asset.
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

  group('clip layout', () {
    test('composes sequential timeline clips from editor segments', () {
      final timeline = composer.compose(
        stateWith([
          VideoSegment(id: 'a', sourceStart: 1, sourceEnd: 4),
          VideoSegment(id: 'b', sourceStart: 8, sourceEnd: 12, speed: 2),
        ]),
      );

      expect(timeline.sourceVideoPath, '/source/video.mp4');
      expect(timeline.durationSeconds, 5);
      expect(timeline.videoClips, hasLength(2));
      expect(timeline.videoClips[0].timelineStart, 0);
      expect(timeline.videoClips[0].timelineEnd, 3);
      expect(timeline.videoClips[1].timelineStart, 3);
      expect(timeline.videoClips[1].timelineEnd, 5);
      expect(timeline.playbackClips, hasLength(2));
      expect(timeline.transitions, isEmpty);
    });

    test('merges plain split clips for playback without changing edit clips', () {
      final timeline = composer.compose(
        stateWith([
          VideoSegment(id: 'left', sourceStart: 0, sourceEnd: 2),
          VideoSegment(id: 'right', sourceStart: 2, sourceEnd: 5),
        ]),
      );

      expect(timeline.videoClips, hasLength(2));
      expect(timeline.playbackClips, hasLength(1));
      expect(timeline.playbackClips.single.id, 'left');
      expect(timeline.playbackClips.single.sourceStart, 0);
      expect(timeline.playbackClips.single.sourceEnd, 5);
      expect(timeline.playbackClips.single.timelineStart, 0);
      expect(timeline.playbackClips.single.timelineEnd, 5);
    });

    test('keeps speed boundaries separate for native playback', () {
      final timeline = composer.compose(
        stateWith([
          VideoSegment(id: 'left', sourceStart: 0, sourceEnd: 2),
          VideoSegment(id: 'fast', sourceStart: 2, sourceEnd: 5, speed: 2),
        ]),
      );

      expect(timeline.videoClips, hasLength(2));
      expect(timeline.playbackClips, hasLength(2));
    });

    test('extends duration to cover audio tail', () {
      final timeline = composer.compose(
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
          segments: [
            VideoSegment(
              id: 'main',
              assetId: 'asset_main',
              sourceStart: 0,
              sourceEnd: 3,
            ),
          ],
          audioTracks: const [
            AudioTrackModel(
              id: 'music',
              filePath: '/audio/music.m4a',
              sourceDuration: 10,
              sourceStart: 0,
              sourceEnd: 5,
              timelineStart: 2,
            ),
          ],
        ),
      );

      expect(timeline.durationSeconds, 7);
      expect(timeline.audioClips.single.timelineStart, 2);
      expect(timeline.audioClips.single.timelineEnd, 7);
    });

    test('extends duration to cover an overlay tail', () {
      final timeline = composer.compose(
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
          segments: [
            VideoSegment(
              id: 'main',
              assetId: 'asset_main',
              sourceStart: 0,
              sourceEnd: 3,
            ),
          ],
          imageOverlays: [
            ImageOverlayModel(
              id: 'sticker',
              imagePath: '/overlay/sticker.png',
              startTime: const Duration(seconds: 1),
              endTime: const Duration(seconds: 9),
            ),
          ],
        ),
      );

      // The project runs until the last thing on it ends, so export does not
      // cut an overlay (or an audio tail) off where the video stops.
      expect(timeline.durationSeconds, 9);
    });
  });

  group('transition overlap model', () {
    test('overlaps neighbouring clips and shortens the timeline', () {
      final timeline = composer.compose(
        stateWith([
          VideoSegment(
            id: 'left',
            sourceStart: 0,
            sourceEnd: 2,
            transitionType: 'dissolve',
            transitionDuration: 0.8,
          ),
          VideoSegment(id: 'right', sourceStart: 2, sourceEnd: 5),
        ]),
      );

      // Edit clips keep their full source ranges and overlap by 0.8s.
      expect(timeline.videoClips[0].timelineStart, 0);
      expect(timeline.videoClips[0].timelineEnd, 2);
      expect(timeline.videoClips[1].timelineStart, closeTo(1.2, 1e-9));
      expect(timeline.videoClips[1].timelineEnd, closeTo(4.2, 1e-9));

      // Total shortens by exactly the transition duration, matching xfade.
      expect(timeline.durationSeconds, closeTo(4.2, 1e-9));
    });

    test('emits the overlap region as the transition window', () {
      final timeline = composer.compose(
        stateWith([
          VideoSegment(
            id: 'left',
            sourceStart: 0,
            sourceEnd: 2,
            transitionType: 'dissolve',
            transitionDuration: 0.8,
          ),
          VideoSegment(id: 'right', sourceStart: 2, sourceEnd: 5),
        ]),
      );

      expect(timeline.transitions, hasLength(1));
      final transition = timeline.transitions.single;
      expect(transition.type, 'dissolve');
      expect(transition.leftClipId, 'left');
      expect(transition.rightClipId, 'right');
      expect(transition.leftClipIndex, 0);
      expect(transition.rightClipIndex, 1);
      expect(transition.durationSeconds, closeTo(0.8, 1e-9));
      // The window opens where the incoming clip starts, not inside the
      // outgoing clip's own tail.
      expect(transition.timelineStartSeconds, closeTo(1.2, 1e-9));
      expect(transition.timelineEndSeconds, closeTo(2.0, 1e-9));
    });

    test('keeps both clips whole so each can keep decoding through the window', () {
      final timeline = composer.compose(
        stateWith([
          VideoSegment(
            id: 'left',
            sourceStart: 0,
            sourceEnd: 2,
            transitionType: 'dissolve',
            transitionDuration: 0.8,
          ),
          VideoSegment(id: 'right', sourceStart: 2, sourceEnd: 5),
        ]),
      );

      // Nothing is trimmed away for the transition: the outgoing clip must
      // keep producing real frames for the whole window, so its tail survives.
      final left = timeline.videoClips[0];
      expect(left.sourceStart, 0);
      expect(left.sourceEnd, 2);
      expect(left.timelineEnd, 2);

      final right = timeline.videoClips[1];
      expect(right.sourceStart, 2);
      expect(right.sourceEnd, 5);
      expect(right.timelineStart, closeTo(1.2, 1e-9));
    });

    test('puts the two clips of a transition on different decoders', () {
      final timeline = composer.compose(
        stateWith([
          VideoSegment(
            id: 'left',
            sourceStart: 0,
            sourceEnd: 2,
            transitionType: 'dissolve',
            transitionDuration: 0.8,
          ),
          VideoSegment(id: 'right', sourceStart: 2, sourceEnd: 5),
        ]),
      );

      expect(timeline.videoClips[0].laneIndex, 0);
      expect(timeline.videoClips[1].laneIndex, 1);
    });

    test('keeps a run of plain cuts on one decoder', () {
      final timeline = composer.compose(
        stateWith([
          VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 2),
          VideoSegment(id: 'b', sourceStart: 2, sourceEnd: 4),
          VideoSegment(id: 'c', sourceStart: 4, sourceEnd: 6),
        ]),
      );

      // No overlap means no reason to alternate — one gapless playlist.
      expect(timeline.videoClips.map((c) => c.laneIndex), everyElement(0));
    });

    test('derives both source positions from one shared timeline clock', () {
      final timeline = composer.compose(
        stateWith([
          VideoSegment(
            id: 'left',
            sourceStart: 0,
            sourceEnd: 5,
            transitionType: 'dissolve',
            transitionDuration: 1.0,
          ),
          VideoSegment(id: 'right', sourceStart: 5, sourceEnd: 10),
        ]),
      );

      final left = timeline.videoClips[0];
      final right = timeline.videoClips[1];
      final window = timeline.transitions.single;

      // Window opens at 4.0s: A is 1s from its end, B is at its very start.
      expect(window.timelineStartSeconds, closeTo(4.0, 1e-9));
      expect(left.sourceAt(4.0), closeTo(4.0, 1e-9));
      expect(right.sourceAt(4.0), closeTo(5.0, 1e-9));

      // Halfway through, both have advanced by the same amount of real time.
      expect(left.sourceAt(4.5), closeTo(4.5, 1e-9));
      expect(right.sourceAt(4.5), closeTo(5.5, 1e-9));

      // Window closes at 5.0s: A reaches its end, B is 1s in.
      expect(window.timelineEndSeconds, closeTo(5.0, 1e-9));
      expect(left.sourceAt(5.0), closeTo(5.0, 1e-9));
      expect(right.sourceAt(5.0), closeTo(6.0, 1e-9));
    });

    test('advances the source position at clip speed', () {
      final timeline = composer.compose(
        stateWith([
          VideoSegment(id: 'fast', sourceStart: 0, sourceEnd: 8, speed: 2),
        ]),
      );

      // 2x means 2s of source per 1s of timeline.
      expect(timeline.videoClips.single.sourceAt(1.0), closeTo(2.0, 1e-9));
      expect(timeline.videoClips.single.sourceAt(2.0), closeTo(4.0, 1e-9));
    });

    test('accumulates shortening across several transitions', () {
      final timeline = composer.compose(
        stateWith([
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
        ]),
      );

      expect(timeline.durationSeconds, closeTo(9 - 1.6, 1e-9));
      expect(timeline.transitions, hasLength(2));
      expect(timeline.transitions[0].timelineStartSeconds, closeTo(2.2, 1e-9));
      expect(timeline.transitions[1].timelineStartSeconds, closeTo(4.4, 1e-9));
      expect(timeline.videoClips, hasLength(3));

      // Lanes ping-pong so no decoder is ever asked for two overlapping clips.
      expect(timeline.videoClips.map((c) => c.laneIndex), [0, 1, 0]);

      // Each consecutive pair overlaps by exactly its transition duration.
      for (var i = 0; i < timeline.transitions.length; i++) {
        final transition = timeline.transitions[i];
        expect(
          timeline.videoClips[i + 1].timelineStart,
          closeTo(transition.timelineStartSeconds, 1e-9),
        );
        expect(
          timeline.videoClips[i].timelineEnd,
          closeTo(transition.timelineEndSeconds, 1e-9),
        );
      }
    });

    test('clamps the duration against the shorter neighbouring clip', () {
      final timeline = composer.compose(
        stateWith([
          VideoSegment(
            id: 'short',
            sourceStart: 0,
            sourceEnd: 1,
            transitionType: 'dissolve',
            transitionDuration: 2.0,
          ),
          VideoSegment(id: 'long', sourceStart: 1, sourceEnd: 5),
        ]),
      );

      // 45% of the 1s clip, not the requested 2s.
      expect(timeline.transitions.single.durationSeconds, closeTo(0.45, 1e-9));
      // Clips report the clamped value, never the raw request.
      expect(timeline.videoClips.first.transitionDuration, closeTo(0.45, 1e-9));
      expect(timeline.durationSeconds, closeTo(4.55, 1e-9));
    });

    test('falls back to the default duration when none is set', () {
      final timeline = composer.compose(
        stateWith([
          VideoSegment(
            id: 'left',
            sourceStart: 0,
            sourceEnd: 5,
            transitionType: 'dissolve',
          ),
          VideoSegment(id: 'right', sourceStart: 5, sourceEnd: 10),
        ]),
      );

      expect(timeline.transitions.single.durationSeconds, closeTo(0.8, 1e-9));
    });
  });

  group('transition degradation', () {
    test('treats a retired transition type as a hard cut', () {
      final timeline = composer.compose(
        stateWith([
          VideoSegment(
            id: 'left',
            sourceStart: 0,
            sourceEnd: 2,
            // Saved by an older build that still offered circle transitions.
            transitionType: 'circleOpen',
            transitionDuration: 0.8,
          ),
          VideoSegment(id: 'right', sourceStart: 2, sourceEnd: 5),
        ]),
      );

      expect(timeline.transitions, isEmpty);
      expect(timeline.durationSeconds, 5);
      expect(timeline.videoClips.first.transitionType, isNull);
      expect(timeline.videoClips.first.transitionDuration, isNull);
      // Degrades all the way back to a mergeable plain split.
      expect(timeline.playbackClips, hasLength(1));
    });

    test('ignores a transition on the final segment', () {
      final timeline = composer.compose(
        stateWith([
          VideoSegment(
            id: 'only',
            sourceStart: 0,
            sourceEnd: 4,
            transitionType: 'dissolve',
            transitionDuration: 0.8,
          ),
        ]),
      );

      expect(timeline.transitions, isEmpty);
      expect(timeline.durationSeconds, 4);
      expect(timeline.playbackClips.single.timelineEnd, 4);
    });
  });

  group('reverse proxies', () {
    test('marks reversed clips without proxy as needing preparation', () {
      final timeline = composer.compose(
        stateWith([
          VideoSegment(
            id: 'reverse',
            sourceStart: 0,
            sourceEnd: 2,
            isReversed: true,
          ),
        ]),
      );

      expect(timeline.needsReverseProxy, isTrue);
      expect(timeline.videoClips.single.needsReverseProxy, isTrue);
      expect(timeline.videoClips.single.playbackVideoPath, '/source/video.mp4');
    });

    test('uses override path as prepared playback proxy', () {
      final timeline = composer.compose(
        stateWith([
          VideoSegment(
            id: 'reverse',
            sourceStart: 0,
            sourceEnd: 2,
            isReversed: true,
            overrideVideoPath: '/cache/reverse.mp4',
          ),
        ]),
      );

      expect(timeline.needsReverseProxy, isFalse);
      expect(timeline.videoClips.single.hasPreparedProxy, isTrue);
      expect(timeline.videoClips.single.playbackVideoPath, '/cache/reverse.mp4');
    });
  });

  // A per-clip filter reaches the renderer as `colorMatrix` on the clip, and
  // nothing pinned that until a per-clip effect was added *in its place* rather
  // than beside it — every clip then arrived ungraded and filters silently did
  // nothing, through a green suite of 293 tests and onto a device.
  group('per-clip look', () {
    test('a clip filter travels as the clip colour matrix', () {
      final timeline = composer.compose(
        stateWith([
          VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 4, filterId: 'neon'),
        ]),
      );

      final matrix = timeline.videoClips.single.colorMatrix;
      expect(
        matrix,
        isNotNull,
        reason: 'a filtered clip must carry its grade to the renderer',
      );
      // Flutter's ColorFilter.matrix layout: 4 rows of 5.
      expect(matrix, hasLength(20));
    });

    test('an unfiltered clip carries no matrix', () {
      final timeline = composer.compose(
        stateWith([VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 4)]),
      );
      expect(timeline.videoClips.single.colorMatrix, isNull);
    });

    test('the grade and the effect are independent per clip', () {
      // They apply at different moments — the grade per lane before the blend,
      // the effect whole-frame after compositing — so carrying one must never
      // cost the other.
      final timeline = composer.compose(
        stateWith([
          VideoSegment(
            id: 'a',
            sourceStart: 0,
            sourceEnd: 4,
            filterId: 'neon',
            effectId: 'vignette',
          ),
        ]),
      );

      final clip = timeline.videoClips.single;
      expect(clip.colorMatrix, isNotNull);
      expect(clip.effectId, 'vignette');
    });

    test('a static effect carries no animation window', () {
      // Null is what tells the renderer to measure progress across the whole
      // clip and expect the shader to ignore it — which is every effect
      // written before the clock existed.
      final timeline = composer.compose(
        stateWith([
          VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 4,
              effectId: 'vignette'),
        ]),
      );
      expect(timeline.videoClips.single.effectIntroSeconds, isNull);
    });

    test('an intro carries the catalog window, not a stored one', () {
      // Read from the catalog at compose time so retuning an intro's length
      // reaches saved projects without a draft migration.
      final timeline = composer.compose(
        stateWith([
          VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 4,
              effectId: 'fade_in'),
        ]),
      );

      final clip = timeline.videoClips.single;
      expect(clip.effectId, 'fade_in');
      expect(clip.effectIntroSeconds, videoEffectById('fade_in')!.introSeconds);
      expect(clip.toJson()['effectIntroSeconds'], clip.effectIntroSeconds);
    });

    test('two clips carrying the same intro are never merged', () {
      // The id and intensity guards both pass here — the effects are
      // identical — and merging would still be wrong: progress is measured
      // from the merged clip's start, so the second clip's fade would never
      // play and the cut the user put an intro on would run straight through.
      final timeline = composer.compose(
        stateWith([
          VideoSegment(id: 'left', sourceStart: 0, sourceEnd: 2,
              effectId: 'fade_in'),
          VideoSegment(id: 'right', sourceStart: 2, sourceEnd: 5,
              effectId: 'fade_in'),
        ]),
      );

      expect(timeline.videoClips, hasLength(2));
      expect(timeline.playbackClips, hasLength(2),
          reason: 'a merged item would swallow the second intro');
    });

    test('two clips carrying the same static effect still merge', () {
      // The counterpart of the test above: the refusal must be about the
      // *clock*, not about effects in general, or every effected project
      // would lose gapless playback across a plain split.
      final timeline = composer.compose(
        stateWith([
          VideoSegment(id: 'left', sourceStart: 0, sourceEnd: 2,
              effectId: 'vignette'),
          VideoSegment(id: 'right', sourceStart: 2, sourceEnd: 5,
              effectId: 'vignette'),
        ]),
      );

      expect(timeline.playbackClips, hasLength(1));
    });
  });

  group('keyframed clips on the wire', () {
    test('a keyframed transform reaches the timeline clip and resolves there',
        () {
      final timeline = composer.compose(
        stateWith([
          VideoSegment(
            id: 'a',
            sourceStart: 0,
            sourceEnd: 4,
            canvasScale: const AnimatableDouble(baseValue: 1.0, keyframes: [
              Keyframe(progress: 0.0, value: 1.0),
              Keyframe(progress: 1.0, value: 3.0),
            ]),
          ),
        ]),
      );

      final clip = timeline.videoClips.single;
      expect(clip.hasKeyframes, isTrue);
      // The composer must not flatten the curve on the way through: the clip
      // resolves the same value the segment does, at the same instant.
      expect(clip.canvasScaleAt(0.5), closeTo(2.0, 1e-9));
      expect(clip.clipProgressAt(2.0), closeTo(0.5, 1e-9));
    });

    test('an unanimated clip composes bare numbers, not maps', () {
      final timeline = composer.compose(
        stateWith([VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 4)]),
      );
      final wire = timeline.videoClips.single.toJson();

      // The shape is the contract: a clip nobody keyframed crosses the channel
      // exactly as it always has, so introducing this model changed nothing for
      // every project already saved.
      expect(wire['volume'], isA<num>());
      expect(wire['canvasScale'], isA<num>());
      expect(wire['canvasOffsetX'], isA<num>());
      expect(wire['canvasOffsetY'], isA<num>());
    });

    test('a keyframed field crosses as a map Kotlin can read', () {
      final timeline = composer.compose(
        stateWith([
          VideoSegment(
            id: 'a',
            sourceStart: 0,
            sourceEnd: 4,
            volume: const AnimatableDouble(baseValue: 1.0, keyframes: [
              Keyframe(progress: 0.0, value: 1.0),
              Keyframe(
                progress: 1.0,
                value: 0.0,
                interpolation: KeyframeInterpolation.quadOut,
              ),
            ]),
          ),
        ]),
      );

      final wire = timeline.videoClips.single.toJson()['volume'];
      expect(wire, isA<Map>());
      expect((wire as Map)['baseValue'], 1.0);
      final keyframes = wire['keyframes'] as List;
      expect(keyframes, hasLength(2));
      // The enum's `.name`, which is the `wireName` Kotlin declares.
      expect((keyframes.last as Map)['interpolation'], 'quadOut');
    });

    test('a keyframed clip is never merged for playback', () {
      // Two adjacent cuts from one file that would otherwise collapse into a
      // single media item. A curve is measured across *a clip*, so merging
      // would resolve one curve over the pair and the second clip's diamonds
      // would never land where the user put them.
      final timeline = composer.compose(
        stateWith([
          VideoSegment(
            id: 'a',
            sourceStart: 0,
            sourceEnd: 4,
            canvasScale: const AnimatableDouble(
              baseValue: 1.0,
              keyframes: [Keyframe(progress: 0.5, value: 2.0)],
            ),
          ),
          VideoSegment(id: 'b', sourceStart: 4, sourceEnd: 8),
        ]),
      );
      expect(timeline.playbackClips, hasLength(2));
    });

    test('two identically keyframed clips still do not merge', () {
      // Not about the two values disagreeing — it is that the merge destroys
      // the span each curve runs over.
      const curve = AnimatableDouble(
        baseValue: 1.0,
        keyframes: [Keyframe(progress: 0.5, value: 2.0)],
      );
      final timeline = composer.compose(
        stateWith([
          VideoSegment(
              id: 'a', sourceStart: 0, sourceEnd: 4, canvasScale: curve),
          VideoSegment(
              id: 'b', sourceStart: 4, sourceEnd: 8, canvasScale: curve),
        ]),
      );
      expect(timeline.playbackClips, hasLength(2));
    });

    test('unkeyframed neighbours still merge, so nothing regressed', () {
      final timeline = composer.compose(
        stateWith([
          VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 4),
          VideoSegment(id: 'b', sourceStart: 4, sourceEnd: 8),
        ]),
      );
      expect(timeline.playbackClips, hasLength(1));
    });
  });
}
