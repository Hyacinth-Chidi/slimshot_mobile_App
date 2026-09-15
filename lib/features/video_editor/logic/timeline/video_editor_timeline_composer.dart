import 'dart:ui';

import '../../models/audio_track_model.dart';
import '../../models/editor_timeline.dart';
import '../../models/video_editor_state.dart';
import '../../models/video_segment.dart';
import '../canvas_geometry.dart';
import 'timeline_geometry.dart';

/// Turns editor state into the timeline contract the native engine consumes.
///
/// Transitions are modelled as an **overlap**: when clip A transitions into
/// clip B over `D` seconds, B starts `D` before A ends and the total timeline
/// shortens by `D`. Clips keep their full source ranges. This is exactly what
/// FFmpeg `xfade` does, which is what keeps preview and export in agreement.
/// Fixed boxes the editor lays overlays out in, in preview-canvas pixels.
const double _kImageOverlayBoxPx = 200.0;
const double _kVideoOverlayBoxPx = 240.0;

/// Distance a slide animation travels, in the same pixels.
const double _kSlideDistancePx = 200.0;

class VideoEditorTimelineComposer {
  const VideoEditorTimelineComposer();

  /// [previewCanvasSize] is the on-screen size of the preview.
  ///
  /// Overlay position and size are stored in *those* pixels, so it is needed to
  /// convert them into canvas fractions. Without it overlays are omitted rather
  /// than placed wrongly — a missing overlay is obvious, a misplaced one is not.
  /// [extraOverlays] are appended to the composed overlay list — already in
  /// canvas fractions, because the caller produced them (rasterised text for
  /// export takes this route).
  EditorTimeline compose(
    VideoEditorState state, {
    Size? previewCanvasSize,
    List<EditorTimelineOverlay> extraOverlays = const [],
  }) {
    final sourceVideoPath = state.sourceVideo?.path;
    if (sourceVideoPath == null || sourceVideoPath.isEmpty) {
      throw StateError('Cannot compose a timeline without a source video.');
    }

    // Each clip resolves its own file. A project can mix several videos and
    // photos, so there is no single source path — the timeline-level one is
    // only a fallback for clips whose asset cannot be resolved.
    String pathFor(VideoSegment segment) =>
        state.assetFor(segment)?.path ?? sourceVideoPath;

    bool isImage(VideoSegment segment) =>
        state.assetFor(segment)?.isImage ?? false;

    Size sizeOf(VideoSegment segment) {
      final asset = state.assetFor(segment);
      return asset == null ? Size.zero : Size(asset.width, asset.height);
    }

    final segments = state.segments;
    // Shared with the Flutter-side timeline geometry so the UI and the native
    // engine can never disagree about where clips sit.
    final transitionDurations = segmentTransitionDurations(segments);

    var timelineCursor = 0.0;
    var laneIndex = 0;
    final videoClips = <EditorTimelineVideoClip>[];

    for (var index = 0; index < segments.length; index++) {
      final segment = segments[index];
      final timelineStart = timelineCursor;
      final timelineEnd = timelineStart + segment.duration;
      final transitionDuration = transitionDurations[index];

      videoClips.add(
        _composeVideoClip(
          segment,
          sourceVideoPath: pathFor(segment),
          isImage: isImage(segment),
          sourceSize: sizeOf(segment),
          timelineStart: timelineStart,
          timelineEnd: timelineEnd,
          laneIndex: laneIndex,
          resolvedTransitionDuration: transitionDuration,
        ),
      );

      // The next clip starts early by the transition duration, so the two
      // overlap for exactly that long.
      timelineCursor = timelineEnd - (transitionDuration ?? 0.0);

      // Only an overlap forces the next clip onto the other decoder. A run of
      // plain cuts stays on one lane so it can play as a gapless playlist.
      if (transitionDuration != null) {
        laneIndex = 1 - laneIndex;
      }
    }

    final videoDuration = videoClips.isEmpty ? 0.0 : videoClips.last.timelineEnd;

    return EditorTimeline(
      sourceVideoPath: sourceVideoPath,
      sourceDurationSeconds: state.durationSeconds,
      durationSeconds: _projectEndSeconds(videoDuration, state),
      canvas: EditorTimelineCanvas(
        backgroundColor: state.backgroundColor,
        backgroundType: state.backgroundType.name,
        backgroundBlurIntensity: state.backgroundBlurIntensity,
        cropRatio: state.selectedRatio.name,
        customCropRect: state.customCropRect,
        videoScale: state.videoScale,
        videoPan: state.videoPan,
        aspectRatio: state.projectAspectRatio,
        width: state.projectCanvasSize.width,
        height: state.projectCanvasSize.height,
        contentRect: _resolveContentRect(state, previewCanvasSize),
        colorMatrix: state.selectedFilter?.getInterpolatedMatrix(
          state.filterIntensity,
        ),
      ),
      videoClips: videoClips,
      playbackClips: _composePlaybackClips(videoClips),
      transitions: _composeTransitions(videoClips, transitionDurations),
      audioClips: state.audioTracks
          .map(_composeAudioClip)
          .toList(growable: false),
      overlays: _composeOverlays(state, previewCanvasSize, extraOverlays),
      isMuted: state.isMuted,
    );
  }

  /// The part of each frame the canvas shows.
  ///
  /// While the crop tool is open the preview deliberately shows the *whole*
  /// frame with the crop rectangle drawn over it, so the user can see what they
  /// are excluding. Cropping only takes effect once the tool is closed.
  ///
  /// Zoom and pan follow the live preview values while their panel is open, so
  /// dragging the slider is reflected immediately.
  Rect _resolveContentRect(VideoEditorState state, Size? previewCanvasSize) {
    if (state.activeToolId == 'crop') {
      return const Rect.fromLTWH(0, 0, 1, 1);
    }

    return resolveContentRect(
      cropRect: state.selectedRatio == EditorCropRatio.custom
          ? state.customCropRect
          : const Rect.fromLTWH(0, 0, 1, 1),
      videoScale: state.previewVideoScale ?? state.videoScale,
      videoPan: state.previewVideoPan ?? state.videoPan,
      previewCanvasSize: previewCanvasSize,
    );
  }

  /// Normalises overlays out of preview-canvas pixels into canvas fractions.
  ///
  /// The editor lays overlays out in device pixels — an image inside a fixed
  /// 200×200 box, a video inside 240×240, centred on the canvas centre plus an
  /// offset. Those numbers mean different things on different screens, so they
  /// are converted here and the renderer only ever sees fractions.
  List<EditorTimelineOverlay> _composeOverlays(
    VideoEditorState state,
    Size? previewCanvasSize,
    List<EditorTimelineOverlay> extraOverlays,
  ) {
    final canvas = previewCanvasSize;
    if (canvas == null || canvas.width <= 0 || canvas.height <= 0) {
      return List.of(extraOverlays);
    }

    EditorTimelineOverlay build({
      required String id,
      required String kind,
      required String path,
      required Offset position,
      required double box,
      required double scale,
      required double rotation,
      required double opacity,
      required double startSeconds,
      required double endSeconds,
      required int laneIndex,
      String? animationIn,
      String? animationOut,
      required double animationInSeconds,
      required double animationOutSeconds,
      double sourceStart = 0,
      double sourceEnd = 0,
      double volume = 1.0,
      bool isMuted = false,
    }) {
      return EditorTimelineOverlay(
        id: id,
        kind: kind,
        path: path,
        centerX: 0.5 + (position.dx / canvas.width),
        centerY: 0.5 + (position.dy / canvas.height),
        boxWidth: box / canvas.width,
        boxHeight: box / canvas.height,
        scale: scale,
        rotation: rotation,
        opacity: opacity,
        startSeconds: startSeconds,
        endSeconds: endSeconds,
        laneIndex: laneIndex,
        // The editor slides overlays a fixed 200px; as a fraction that keeps
        // the motion proportional on any screen.
        slideOffsetX: _kSlideDistancePx / canvas.width,
        slideOffsetY: _kSlideDistancePx / canvas.height,
        animationIn: animationIn,
        animationOut: animationOut,
        animationInSeconds: animationInSeconds,
        animationOutSeconds: animationOutSeconds,
        sourceStart: sourceStart,
        sourceEnd: sourceEnd,
        volume: volume,
        isMuted: isMuted,
      );
    }

    final overlays = <EditorTimelineOverlay>[
      for (final overlay in state.imageOverlays)
        build(
          id: overlay.id,
          kind: 'image',
          path: overlay.imagePath,
          position: overlay.position,
          box: _kImageOverlayBoxPx,
          scale: overlay.scale,
          rotation: overlay.rotation,
          opacity: overlay.opacity,
          startSeconds: overlay.startTime.inMilliseconds / 1000.0,
          endSeconds: overlay.endTime.inMilliseconds / 1000.0,
          laneIndex: overlay.laneIndex,
          animationIn: overlay.animationIn,
          animationOut: overlay.animationOut,
          animationInSeconds: overlay.animationInDuration,
          animationOutSeconds: overlay.animationOutDuration,
        ),
      for (final overlay in state.videoOverlays)
        build(
          id: overlay.id,
          kind: 'video',
          path: overlay.videoPath,
          position: overlay.position,
          box: _kVideoOverlayBoxPx,
          scale: overlay.scale,
          rotation: overlay.rotation,
          opacity: overlay.opacity,
          startSeconds: overlay.timelineStart.inMilliseconds / 1000.0,
          endSeconds: overlay.timelineEnd.inMilliseconds / 1000.0,
          laneIndex: overlay.laneIndex,
          animationIn: overlay.animationIn,
          animationOut: overlay.animationOut,
          animationInSeconds: overlay.animationInDuration,
          animationOutSeconds: overlay.animationOutDuration,
          sourceStart: overlay.sourceStart,
          sourceEnd: overlay.sourceEnd,
          volume: overlay.volume,
          isMuted: overlay.isMuted,
        ),
      ...extraOverlays,
    ];

    // Lower lanes paint first so higher ones land on top.
    overlays.sort((a, b) => a.laneIndex.compareTo(b.laneIndex));
    return overlays;
  }

  List<EditorTimelineTransition> _composeTransitions(
    List<EditorTimelineVideoClip> clips,
    List<double?> transitionDurations,
  ) {
    final transitions = <EditorTimelineTransition>[];

    for (var index = 0; index < clips.length - 1; index++) {
      final duration = transitionDurations[index];
      if (duration == null) continue;

      final left = clips[index];
      final type = left.transitionType;
      if (type == null) continue;

      transitions.add(
        EditorTimelineTransition(
          leftClipId: left.id,
          rightClipId: clips[index + 1].id,
          leftClipIndex: index,
          rightClipIndex: index + 1,
          type: type,
          durationSeconds: duration,
          // The overlap window: it opens when the incoming clip starts and
          // closes where the outgoing clip ends.
          timelineStartSeconds: left.timelineEnd - duration,
          timelineEndSeconds: left.timelineEnd,
        ),
      );
    }

    return transitions;
  }

  /// The clip list a single decoder can walk end to end.
  ///
  /// Clips keep their **full** source ranges — nothing is trimmed for the sake
  /// of a transition, because during a transition both clips must keep
  /// producing real frames. Adjacent plain cuts from one contiguous source are
  /// merged so the decoder is never reset mid-run.
  ///
  /// This list is only a valid description of playback when [EditorTimeline.
  /// transitions] is empty; with transitions the clips overlap in time and the
  /// engine schedules them per lane instead.
  List<EditorTimelineVideoClip> _composePlaybackClips(
    List<EditorTimelineVideoClip> clips,
  ) {
    final playbackClips = <EditorTimelineVideoClip>[];

    for (final clip in clips) {
      if (playbackClips.isNotEmpty &&
          _canMergeForPlayback(playbackClips.last, clip)) {
        playbackClips.add(_merge(playbackClips.removeLast(), clip));
      } else {
        playbackClips.add(clip);
      }
    }

    return playbackClips;
  }

  EditorTimelineVideoClip _merge(
    EditorTimelineVideoClip previous,
    EditorTimelineVideoClip next,
  ) {
    return EditorTimelineVideoClip(
      id: previous.id,
      sourceVideoPath: previous.sourceVideoPath,
      playbackVideoPath: previous.playbackVideoPath,
      sourceStart: previous.sourceStart,
      sourceEnd: next.sourceEnd,
      timelineStart: previous.timelineStart,
      timelineEnd: next.timelineEnd,
      speed: previous.speed,
      volume: previous.volume,
      isReversed: previous.isReversed,
      hasPreparedProxy: previous.hasPreparedProxy,
      isImage: previous.isImage,
      laneIndex: previous.laneIndex,
      transitionType: next.transitionType,
      transitionDuration: next.transitionDuration,
      overrideVideoPath: previous.overrideVideoPath,
      colorMatrix: previous.colorMatrix,
      effectId: previous.effectId,
      effectIntensity: previous.effectIntensity,
      effectIntroSeconds: previous.effectIntroSeconds,
      canvasScale: previous.canvasScale,
      canvasOffsetX: previous.canvasOffsetX,
      canvasOffsetY: previous.canvasOffsetY,
    );
  }

  bool _canMergeForPlayback(
    EditorTimelineVideoClip previous,
    EditorTimelineVideoClip next,
  ) {
    const epsilon = 0.001;

    // A clip that transitions out has a truncated tail the renderer needs to
    // find as its own clip boundary, so it can never be merged forward.
    if (previous.transitionDuration != null) return false;

    // A photo is a duration, not a source range, so it can never merge with
    // anything — including another photo from the same file.
    if (previous.isImage || next.isImage) return false;

    // Two clips graded differently must stay separate media items, or the
    // merged one would take the first clip's look for both.
    if (!_sameMatrix(previous.colorMatrix, next.colorMatrix)) return false;

    // Same for an effect, for the same reason: the merged item is drawn
    // through one shader chain at one strength, so it would run the first
    // clip's effect over both. Intensity counts as much as the id — the same
    // effect at two strengths is two looks.
    const intensityEpsilon = 0.001;
    if (previous.effectId != next.effectId) return false;

    // **An animated intensity can never merge, even with an identical one.**
    // This is the same rule `effectIntroSeconds` follows two checks down, and
    // for the same reason: an envelope and a keyframe row are both measured
    // across *a clip*, so a merged item resolves one curve over the pair. The
    // second clip's pulse would never land where the user put it, and a
    // `ramp_in` would build across both clips instead of arriving twice.
    // Unlike the intensity comparison below, this is not about the two values
    // disagreeing — two clips carrying byte-identical parameters still must
    // not merge, because it is the *span* the curve runs over that the merge
    // destroys.
    if (previous.effectIntensity.isAnimated || next.effectIntensity.isAnimated) {
      return false;
    }

    // Neither animates, so comparing the base values is comparing the whole
    // parameter.
    if ((previous.effectIntensity.baseValue - next.effectIntensity.baseValue)
            .abs() >
        intensityEpsilon) {
      return false;
    }

    // **A timed effect can never merge, even with an identical one.** The
    // checks above pass when both clips carry the same intro at the same
    // strength — and merging them is exactly wrong: progress is measured from
    // the *merged* clip's start, so the second clip's intro would never play.
    // The picture would open with one fade and then run straight through a cut
    // the user put an intro on. Unlike the checks above this is not about the
    // two looks disagreeing; it is that an intro belongs to a clip's opening
    // and a merge destroys the opening.
    if (previous.effectIntroSeconds != null ||
        next.effectIntroSeconds != null) {
      return false;
    }

    // **A keyframed clip never merges**, and this is the same rule the
    // animated-intensity check above follows, for the same reason: a keyframe's
    // progress is measured across *a clip*, so a merged media item would
    // resolve one curve over the pair and the second clip's diamonds would
    // never land where the user placed them. Two clips carrying byte-identical
    // keyframes still must not merge — it is the *span* the curve runs over
    // that the merge destroys.
    if (previous.hasKeyframes || next.hasKeyframes) return false;

    // Same for the canvas transform: a merged item can only carry one. Neither
    // clip is keyframed by the time this runs, so comparing base values is
    // comparing the whole parameter.
    const transformEpsilon = 0.001;
    if ((previous.canvasScale.baseValue - next.canvasScale.baseValue).abs() >
            transformEpsilon ||
        (previous.canvasOffsetX.baseValue - next.canvasOffsetX.baseValue).abs() >
            transformEpsilon ||
        (previous.canvasOffsetY.baseValue - next.canvasOffsetY.baseValue).abs() >
            transformEpsilon) {
      return false;
    }

    return !previous.needsReverseProxy &&
        !next.needsReverseProxy &&
        !previous.isReversed &&
        !next.isReversed &&
        !previous.hasPreparedProxy &&
        !next.hasPreparedProxy &&
        previous.sourceVideoPath == next.sourceVideoPath &&
        previous.playbackVideoPath == next.playbackVideoPath &&
        (previous.sourceEnd - next.sourceStart).abs() <= epsilon &&
        (previous.timelineEnd - next.timelineStart).abs() <= epsilon &&
        (previous.speed - next.speed).abs() <= epsilon &&
        (previous.volume.baseValue - next.volume.baseValue).abs() <= epsilon;
  }

  bool _sameMatrix(List<double>? a, List<double>? b) {
    if (a == null || b == null) return a == null && b == null;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 1e-6) return false;
    }
    return true;
  }

  EditorTimelineVideoClip _composeVideoClip(
    VideoSegment segment, {
    required String sourceVideoPath,
    required bool isImage,
    required Size sourceSize,
    required double timelineStart,
    required double timelineEnd,
    required int laneIndex,
    required double? resolvedTransitionDuration,
  }) {
    final overrideVideoPath = segment.overrideVideoPath;
    final hasPreparedProxy =
        overrideVideoPath != null && overrideVideoPath.isNotEmpty;

    return EditorTimelineVideoClip(
      id: segment.id,
      isImage: isImage,
      sourceWidth: sourceSize.width,
      sourceHeight: sourceSize.height,
      sourceVideoPath: sourceVideoPath,
      playbackVideoPath: hasPreparedProxy ? overrideVideoPath : sourceVideoPath,
      sourceStart: segment.sourceStart,
      sourceEnd: segment.sourceEnd,
      timelineStart: timelineStart,
      timelineEnd: timelineEnd,
      speed: segment.speed,
      volume: segment.volume,
      laneIndex: laneIndex,
      // Report the resolved duration, not the raw request, so every consumer
      // sees the same clamped value.
      transitionType: resolvedTransitionDuration == null
          ? null
          : segment.transitionType,
      transitionDuration: resolvedTransitionDuration,
      isReversed: segment.isReversed,
      hasPreparedProxy: hasPreparedProxy,
      overrideVideoPath: segment.overrideVideoPath,
      // Graded before the shader blends this clip with its neighbour, so two
      // clips with different filters cross-fade between their looks.
      colorMatrix: segment.filterMatrix,
      // The effect is a separate thing applied at a separate moment — the
      // grade runs per lane before the blend, the effect whole-frame after
      // compositing — so it sits *beside* the matrix and never replaces it.
      // It was once added in its place, and every clip silently lost its
      // filter.
      //
      // Resolved through the catalog, not copied raw: an id this build does
      // not know (a newer draft, an unmigrated rename) must reach the renderer
      // as "no effect" rather than as a name it has no shader for. The draft
      // keeps the original string either way.
      effectId: segment.effect?.id,
      effectIntensity: segment.effectIntensity,
      // The window the effect's progress is measured across, read from the
      // catalog at compose time rather than stored on the segment: an intro's
      // length is a property of the effect, so retuning it must reach every
      // saved project without a draft migration. Null for a static look, which
      // is every effect that existed before the clock.
      effectIntroSeconds: segment.effect?.introSeconds,
      canvasScale: segment.canvasScale,
      canvasOffsetX: segment.canvasOffsetX,
      canvasOffsetY: segment.canvasOffsetY,
    );
  }

  EditorTimelineAudioClip _composeAudioClip(AudioTrackModel track) {
    return EditorTimelineAudioClip(
      id: track.id,
      filePath: track.filePath,
      sourceStart: track.sourceStart,
      sourceEnd: track.sourceEnd,
      timelineStart: track.timelineStart,
      timelineEnd: track.timelineEnd,
      volume: track.volume,
      laneIndex: track.laneIndex,
    );
  }

  /// Where the project actually ends: the last video frame, or the end of
  /// whatever audio or overlay outlasts it.
  ///
  /// The preview's ticker tail and the export both run to this instant over
  /// the bare project background, so it must agree with
  /// `totalEditedDurationProvider` — a consumer that stopped at the video's
  /// end would cut a long music track off mid-note.
  double _projectEndSeconds(double videoDuration, VideoEditorState state) {
    var end = videoDuration;
    for (final track in state.audioTracks) {
      if (track.timelineEnd > end) {
        end = track.timelineEnd;
      }
    }
    for (final text in state.textOverlays) {
      final t = text.endTime.inMilliseconds / 1000.0;
      if (t > end) {
        end = t;
      }
    }
    for (final image in state.imageOverlays) {
      final t = image.endTime.inMilliseconds / 1000.0;
      if (t > end) {
        end = t;
      }
    }
    for (final video in state.videoOverlays) {
      final t = video.timelineEnd.inMilliseconds / 1000.0;
      if (t > end) {
        end = t;
      }
    }
    return end;
  }
}
