import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'filter_preset.dart';
import 'media_asset.dart';
import 'image_overlay_model.dart';
import 'text_overlay_model.dart';
import 'video_overlay_model.dart';
import 'video_segment.dart';
import 'audio_track_model.dart';

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

enum EditorBackgroundType { black, color }

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
    this.selectedTransitionSegmentId,
    this.keyframeEditorSegmentId,
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
  final String? selectedTransitionSegmentId;

  /// The clip whose keyframe row is open, or null — which is every project
  /// until someone asks for one.
  ///
  /// **A user who never taps "Keyframe" never sees a diamond**, and this field
  /// is the whole mechanism: the timeline builds no keyframe row at all unless
  /// it names the selected clip. A flag derived from "this parameter has
  /// keyframes" would be the same thing backwards — the row would have to
  /// exist before the first keyframe could be placed — and one derived from
  /// "an effect is applied" would put a diamond row under every clip of the
  /// casual user who tapped one tile and left.
  ///
  /// **Transient and never serialised**, like [isClipTransformActive]: it is
  /// which tool is open, not part of the edit. A draft that reopened with the
  /// row showing would be exactly the unbidden row the design rules out, for a
  /// user who may have placed nothing.
  ///
  /// Scoped to one clip rather than a bare bool so selecting a different clip
  /// closes it: the row draws one clip's parameter, and carrying it across a
  /// selection change would show the new clip a row it never asked for.
  final String? keyframeEditorSegmentId;

  /// Whether the keyframe row should be drawn for [segmentId].
  ///
  /// Both conditions matter and neither implies the other: the row belongs to
  /// the clip that opted in, and a clip with no effect has no parameter to
  /// keyframe — tapping None while the row is open must take the row with it
  /// rather than leave diamonds over a value nothing reads.
  bool showsKeyframeRowFor(String? segmentId) {
    if (segmentId == null || keyframeEditorSegmentId != segmentId) return false;
    for (final segment in segments) {
      if (segment.id == segmentId) return segment.effect != null;
    }
    return false;
  }

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

  /// The asset a clip is cut from.
  ///
  /// Falls back to the first asset so a draft written before clips carried an
  /// asset id still resolves to something playable.
  MediaAsset? assetFor(VideoSegment segment) {
    return assetById(segment.assetId) ?? (assets.isEmpty ? null : assets.first);
  }

  /// Shape of the output frame.
  ///
  /// [kDefaultCanvasAspectRatio] (9:16) unless the user has chosen a ratio in
  /// the crop tool. Every clip is fitted inside it and the leftover space is
  /// filled with the project background.
  ///
  /// It is deliberately **not** derived from the imported media. See
  /// [kDefaultCanvasAspectRatio] for why.
  double get projectAspectRatio {
    return selectedRatio.ratio ?? kDefaultCanvasAspectRatio;
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
    String? selectedTransitionSegmentId,
    bool clearSelectedTransitionSegmentId = false,
    String? keyframeEditorSegmentId,
    bool clearKeyframeEditorSegmentId = false,
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
      selectedTransitionSegmentId: clearSelectedTransitionSegmentId
          ? null
          : selectedTransitionSegmentId ?? this.selectedTransitionSegmentId,
      keyframeEditorSegmentId: clearKeyframeEditorSegmentId
          ? null
          : keyframeEditorSegmentId ?? this.keyframeEditorSegmentId,
    );
  }
}
