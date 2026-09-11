import 'package:flutter/material.dart';

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
    this.isImage = false,
    this.sourceWidth = 0,
    this.sourceHeight = 0,
    this.laneIndex = 0,
    this.transitionType,
    this.transitionDuration,
    this.overrideVideoPath,
    this.colorMatrix,
    this.canvasScale = 1.0,
    this.canvasOffsetX = 0.0,
    this.canvasOffsetY = 0.0,
  });

  final String id;
  final String sourceVideoPath;
  final String playbackVideoPath;
  final double sourceStart;
  final double sourceEnd;
  final double timelineStart;
  final double timelineEnd;
  final double speed;
  final double volume;
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

  /// The user's pinch scale on top of the contain fit (1.0 = plain fit), and
  /// where the clip's centre is dragged to, in canvas fractions.
  final double canvasScale;
  final double canvasOffsetX;
  final double canvasOffsetY;

  double get timelineDuration => timelineEnd - timelineStart;

  bool get needsReverseProxy {
    return isReversed && !hasPreparedProxy;
  }

  /// Source position that corresponds to [timelineSeconds] within this clip.
  ///
  /// Both clips in a transition derive their source position from the one
  /// shared timeline clock through this, which is what keeps them in step.
  double sourceAt(double timelineSeconds) {
    final offset = (timelineSeconds - timelineStart) * speed;
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
      'volume': volume,
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
      'canvasScale': canvasScale,
      'canvasOffsetX': canvasOffsetX,
      'canvasOffsetY': canvasOffsetY,
    };
  }
}

/// A photo or video laid over the timeline.
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
    this.animationInSeconds = 0.5,
    this.animationOutSeconds = 0.5,
    this.sourceStart = 0,
    this.sourceEnd = 0,
    this.volume = 1.0,
    this.isMuted = false,
  });

  final String id;

  /// `image` or `video`.
  final String kind;

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
  final double animationInSeconds;
  final double animationOutSeconds;

  /// Video overlays only: the range of the source to play, and its audio.
  final double sourceStart;
  final double sourceEnd;
  final double volume;
  final bool isMuted;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'kind': kind,
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
      'animationInSeconds': animationInSeconds,
      'animationOutSeconds': animationOutSeconds,
      'sourceStart': sourceStart,
      'sourceEnd': sourceEnd,
      'volume': volume,
      'isMuted': isMuted,
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
