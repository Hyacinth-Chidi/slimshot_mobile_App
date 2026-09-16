import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../logic/animation/animatable_double.dart';
import '../logic/animation/clip_keyframes.dart';
import '../logic/timeline/timeline_geometry.dart';
import 'filter_preset.dart';
import 'media_asset.dart';
import 'image_overlay_model.dart';
import 'text_overlay_model.dart';
import 'video_overlay_model.dart';
import 'video_segment.dart';
import 'audio_track_model.dart';
import '../logic/color/color_adjustments.dart';

/// How far outside a clip's timeline span the playhead may sit and still count
/// as on it — float slack for positions that arrive as event doubles, not a
/// tolerance anyone should feel.
const double kOnClipToleranceSeconds = 1e-6;

/// Declaration order is display order in the crop panel: the 9:16 default
/// leads and freeform Custom sits last. Persistence is by [Enum.name], so
/// reordering is safe; renaming a value needs a draft migration.
enum EditorCropRatio {
  ratio9x16(9 / 16, '9:16'),
  ratio16x9(16 / 9, '16:9'),
  ratio1x1(1 / 1, '1:1'),
  ratio4x3(4 / 3, '4:3'),
  custom(null, 'Custom');

  final double? ratio;
  final String label;
  const EditorCropRatio(this.ratio, this.label);
}

/// What fills the letterbox. `black` predates the picker (a draft's implicit
/// default); `color` is a chosen tile; `image` is a photo at
/// [VideoEditorState.backgroundImagePath], cover-fitted by the engine.
enum EditorBackgroundType { black, color, image }

/// How close the playhead must be to a diamond to count as sitting on it.
///
/// **Seconds, not progress.** The same progress tolerance is a different number
/// of frames on a 1s clip and a 30s one, so a fixed progress window would make
/// diamonds unhittable on long clips and impossible to step off on short ones.
///
/// 0.05s is about a frame and a half at 30fps: tight enough that two diamonds a
/// user placed deliberately stay distinct, loose enough that a playhead parked
/// by tapping a diamond lands on it.
const double kKeyframeHitSeconds = 0.05;

/// [kKeyframeHitSeconds] expressed as progress on this clip.
///
/// Capped at half the clip so a very short one cannot make every point on it
/// "on" every diamond, and a zero-length clip answers 1.0 rather than dividing
/// by zero.
double keyframeHitToleranceFor(VideoSegment segment) {
  final d = segment.duration;
  if (d <= 0) return 1.0;
  return (kKeyframeHitSeconds / d).clamp(0.0, 0.5).toDouble();
}

class VideoEditorState {
  const VideoEditorState({
    this.draftId,
    this.thumbnailPath,
    this.assets = const [],
    this.trimRange = const RangeValues(0, 0),
    this.segments = const [],
    this.canUndo = false,
    this.canRedo = false,
    this.selectedSegmentId,
    this.durationSeconds = 0,
    this.isMuted = false,
    this.isPlaying = false,
    this.isExporting = false,
    this.currentMenuId = 'root',
    this.isClipSelected = false,
    this.activeToolId,
    this.previewVolume,
    this.previewSpeed,
    // 9:16 is the publishing format (reels/TikTok) and the shape the canvas
    // renders anyway; defaulting to Custom routed exports through the
    // crop-rect geometry, which distorted them.
    this.selectedRatio = EditorCropRatio.ratio9x16,
    this.customCropRect = const Rect.fromLTWH(0, 0, 1, 1),
    this.videoScale = 1.0,
    this.videoPan = Offset.zero,
    this.previewVideoScale,
    this.previewVideoPan,
    this.selectedFilter,
    this.filterIntensity = 1.0,
    this.filterAppliesToAll = true,
    this.transitionAppliesToAll = false,
    this.isClipTransformActive = false,
    this.activeFilterCategory = 'Trending',
    this.filterThumbnail,
    this.textOverlays = const [],
    this.selectedTextId,
    this.imageOverlays = const [],
    this.selectedImageId,
    this.videoOverlays = const [],
    this.selectedVideoOverlayId,
    this.audioTracks = const [],
    this.selectedAudioId,
    this.currentPlaybackPosition = 0.0,
    this.backgroundType = EditorBackgroundType.black,
    this.backgroundColor = Colors.black,
    this.backgroundBlurIntensity = 20.0,
    this.backgroundImagePath,
    this.adjustments = ColorAdjustments.none,
    this.selectedTransitionSegmentId,
  });

  final String? draftId;
  final String? thumbnailPath;

  /// Every imported file in the project, in import order.
  final List<MediaAsset> assets;

  final RangeValues trimRange;
  final List<VideoSegment> segments;
  final bool canUndo;
  final bool canRedo;
  final String? selectedSegmentId;
  final double durationSeconds;
  final bool isMuted;
  final bool isPlaying;
  final bool isExporting;
  final String currentMenuId;
  final bool isClipSelected;
  final String? activeToolId;
  final double? previewVolume;
  final double? previewSpeed;
  final EditorCropRatio selectedRatio;
  final Rect customCropRect;
  final double videoScale;
  final Offset videoPan;
  final double? previewVideoScale;
  final Offset? previewVideoPan;
  final FilterPreset? selectedFilter;
  final double filterIntensity;

  /// Whether the filter sheet grades the whole project or just the selected
  /// clip.
  ///
  /// On (the default) the filter is one grade applied to the finished frame,
  /// which is how the editor behaved before clips could carry their own. Off,
  /// the filter belongs to the selected clip and is applied before a transition
  /// blends it. The two are kept mutually exclusive so nothing is graded twice.
  final bool filterAppliesToAll;

  /// Whether choosing a transition applies it to every cut or only the
  /// selected one.
  final bool transitionAppliesToAll;

  /// True while a pinch/drag on the canvas is repositioning the selected clip.
  ///
  /// Transient — never serialised. The editor skips pushing full timelines to
  /// the engine while this is set (the gesture updates the engine through its
  /// own lightweight channel) and catches up once on release, the same
  /// arrangement trimming uses.
  final bool isClipTransformActive;
  final String activeFilterCategory;
  final Uint8List? filterThumbnail;
  final List<TextOverlayModel> textOverlays;
  final String? selectedTextId;
  final List<ImageOverlayModel> imageOverlays;
  final String? selectedImageId;
  final List<VideoOverlayModel> videoOverlays;
  final String? selectedVideoOverlayId;
  final List<AudioTrackModel> audioTracks;
  final String? selectedAudioId;
  final double currentPlaybackPosition;
  final EditorBackgroundType backgroundType;
  final Color backgroundColor;
  final double backgroundBlurIntensity;

  /// The project's own copy of a background photo, when one has been picked.
  ///
  /// Kept even while a colour is in use, so the photo tile keeps showing it and
  /// one tap brings it back without another trip to the picker. Only read by
  /// the engine when [backgroundType] is [EditorBackgroundType.image].
  final String? backgroundImagePath;

  /// The project's brightness / contrast / saturation / temperature, composed
  /// into the canvas look after the project filter. Coexists with per-clip
  /// adjustments; see `logic/color/color_adjustments.dart`.
  final ColorAdjustments adjustments;
  final String? selectedTransitionSegmentId;

  /// The first imported file, as an [XFile].
  ///
  /// A project can hold many assets now; this exists for the places that only
  /// need *a* file — the draft cover, the editor title. Anything that renders,
  /// trims or exports a clip must resolve that clip's own asset through
  /// [assetFor] instead, or it will silently use the wrong file.
  XFile? get sourceVideo =>
      assets.isEmpty ? null : XFile(assets.first.path);

  MediaAsset? assetById(String id) {
    for (final asset in assets) {
      if (asset.id == id) return asset;
    }
    return null;
  }

  /// The clip the tool panels act on, or null if nothing is selected.
  VideoSegment? get selectedSegment {
    final id = selectedSegmentId;
    if (id == null) return null;
    for (final segment in segments) {
      if (segment.id == id) return segment;
    }
    return null;
  }

  /// Where the playhead sits inside the selected clip, 0..1, or null when
  /// nothing is selected or the playhead is outside it.
  ///
  /// **The one definition of "this instant of this clip".** The keyframe
  /// controls, the diamonds on the filmstrip and every gesture that captures a
  /// starting value all resolve through it, so they cannot disagree about which
  /// moment the user is looking at. Resolved through
  /// [segmentTimelineStarts] — the same geometry the filmstrip and playback use
  /// — so it stays right through trims, speed and transition overlaps.
  double? get selectedClipProgress {
    final segment = selectedSegment;
    if (segment == null) return null;
    final starts = segmentTimelineStarts(segments);
    final index = segments.indexWhere((s) => s.id == segment.id);
    if (index < 0 || index >= starts.length) return null;
    final start = starts[index];
    final position = currentPlaybackPosition;
    // **Null, never clamped**, when the playhead is on another clip. A clip
    // stays selected while the playhead moves onto its neighbour, and clamping
    // resolved that as progress 0 or 1 — so a plus tapped there pinned a
    // diamond at the edge of a clip the user was not looking at, and the
    // curve icon lit for a segment the playhead was nowhere near. The edges
    // themselves count as on the clip: a split parks the playhead exactly on
    // the seam, which is the right half's first instant.
    if (position < start - kOnClipToleranceSeconds ||
        position > start + segment.duration + kOnClipToleranceSeconds) {
      return null;
    }
    return segment.clipProgressAt(position, start);
  }

  /// The clip the keyframe controls act on: the selected one.
  ///
  /// Null with nothing selected, which is what takes the diamond button out of
  /// the playback bar — a keyframe belongs to a clip, and a control that is
  /// present but inert is a control that lies.
  ///
  /// **There is no "keyframe mode" and no editor to open.** The rejected design
  /// held a `keyframeEditorSegmentId` naming a clip whose row was showing;
  /// diamonds now live on the clip's own thumbnail and the controls act on
  /// whatever is selected, so there is no third state to keep in step.
  String? get keyframeClipId => isClipSelected ? selectedSegmentId : null;

  /// Every diamond on the selected clip, as clip-relative progresses.
  List<double> get selectedClipKeyframes {
    final segment = selectedSegment;
    if (segment == null) return const [];
    return keyframeProgresses(segment);
  }

  /// The diamond under the playhead, or null.
  ///
  /// **The selection is the playhead.** Nothing is stored: the diamond being
  /// acted on is simply the one the playhead is standing on, which is what lets
  /// the plus/minus flip, the easing sheet and the timeline agree about what
  /// "here" means without a third piece of state that could fall out of step.
  double? get playheadKeyframeProgress {
    final segment = selectedSegment;
    final progress = selectedClipProgress;
    if (segment == null || progress == null) return null;
    return keyframeProgressNear(
      segment,
      progress,
      keyframeHitToleranceFor(segment),
    );
  }

  bool get playheadIsOnKeyframe => playheadKeyframeProgress != null;

  /// Which segment's curve the curve control edits, or null when there is
  /// nothing to ease at the playhead.
  double? get keyframeCurveTargetProgress {
    final segment = selectedSegment;
    final progress = selectedClipProgress;
    if (segment == null || progress == null) return null;
    return keyframeCurveTarget(
      segment,
      progress,
      keyframeHitToleranceFor(segment),
    );
  }

  /// Whether the curve control does anything here.
  ///
  /// **False is a disabled icon, not a hidden one.** A control that vanishes
  /// and reappears is harder to find than one that dims; dimming also teaches
  /// what it needs — place a second diamond and it lights up.
  bool get canEditKeyframeCurve => keyframeCurveTargetProgress != null;

  /// The curve currently on the segment the playhead is inside, or
  /// [KeyframeInterpolation.linear] when there is none.
  ///
  /// Linear doubles as "None" in the sheet, which is honest: a segment with no
  /// curve chosen travels in a straight line.
  KeyframeInterpolation get keyframeCurve {
    final segment = selectedSegment;
    final target = keyframeCurveTargetProgress;
    if (segment == null || target == null) return KeyframeInterpolation.linear;
    for (final property in ClipProperty.values) {
      for (final k in clipParameter(segment, property).keyframes) {
        if ((k.progress - target).abs() <= kKeyframeMatchProgress) {
          return k.interpolation;
        }
      }
    }
    return KeyframeInterpolation.linear;
  }

  /// What a control editing [property] should **show**.
  ///
  /// **A control shows what its write will target**, which is the rule that
  /// makes the sliders honest. With no diamonds an edit writes the base, so the
  /// base is shown. With diamonds it writes the keyframe at the playhead, so
  /// the value *there* is shown.
  ///
  /// Getting this wrong is not cosmetic. A volume slider parked at the base's
  /// 1.0 on a clip whose keyframes had taken it down to 0.2 offers no way to
  /// drag *up* — the thumb is already at the top while the audio is quiet —
  /// which is exactly the device report this rule fixes.
  ///
  /// **An envelope is not a keyframe here.** It shapes the base, and the write
  /// still targets the base, so the base is what to show; a slider tracking an
  /// enveloped curve would wander while playing and write back one frame of it
  /// when grabbed.
  double clipEditValue(VideoSegment segment, ClipProperty property) {
    final param = clipParameter(segment, property);
    if (!segment.hasKeyframes) return param.baseValue;
    final progress = selectedClipProgress;
    if (progress == null) return param.baseValue;
    return param.resolveAt(progress);
  }

  /// The asset a clip is cut from.  /// The asset a clip is cut from.
  ///
  /// Falls back to the first asset so a draft written before clips carried an
  /// asset id still resolves to something playable.
  MediaAsset? assetFor(VideoSegment segment) {
    return assetById(segment.assetId) ?? (assets.isEmpty ? null : assets.first);
  }

  /// The project's crop, as fractions of every clip's source frame.
  ///
  /// The custom rect under the Custom ratio, else the whole frame. **Full while
  /// the crop tool is open**, because the preview then shows the whole frame
  /// with the rectangle drawn over it — cropping takes effect when the tool
  /// closes. The composer, the canvas shape and the clip-crop editor all read
  /// this one definition, so none of them can disagree about what "the project
  /// shows" is.
  Rect get projectCropRect {
    if (activeToolId == 'crop' || selectedRatio != EditorCropRatio.custom) {
      return kFullFrameRect;
    }
    if (customCropRect.width <= 0 || customCropRect.height <= 0) {
      return kFullFrameRect;
    }
    return customCropRect;
  }

  /// Shape of the output frame.
  ///
  /// [kDefaultCanvasAspectRatio] (9:16) unless the user has chosen a ratio in
  /// the crop tool. Every clip is fitted inside it and the leftover space is
  /// filled with the project background.
  ///
  /// **Under Custom, the canvas takes the crop's shape**: the default frame
  /// reshaped by the rect's own proportions. A clip's fit is computed from the
  /// shape of what it *shows* — its frame narrowed by the crop — so the canvas
  /// has to be shaped to match or every clip letterboxes against the wrong
  /// frame. The preview used to keep the texture at 9:16 and reshape only the
  /// Flutter box around it, which un-stretched the picture on screen while the
  /// export, which has no box to reshape, kept the stretched texture. One frame
  /// shape, read by both, is what makes the file match the canvas.
  ///
  /// It is deliberately **not** derived from the imported media. See
  /// [kDefaultCanvasAspectRatio] for why.
  double get projectAspectRatio {
    final ratio = selectedRatio.ratio;
    if (ratio != null) return ratio;
    final crop = projectCropRect;
    return kDefaultCanvasAspectRatio * (crop.width / crop.height);
  }

  /// Pixel size of the output frame.
  ///
  /// The native preview renders into a texture of exactly this shape, and
  /// clips are fitted into it. It has to be the **canvas** size, not any one
  /// clip's — sizing the texture to a clip makes every fit wrong as soon as
  /// another clip has a different shape.
  ///
  /// Depends only on the aspect ratio, so importing, removing or reordering
  /// media never resizes the texture.
  Size get projectCanvasSize {
    var height = kDefaultCanvasHeightPx;
    var width = height * projectAspectRatio;
    if (width <= 0 || height <= 0) return const Size(720, 1280);

    final longest = width > height ? width : height;
    if (longest > kMaxPreviewCanvasPx) {
      final scale = kMaxPreviewCanvasPx / longest;
      width *= scale;
      height *= scale;
    }

    // Even dimensions keep encoders and some GL drivers happy.
    return Size(
      (width / 2).round() * 2.0,
      (height / 2).round() * 2.0,
    );
  }

  VideoEditorState copyWith({
    String? draftId,
    String? thumbnailPath,
    List<MediaAsset>? assets,
    RangeValues? trimRange,
    List<VideoSegment>? segments,
    bool? canUndo,
    bool? canRedo,
    String? selectedSegmentId,
    bool clearSelectedSegmentId = false,
    double? durationSeconds,
    bool? isMuted,
    bool? isPlaying,
    bool? isExporting,
    String? currentMenuId,
    bool? isClipSelected,
    String? activeToolId,
    bool clearActiveToolId = false,
    double? previewVolume,
    bool clearPreviewVolume = false,
    double? previewSpeed,
    bool clearPreviewSpeed = false,
    EditorCropRatio? selectedRatio,
    Rect? customCropRect,
    double? videoScale,
    Offset? videoPan,
    double? previewVideoScale,
    bool clearPreviewVideoScale = false,
    Offset? previewVideoPan,
    bool clearPreviewVideoPan = false,
    FilterPreset? selectedFilter,
    bool clearSelectedFilter = false,
    double? filterIntensity,
    bool? filterAppliesToAll,
    bool? transitionAppliesToAll,
    bool? isClipTransformActive,
    String? activeFilterCategory,
    Uint8List? filterThumbnail,
    bool clearFilterThumbnail = false,
    List<TextOverlayModel>? textOverlays,
    String? selectedTextId,
    bool clearSelectedTextId = false,
    List<ImageOverlayModel>? imageOverlays,
    String? selectedImageId,
    bool clearSelectedImageId = false,
    List<VideoOverlayModel>? videoOverlays,
    String? selectedVideoOverlayId,
    bool clearSelectedVideoOverlayId = false,
    List<AudioTrackModel>? audioTracks,
    String? selectedAudioId,
    bool clearSelectedAudioId = false,
    double? currentPlaybackPosition,
    EditorBackgroundType? backgroundType,
    Color? backgroundColor,
    double? backgroundBlurIntensity,
    String? backgroundImagePath,
    bool clearBackgroundImagePath = false,
    ColorAdjustments? adjustments,
    String? selectedTransitionSegmentId,
    bool clearSelectedTransitionSegmentId = false,
  }) {
    return VideoEditorState(
      draftId: draftId ?? this.draftId,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      assets: assets ?? this.assets,
      trimRange: trimRange ?? this.trimRange,
      segments: segments ?? this.segments,
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
      selectedSegmentId: clearSelectedSegmentId
          ? null
          : selectedSegmentId ?? this.selectedSegmentId,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      isMuted: isMuted ?? this.isMuted,
      isPlaying: isPlaying ?? this.isPlaying,
      isExporting: isExporting ?? this.isExporting,
      currentMenuId: currentMenuId ?? this.currentMenuId,
      isClipSelected: isClipSelected ?? this.isClipSelected,
      activeToolId: clearActiveToolId ? null : activeToolId ?? this.activeToolId,
      previewVolume: clearPreviewVolume
          ? null
          : previewVolume ?? this.previewVolume,
      previewSpeed: clearPreviewSpeed ? null : previewSpeed ?? this.previewSpeed,
      selectedRatio: selectedRatio ?? this.selectedRatio,
      customCropRect: customCropRect ?? this.customCropRect,
      videoScale: videoScale ?? this.videoScale,
      videoPan: videoPan ?? this.videoPan,
      previewVideoScale: clearPreviewVideoScale
          ? null
          : previewVideoScale ?? this.previewVideoScale,
      previewVideoPan: clearPreviewVideoPan
          ? null
          : previewVideoPan ?? this.previewVideoPan,
      selectedFilter: clearSelectedFilter
          ? null
          : selectedFilter ?? this.selectedFilter,
      filterIntensity: filterIntensity ?? this.filterIntensity,
      filterAppliesToAll: filterAppliesToAll ?? this.filterAppliesToAll,
      transitionAppliesToAll:
          transitionAppliesToAll ?? this.transitionAppliesToAll,
      isClipTransformActive:
          isClipTransformActive ?? this.isClipTransformActive,
      activeFilterCategory: activeFilterCategory ?? this.activeFilterCategory,
      filterThumbnail: clearFilterThumbnail
          ? null
          : filterThumbnail ?? this.filterThumbnail,
      textOverlays: textOverlays ?? this.textOverlays,
      selectedTextId:
          clearSelectedTextId ? null : selectedTextId ?? this.selectedTextId,
      imageOverlays: imageOverlays ?? this.imageOverlays,
      selectedImageId:
          clearSelectedImageId ? null : selectedImageId ?? this.selectedImageId,
      videoOverlays: videoOverlays ?? this.videoOverlays,
      selectedVideoOverlayId:
          clearSelectedVideoOverlayId ? null : selectedVideoOverlayId ?? this.selectedVideoOverlayId,
      audioTracks: audioTracks ?? this.audioTracks,
      selectedAudioId:
          clearSelectedAudioId ? null : selectedAudioId ?? this.selectedAudioId,
      currentPlaybackPosition:
          currentPlaybackPosition ?? this.currentPlaybackPosition,
      backgroundType: backgroundType ?? this.backgroundType,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      backgroundBlurIntensity: backgroundBlurIntensity ?? this.backgroundBlurIntensity,
      backgroundImagePath: clearBackgroundImagePath
          ? null
          : backgroundImagePath ?? this.backgroundImagePath,
      adjustments: adjustments ?? this.adjustments,
      selectedTransitionSegmentId: clearSelectedTransitionSegmentId
          ? null
          : selectedTransitionSegmentId ?? this.selectedTransitionSegmentId,
    );
  }
}
