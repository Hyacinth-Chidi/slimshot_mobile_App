import 'package:flutter/material.dart';

import '../logic/animation/animatable_double.dart';
import '../logic/mask/clip_mask.dart';
import '../logic/speed/speed_curve.dart';
import '../logic/chroma/chroma_key.dart';

/// A resolved editor timeline, ready to hand to the native preview engine.
///
/// Two views of the same edit are carried deliberately:
///
/// * [videoClips] is the *edit* truth. Clips keep their full source ranges, and
///   a clip joined by a transition **overlaps** its neighbour in timeline time
///   by the transition duration. This matches FFmpeg `xfade` semantics exactly,
///   so preview and export agree on the total duration.
/// * [playbackClips] is what a single decoder walks: the same clips with each
///   outgoing transition side truncated so the ranges never overlap. The
///   renderer composites the transition on top using [transitions].
class EditorTimeline {
  const EditorTimeline({
    required this.sourceVideoPath,
    required this.sourceDurationSeconds,
    required this.durationSeconds,
    required this.canvas,
    required this.videoClips,
    required this.playbackClips,
    required this.transitions,
    required this.audioClips,
    this.overlays = const [],
    this.isMuted = false,
  });

  final String sourceVideoPath;
  final double sourceDurationSeconds;
  final double durationSeconds;
  final EditorTimelineCanvas canvas;
  final List<EditorTimelineVideoClip> videoClips;
  final List<EditorTimelineVideoClip> playbackClips;
  final List<EditorTimelineTransition> transitions;
  final List<EditorTimelineAudioClip> audioClips;

  /// Photo and video overlays, sorted so lower lanes paint first.
  final List<EditorTimelineOverlay> overlays;

  /// Whether the project's own audio is silenced.
  ///
  /// Belongs on the timeline rather than being applied clip by clip, because it
  /// is one switch over the whole edit — and export has to see it, or a muted
  /// project would export with its sound back.
  final bool isMuted;

  bool get needsReverseProxy {
    return videoClips.any((clip) => clip.needsReverseProxy);
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': 2,
      'sourceVideoPath': sourceVideoPath,
      'sourceDurationSeconds': sourceDurationSeconds,
      'durationSeconds': durationSeconds,
      'backgroundColor': canvas.backgroundColor.value,
      'canvas': canvas.toJson(),
      'segments': videoClips.map((clip) => clip.toJson()).toList(),
      'videoClips': videoClips.map((clip) => clip.toJson()).toList(),
      'playbackClips': playbackClips.map((clip) => clip.toJson()).toList(),
      'transitions':
          transitions.map((transition) => transition.toJson()).toList(),
      'audioTracks': audioClips.map((clip) => clip.toJson()).toList(),
      'overlays': overlays.map((overlay) => overlay.toJson()).toList(),
      'needsReverseProxy': needsReverseProxy,
      'isMuted': isMuted,
    };
  }
}

/// A resolved transition window on the timeline.
///
/// The window is where the two clips overlap: it starts when the incoming clip
/// begins and ends when the outgoing clip would have ended. The native renderer
/// consumes these directly — it must never recompute the window from clip
/// boundaries, because the clip list it receives is already truncated for
/// playback.
class EditorTimelineTransition {
  const EditorTimelineTransition({
    required this.leftClipId,
    required this.rightClipId,
    required this.leftClipIndex,
    required this.rightClipIndex,
    required this.type,
    required this.durationSeconds,
    required this.timelineStartSeconds,
    required this.timelineEndSeconds,
  });

  final String leftClipId;
  final String rightClipId;
  final int leftClipIndex;
  final int rightClipIndex;

  /// Persisted transition identifier, matching `EditorTransition.name`.
  final String type;

  final double durationSeconds;
  final double timelineStartSeconds;
  final double timelineEndSeconds;

  Map<String, dynamic> toJson() {
    return {
      'leftClipId': leftClipId,
      'rightClipId': rightClipId,
      'leftClipIndex': leftClipIndex,
      'rightClipIndex': rightClipIndex,
      'type': type,
      'durationSeconds': durationSeconds,
      'timelineStartSeconds': timelineStartSeconds,
      'timelineEndSeconds': timelineEndSeconds,
    };
  }
}

class EditorTimelineCanvas {
  const EditorTimelineCanvas({
    required this.backgroundColor,
    required this.backgroundType,
    required this.backgroundBlurIntensity,
    this.backgroundImagePath,
    required this.cropRatio,
    required this.customCropRect,
    required this.videoScale,
    required this.videoPan,
    this.aspectRatio = 0,
    this.width = 0,
    this.height = 0,
    this.contentRect = const Rect.fromLTWH(0, 0, 1, 1),
    this.colorMatrix,
  });

  /// The portion of each clip's frame that reaches the canvas, in normalised
  /// source coordinates, with crop, zoom and pan already resolved into it.
  ///
  /// Full-frame `(0, 0, 1, 1)` means no cropping.
  /// The **project's** sampling rect — crop, zoom and pan with no clip's own
  /// crop folded in. Kept on the contract for the Flutter side; **the engine
  /// samples through each clip's own `contentRect`**, not this.
  final Rect contentRect;

  /// 4×5 colour matrix for the selected filter, row-major, in Flutter's
  /// `ColorFilter.matrix` layout — 20 values, offsets on a 0–255 scale.
  /// Null when no filter is applied.
  final List<double>? colorMatrix;

  /// Pixel size of the output frame. The native preview renders a texture of
  /// exactly this shape; clips are fitted into it.
  final double width;
  final double height;

  /// Shape of the output frame, taken from the tallest imported clip.
  ///
  /// Clips that do not match are fitted inside it, leaving background-filled
  /// bars rather than being stretched. Zero means unresolved, in which case the
  /// renderer falls back to filling the frame.
  final double aspectRatio;

  final Color backgroundColor;
  final String backgroundType;
  final double backgroundBlurIntensity;

  /// The background photo's path when [backgroundType] is `image`, else null
  /// and **absent from the JSON** — a build that predates the photo reads the
  /// payload it always did. The engine decodes it and samples it wherever it
  /// used to paint the colour.
  final String? backgroundImagePath;
  final String cropRatio;
  final Rect customCropRect;
  final double videoScale;
  final Offset videoPan;

  Map<String, dynamic> toJson() {
    return {
      'backgroundColor': backgroundColor.value,
      'aspectRatio': aspectRatio,
      'width': width,
      'height': height,
      'contentRect': {
        'left': contentRect.left,
        'top': contentRect.top,
        'width': contentRect.width,
        'height': contentRect.height,
      },
      'colorMatrix': colorMatrix,
      'backgroundType': backgroundType,
      'backgroundBlurIntensity': backgroundBlurIntensity,
      if (backgroundImagePath != null) 'backgroundImagePath': backgroundImagePath,
      'cropRatio': cropRatio,
      'customCropRect': {
        'left': customCropRect.left,
        'top': customCropRect.top,
        'width': customCropRect.width,
        'height': customCropRect.height,
      },
      'videoScale': videoScale,
      'videoPan': {
        'dx': videoPan.dx,
        'dy': videoPan.dy,
      },
    };
  }
}

class EditorTimelineVideoClip {
  const EditorTimelineVideoClip({
    required this.id,
    required this.sourceVideoPath,
    required this.playbackVideoPath,
    required this.sourceStart,
    required this.sourceEnd,
    required this.timelineStart,
    required this.timelineEnd,
    required this.speed,
    required this.volume,
    required this.isReversed,
    required this.hasPreparedProxy,
    this.speedCurve,
    this.isImage = false,
    this.sourceWidth = 0,
    this.sourceHeight = 0,
    this.laneIndex = 0,
    this.transitionType,
    this.transitionDuration,
    this.overrideVideoPath,
    this.colorMatrix,
    this.effectId,
    this.effectIntensity = const AnimatableDouble(baseValue: 1.0),
    this.effectIntroSeconds,
    this.canvasScale = const AnimatableDouble(baseValue: 1.0),
    this.canvasOffsetX = const AnimatableDouble(baseValue: 0.0),
    this.canvasOffsetY = const AnimatableDouble(baseValue: 0.0),
    this.canvasRotation = const AnimatableDouble(baseValue: 0.0),
    this.contentRect = const Rect.fromLTWH(0, 0, 1, 1),
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.opacity = const AnimatableDouble(baseValue: 1.0),
    this.mask = ClipMask.none,
    this.chromaKey = ChromaKey.none,
  });

  final String id;
  final String sourceVideoPath;
  final String playbackVideoPath;
  final double sourceStart;
  final double sourceEnd;
  final double timelineStart;
  final double timelineEnd;
  final double speed;

  /// A ramping speed, or null for the flat [speed]. See
  /// `VideoSegment.speedCurve`; the engine resolves source position through
  /// it in [sourceAt] and its Kotlin twin.
  final SpeedCurve? speedCurve;

  /// This clip's own gain, and how it varies across the clip.
  ///
  /// Resolved per frame by whichever engine is drawing — [volumeAt] against
  /// [clipProgressAt] — never read flat, or a keyframed fade would play at one
  /// level.
  final AnimatableDouble volume;

  final bool isReversed;
  final bool hasPreparedProxy;

  /// A still photo rather than a video.
  ///
  /// The engine gives an image clip a duration instead of a source range, so
  /// it is shown for as long as the timeline asks rather than being clipped to
  /// a range the file does not have.
  final bool isImage;

  /// The clip's own frame size.
  ///
  /// Clips in one project can differ in shape, so the renderer fits each one
  /// into the project canvas rather than stretching it to fill. Zero means
  /// unknown, in which case the renderer fills the frame as before.
  final double sourceWidth;
  final double sourceHeight;

  /// Which decoder plays this clip.
  ///
  /// Two clips joined by a transition overlap in time, so they must be decoded
  /// by different players to both produce frames at once. Lanes alternate only
  /// across a transition; a run of plain cuts stays on one lane so it can be a
  /// single gapless playlist.
  final int laneIndex;

  final String? transitionType;
  final double? transitionDuration;
  final String? overrideVideoPath;

  /// This clip's own grade, as a 4×5 `ColorFilter.matrix` with offsets on a
  /// 0–255 scale, or null when the clip is ungraded.
  ///
  /// Applied to the clip *before* a transition blends it, so two clips carrying
  /// different looks cross-fade between those looks. The project-wide filter in
  /// [EditorTimelineCanvas.colorMatrix] is applied afterwards, once, to the
  /// finished frame.
  final List<double>? colorMatrix;

  /// The shader effect this clip is drawn through, as a catalog id, or null
  /// when the clip is unaffected.
  ///
  /// Already resolved against the catalog by the composer: an id this build
  /// does not know arrives here as null rather than as a string the renderer
  /// has no shader for. A clip's effect is applied per lane, like
  /// [colorMatrix], so two clips carrying different effects cross-fade between
  /// them rather than the blend being drawn through one of the two.
  final String? effectId;

  /// How strongly [effectId] is applied, **normalised 0..1, never pixels** —
  /// preview and export draw the same clip at different resolutions and a
  /// pixel parameter would give them different pictures.
  ///
  /// An [AnimatableDouble], so the strength may vary across the clip. **Both
  /// renderers resolve it themselves, per frame, against the same progress
  /// they already pass to the shader** — there is no second animation path and
  /// no new uniform. A parameter with no envelope and no keyframes resolves
  /// flat at every progress, which is byte for byte what the scalar did.
  ///
  /// Crosses the channel as [AnimatableDouble.toJson] writes it: a **bare
  /// number** while nothing animates it, a map of `baseValue` / `envelope` /
  /// `keyframes` once something does. Kotlin's `AnimatableDouble.fromWire`
  /// reads both shapes and falls back rather than throwing on anything else,
  /// so an older engine build still sees the number it expects.
  final AnimatableDouble effectIntensity;

  /// The window [effectId]'s animation plays across, in **seconds from this
  /// clip's first frame**, or null when the effect is a static look.
  ///
  /// Resolved by the composer from the catalog rather than stored on the clip:
  /// it is a property of the *effect*, not of the user's edit, so a retuned
  /// intro length reaches every existing project on the next compose instead of
  /// needing a draft migration. That also keeps the renderer from holding a
  /// second copy of the catalog — it is told the window and never has to know
  /// which ids are intros.
  ///
  /// Null means the shader receives progress across the whole clip and is
  /// expected to ignore it, which is every effect written before the clock
  /// existed.
  final double? effectIntroSeconds;

  /// The user's pinch scale on top of the contain fit (1.0 = plain fit), and
  /// where the clip's centre is dragged to, in canvas fractions.
  final AnimatableDouble canvasScale;
  final AnimatableDouble canvasOffsetX;
  final AnimatableDouble canvasOffsetY;

  /// Rotation about the clip's centre, in degrees. See `VideoSegment`.
  final AnimatableDouble canvasRotation;

  /// The part of **this clip's** source frame that reaches the canvas, as
  /// fractions — crop, zoom and pan already collapsed into one rectangle.
  ///
  /// **Per clip, not per canvas.** It used to be one rect on
  /// `EditorTimelineCanvas` that every lane sampled through, which made a
  /// per-clip crop impossible: two lanes blending through a transition had one
  /// rect and two answers. Now each lane samples through its own, mirroring
  /// what the fit and pan already do. A project with no per-clip crop composes
  /// the identical rect onto every clip, so nothing changes for it.
  final Rect contentRect;

  /// Mirrored across its own axes. See `VideoSegment.flipHorizontal`.
  final bool flipHorizontal;
  final bool flipVertical;

  /// How present the clip is, 0..1. See `VideoSegment.opacity`.
  final AnimatableDouble opacity;

  /// The window over the picture. See `VideoSegment.mask`.
  final ClipMask mask;

  /// The clip's chroma key. Resolved in the shader as a coverage that
  /// multiplies the clip's opacity, exactly as the mask does.
  final ChromaKey chromaKey;

  double get timelineDuration => timelineEnd - timelineStart;

  /// This clip's 0..1 position at a timeline instant.
  ///
  /// **Whole-clip, and the same for every keyframable property** — a diamond is
  /// one instant of the clip. Distinct from the effect clock, which runs over
  /// [effectIntroSeconds] when an effect declares one. A zero-length clip is 0,
  /// not a division by zero.
  double clipProgressAt(double timelineSeconds) {
    final d = timelineDuration;
    if (d <= 0) return 0.0;
    return ((timelineSeconds - timelineStart) / d).clamp(0.0, 1.0).toDouble();
  }

  double volumeAt(double progress) => volume.resolveAt(progress);
  double opacityAt(double progress) =>
      opacity.resolveAt(progress).clamp(0.0, 1.0).toDouble();
  double canvasScaleAt(double progress) => canvasScale.resolveAt(progress);
  double canvasOffsetXAt(double progress) => canvasOffsetX.resolveAt(progress);
  double canvasOffsetYAt(double progress) => canvasOffsetY.resolveAt(progress);
  double canvasRotationAt(double progress) => canvasRotation.resolveAt(progress);

  /// Whether this clip carries any keyframe at all, on any property.
  bool get hasKeyframes =>
      canvasScale.keyframes.isNotEmpty ||
      canvasOffsetX.keyframes.isNotEmpty ||
      canvasOffsetY.keyframes.isNotEmpty ||
      canvasRotation.keyframes.isNotEmpty ||
      volume.keyframes.isNotEmpty ||
      effectIntensity.keyframes.isNotEmpty ||
      opacity.keyframes.isNotEmpty;

  bool get needsReverseProxy {
    return isReversed && !hasPreparedProxy;
  }

  /// Source position that corresponds to [timelineSeconds] within this clip.
  ///
  /// Both clips in a transition derive their source position from the one
  /// shared timeline clock through this, which is what keeps them in step.
  double sourceAt(double timelineSeconds) {
    final curve = speedCurve;
    final into = timelineSeconds - timelineStart;
    final span = sourceEnd - sourceStart;
    final offset = curve == null || span <= 0
        ? into * speed
        : curve.sourceAtTime(into / span) * span;
    return (sourceStart + offset).clamp(sourceStart, sourceEnd).toDouble();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sourceVideoPath': sourceVideoPath,
      'playbackVideoPath': playbackVideoPath,
      'sourceStart': sourceStart,
      'sourceEnd': sourceEnd,
      'timelineStart': timelineStart,
      'timelineEnd': timelineEnd,
      'timelineDuration': timelineDuration,
      'speed': speed,
      // Only when set: an engine reading a flat clip sees the payload it
      // always did. Kotlin's `SpeedCurve.parse` reads the same shape.
      if (speedCurve != null) 'speedCurve': speedCurve!.toJson(),
      // A bare number while flat, a map once keyframed — so a clip nobody has
      // animated crosses the channel exactly as it always has, and Kotlin's
      // `AnimatableDouble.fromWire` reads either shape.
      'volume': volume.toJson(),
      'isReversed': isReversed,
      'hasPreparedProxy': hasPreparedProxy,
      'needsReverseProxy': needsReverseProxy,
      'isImage': isImage,
      'sourceWidth': sourceWidth,
      'sourceHeight': sourceHeight,
      'laneIndex': laneIndex,
      'transitionType': transitionType,
      'transitionDuration': transitionDuration,
      'overrideVideoPath': overrideVideoPath,
      'colorMatrix': colorMatrix,
      'effectId': effectId,
      // A bare number while flat, a map once animated — the shape
      // `AnimatableDouble.fromWire` reads on the Kotlin side.
      'effectIntensity': effectIntensity.toJson(),
      'effectIntroSeconds': effectIntroSeconds,
      'canvasScale': canvasScale.toJson(),
      'canvasOffsetX': canvasOffsetX.toJson(),
      'canvasOffsetY': canvasOffsetY.toJson(),
      'canvasRotation': canvasRotation.toJson(),
      'opacity': opacity.toJson(),
      if (!mask.isNone) 'mask': mask.toJson(),
      // Only when on: an engine reading an unkeyed clip sees the payload it
      // always did.
      if (!chromaKey.isNone) 'chromaKey': chromaKey.toJson(),
      // Only when set, so an older engine reads the payload it always did.
      if (flipHorizontal) 'flipHorizontal': true,
      if (flipVertical) 'flipVertical': true,
      // The same shape the canvas rect crosses in, so the Kotlin reader is one
      // helper for both.
      'contentRect': {
        'left': contentRect.left,
        'top': contentRect.top,
        'width': contentRect.width,
        'height': contentRect.height,
      },
    };
  }
}

/// One glyph of a `text` overlay: where its cell sits in the atlas, where it
/// is placed on the text box, and which part of the cell is real ink.
///
/// A glyph carries **three** rects, not two, because a padded cell and a
/// placed glyph are not the same rectangle:
///
/// - [atlasLeft]/[atlasTop]/[atlasRight]/[atlasBottom] (fractions of the
///   atlas) — the whole padded cell. The padding is real ink (shadow/stroke
///   bleed) and must be sampled, not cropped away.
/// - [boxLeft]/[boxTop]/[boxRight]/[boxBottom] (fractions of the text box) —
///   where the glyph is **placed**. These tile the box and never overlap,
///   unlike the padded cells, which do overlap their neighbours.
/// - [srcLeft]/[srcTop]/[srcRight]/[srcBottom] (fractions **of the cell**) —
///   which sub-rectangle of the cell maps onto the box rect; the bleed sits
///   outside it and is allowed to spill past the box rect's edges.
///
/// Placing by the padded rect instead of the box rect double-composites the
/// shared ink where two padded cells overlap — see Task 2's fix (C1) for the
/// measured effect. All twelve values are 0..1 fractions, never pixels, so
/// the renderer never inherits a device resolution.
class EditorTimelineGlyph {
  const EditorTimelineGlyph({
    required this.atlasLeft,
    required this.atlasTop,
    required this.atlasRight,
    required this.atlasBottom,
    required this.boxLeft,
    required this.boxTop,
    required this.boxRight,
    required this.boxBottom,
    required this.srcLeft,
    required this.srcTop,
    required this.srcRight,
    required this.srcBottom,
  });

  final double atlasLeft;
  final double atlasTop;
  final double atlasRight;
  final double atlasBottom;

  final double boxLeft;
  final double boxTop;
  final double boxRight;
  final double boxBottom;

  final double srcLeft;
  final double srcTop;
  final double srcRight;
  final double srcBottom;

  Map<String, dynamic> toJson() {
    return {
      'atlasLeft': atlasLeft,
      'atlasTop': atlasTop,
      'atlasRight': atlasRight,
      'atlasBottom': atlasBottom,
      'boxLeft': boxLeft,
      'boxTop': boxTop,
      'boxRight': boxRight,
      'boxBottom': boxBottom,
      'srcLeft': srcLeft,
      'srcTop': srcTop,
      'srcRight': srcRight,
      'srcBottom': srcBottom,
    };
  }
}

/// A photo, video, or text block laid over the timeline.
///
/// All geometry is **normalised to the canvas** — `0..1` fractions rather than
/// pixels. The editor stores overlay position and size in preview-canvas
/// pixels, which makes them depend on the device's screen size; normalising
/// here keeps that out of the renderer, so a project looks the same on any
/// screen and in the exported file.
///
/// The overlay is centred on ([centerX], [centerY]) and drawn to fit inside a
/// box of [boxWidth] × [boxHeight], preserving its own aspect ratio. Native
/// resolves the fit because only it knows the decoded media's true dimensions.
class EditorTimelineOverlay {
  const EditorTimelineOverlay({
    required this.id,
    required this.kind,
    required this.path,
    required this.centerX,
    required this.centerY,
    required this.boxWidth,
    required this.boxHeight,
    required this.scale,
    required this.rotation,
    required this.opacity,
    required this.startSeconds,
    required this.endSeconds,
    required this.laneIndex,
    required this.slideOffsetX,
    required this.slideOffsetY,
    this.animationIn,
    this.animationOut,
    this.animationLoop,
    this.animationInSeconds = 0.5,
    this.animationOutSeconds = 0.5,
    this.speedIn = 1.0,
    this.speedOut = 1.0,
    this.speedLoop = 1.0,
    this.sourceStart = 0,
    this.sourceEnd = 0,
    this.speed = 1.0,
    this.volume = 1.0,
    this.isMuted = false,
    this.glyphs,
    this.mask = ClipMask.none,
    this.chromaKey = ChromaKey.none,
    this.backgroundLeft = 0,
    this.backgroundTop = 0,
    this.backgroundRight = 0,
    this.backgroundBottom = 0,
    this.backgroundRadius = 0,
  });

  final String id;

  /// `image`, `video`, or `text`.
  final String kind;

  /// The shape this overlay is cut to, in its **own box**. See
  /// `ImageOverlayModel.mask`.
  final ClipMask mask;

  /// The colour keyed out of this overlay. See `ImageOverlayModel.chromaKey`.
  final ChromaKey chromaKey;

  final String path;

  final double centerX;
  final double centerY;
  final double boxWidth;
  final double boxHeight;
  final double scale;

  /// Radians, clockwise, about the overlay's centre.
  final double rotation;

  final double opacity;
  final double startSeconds;
  final double endSeconds;

  /// Draw order — higher lanes paint on top.
  final int laneIndex;

  /// How far a slide animation travels, normalised from the editor's fixed
  /// 200px so the motion covers the same fraction of frame on any screen.
  final double slideOffsetX;
  final double slideOffsetY;

  final String? animationIn;
  final String? animationOut;

  /// Text overlays only: an animation that repeats for the whole span. Image
  /// and video overlays have no loop slot, so null here is the ordinary case.
  final String? animationLoop;

  /// The in/out window lengths, in seconds.
  ///
  /// **Image and video overlays only.** Native times a *text* overlay's
  /// animations itself — `TextAnimationCurves.resolveDurations`, from the
  /// catalog's natural duration, the glyph count and [speedIn] — because a
  /// staggered animation's length depends on how many characters there are,
  /// which is a fact the renderer holds and the composer would have to
  /// duplicate. These two are left at their defaults on a text overlay and are
  /// not read for one.
  final double animationInSeconds;
  final double animationOutSeconds;

  /// Text overlays only: dimensionless speed multipliers that **divide** the
  /// catalog's natural durations. 1.0 is natural; higher is faster.
  ///
  /// A speed rather than a duration precisely because the duration is not the
  /// composer's to know — see [animationInSeconds]. Being dimensionless, they
  /// also carry no device pixel or canvas size across the boundary.
  ///
  /// [speedIn] and [speedOut] are expected to be **equal** — the animation tab
  /// is one Speed slider — and the Kotlin side resolves both windows from
  /// [speedIn], so that the proportional compression which fits them into a
  /// short span exists exactly once. [speedLoop] is independent: a cycle length
  /// is no part of that compression.
  final double speedIn;
  final double speedOut;
  final double speedLoop;

  /// Video overlays only: the range of the source to play, and its audio.
  final double sourceStart;
  final double sourceEnd;

  /// How fast a video overlay's footage runs, 1.0 being natural. The engine
  /// resolves which source frame is due through it.
  final double speed;
  final double volume;
  final bool isMuted;

  /// Text overlays only: one entry per drawn character. A `text` overlay with
  /// no glyphs is drawn as a plain image, which is the fallback path.
  final List<EditorTimelineGlyph>? glyphs;

  /// Text overlays only: the background box, in text-box fractions, and its
  /// corner radius as a fraction of the box width. Drawn as one quad behind
  /// the glyphs — slicing it per glyph would make it move with the letters.
  final double backgroundLeft;
  final double backgroundTop;
  final double backgroundRight;
  final double backgroundBottom;
  final double backgroundRadius;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'kind': kind,
      // Only when set: an engine reading an unmasked overlay sees the payload
      // it always did.
      if (!mask.isNone) 'mask': mask.toJson(),
      // Same rule as the mask: only when set, so an unkeyed overlay is the
      // payload every build has always read.
      if (!chromaKey.isNone) 'chromaKey': chromaKey.toJson(),
      'path': path,
      'centerX': centerX,
      'centerY': centerY,
      'boxWidth': boxWidth,
      'boxHeight': boxHeight,
      'scale': scale,
      'rotation': rotation,
      'opacity': opacity,
      'startSeconds': startSeconds,
      'endSeconds': endSeconds,
      'laneIndex': laneIndex,
      'slideOffsetX': slideOffsetX,
      'slideOffsetY': slideOffsetY,
      'animationIn': animationIn,
      'animationOut': animationOut,
      'animationLoop': animationLoop,
      'animationInSeconds': animationInSeconds,
      'animationOutSeconds': animationOutSeconds,
      'speedIn': speedIn,
      'speedOut': speedOut,
      'speedLoop': speedLoop,
      'sourceStart': sourceStart,
      'sourceEnd': sourceEnd,
      // Video overlays only; the engine resolves which frame is due through it.
      'speed': speed,
      'volume': volume,
      'isMuted': isMuted,
      'glyphs': glyphs?.map((glyph) => glyph.toJson()).toList(),
      'backgroundLeft': backgroundLeft,
      'backgroundTop': backgroundTop,
      'backgroundRight': backgroundRight,
      'backgroundBottom': backgroundBottom,
      'backgroundRadius': backgroundRadius,
    };
  }
}

class EditorTimelineAudioClip {
  const EditorTimelineAudioClip({
    required this.id,
    required this.filePath,
    required this.sourceStart,
    required this.sourceEnd,
    required this.timelineStart,
    required this.timelineEnd,
    required this.volume,
    required this.laneIndex,
  });

  final String id;
  final String filePath;
  final double sourceStart;
  final double sourceEnd;
  final double timelineStart;
  final double timelineEnd;
  final double volume;
  final int laneIndex;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'filePath': filePath,
      'sourceStart': sourceStart,
      'sourceEnd': sourceEnd,
      'timelineStart': timelineStart,
      'timelineEnd': timelineEnd,
      'volume': volume,
      'laneIndex': laneIndex,
    };
  }
}
