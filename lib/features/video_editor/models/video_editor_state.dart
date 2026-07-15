import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'filter_preset.dart';
import 'image_overlay_model.dart';
import 'text_overlay_model.dart';
import 'video_overlay_model.dart';
import 'video_segment.dart';
import 'audio_track_model.dart';

enum EditorCropRatio {
  custom(null, 'Custom'),
  ratio9x16(9 / 16, '9:16'),
  ratio16x9(16 / 9, '16:9'),
  ratio1x1(1 / 1, '1:1'),
  ratio4x3(4 / 3, '4:3');

  final double? ratio;
  final String label;
  const EditorCropRatio(this.ratio, this.label);
}

enum EditorBackgroundType { black, color }

class VideoEditorState {
  const VideoEditorState({
    this.draftId,
    this.thumbnailPath,
    this.sourceVideo,
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
    this.selectedRatio = EditorCropRatio.custom,
    this.customCropRect = const Rect.fromLTWH(0, 0, 1, 1),
    this.videoScale = 1.0,
    this.videoPan = Offset.zero,
    this.previewVideoScale,
    this.previewVideoPan,
    this.selectedFilter,
    this.filterIntensity = 1.0,
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
  });

  final String? draftId;
  final String? thumbnailPath;
  final XFile? sourceVideo;
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

  VideoEditorState copyWith({
    String? draftId,
    String? thumbnailPath,
    XFile? sourceVideo,
    bool clearSourceVideo = false,
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
  }) {
    return VideoEditorState(
      draftId: draftId ?? this.draftId,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      sourceVideo: clearSourceVideo ? null : sourceVideo ?? this.sourceVideo,
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
    );
  }
}
