import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/models/draft_project.dart';
import '../../../core/services/draft_service.dart';
import '../logic/filter_presets.dart';
import '../models/filter_preset.dart';
import '../models/text_overlay_model.dart';
import '../models/image_overlay_model.dart';
import '../models/video_overlay_model.dart';
import '../models/audio_track_model.dart';
import '../models/video_editor_state.dart';
import '../models/video_segment.dart';
import '../services/video_editor_service.dart';

class _ResolvedExportGeometry {
  const _ResolvedExportGeometry({
    required this.cropRect,
    required this.aspectRatio,
  });

  final Rect? cropRect;
  final double? aspectRatio;
}

Rect _clampNormalizedRect(Rect rect) {
  final left = rect.left.clamp(0.0, 1.0).toDouble();
  final top = rect.top.clamp(0.0, 1.0).toDouble();
  final right = rect.right.clamp(left + 0.0001, 1.0).toDouble();
  final bottom = rect.bottom.clamp(top + 0.0001, 1.0).toDouble();
  return Rect.fromLTRB(left, top, right, bottom);
}

Rect _applyZoomPanToCropRect({
  required Rect baseRect,
  required double videoScale,
  required Offset videoPan,
  required Size previewCanvasSize,
}) {
  if (videoScale <= 1.0001 ||
      previewCanvasSize.width <= 0 ||
      previewCanvasSize.height <= 0) {
    return _clampNormalizedRect(baseRect);
  }

  final scale = videoScale.clamp(1.0, 5.0);
  final cropWidth = baseRect.width / scale;
  final cropHeight = baseRect.height / scale;
  final centerX =
      baseRect.center.dx -
      (videoPan.dx * baseRect.width) / (previewCanvasSize.width * scale);
  final centerY =
      baseRect.center.dy -
      (videoPan.dy * baseRect.height) / (previewCanvasSize.height * scale);

  final left = (centerX - cropWidth / 2)
      .clamp(baseRect.left, baseRect.right - cropWidth)
      .toDouble();
  final top = (centerY - cropHeight / 2)
      .clamp(baseRect.top, baseRect.bottom - cropHeight)
      .toDouble();

  return _clampNormalizedRect(Rect.fromLTWH(left, top, cropWidth, cropHeight));
}

bool _isNearlyFullFrame(Rect rect) {
  return rect.left.abs() < 0.0001 &&
      rect.top.abs() < 0.0001 &&
      (1.0 - rect.right).abs() < 0.0001 &&
      (1.0 - rect.bottom).abs() < 0.0001;
}

double? _cropAspectRatio(Rect? cropRect, Size originalVideoSize) {
  if (cropRect == null || originalVideoSize.height == 0 || cropRect.height <= 0) {
    return null;
  }

  return (cropRect.width * originalVideoSize.width) /
      (cropRect.height * originalVideoSize.height);
}

_ResolvedExportGeometry _resolveExportGeometry({
  required VideoEditorState editorState,
  required Size previewCanvasSize,
  required Size originalVideoSize,
}) {
  if (editorState.selectedRatio != EditorCropRatio.custom) {
    return _ResolvedExportGeometry(
      cropRect: null,
      aspectRatio: editorState.selectedRatio.ratio,
    );
  }

  final baseRect = _clampNormalizedRect(editorState.customCropRect);

  final finalRect = _applyZoomPanToCropRect(
    baseRect: baseRect,
    videoScale: editorState.videoScale,
    videoPan: editorState.videoPan,
    previewCanvasSize: previewCanvasSize,
  );
  final cropRect = _isNearlyFullFrame(finalRect) ? null : finalRect;

  return _ResolvedExportGeometry(
    cropRect: cropRect,
    aspectRatio: _cropAspectRatio(cropRect, originalVideoSize),
  );
}

class VideoEditorNotifier extends StateNotifier<VideoEditorState> {
  final VideoEditorService _editorService;
  final List<VideoEditorState> _undoStack = [];
  final List<VideoEditorState> _redoStack = [];

  VideoEditorNotifier(this._editorService) : super(const VideoEditorState());

  void reset() {
    _undoStack.clear();
    _redoStack.clear();
    state = const VideoEditorState();
  }

  Future<void> loadAndInitializeVideo({
    required XFile video,
    required double durationSeconds,
    String? draftId,
  }) async {
    final newDraftId = draftId ?? DateTime.now().millisecondsSinceEpoch.toString();
    
    state = state.copyWith(
      draftId: newDraftId,
      sourceVideo: video,
      durationSeconds: durationSeconds,
      trimRange: RangeValues(0, durationSeconds),
      segments: [
        VideoSegment(id: 'main', sourceStart: 0, sourceEnd: durationSeconds),
      ],
      clearSelectedSegmentId: true,
      isClipSelected: false,
      isPlaying: false,
      isExporting: false,
      isMuted: false,
      currentMenuId: 'root',
      clearActiveToolId: true,
      clearSelectedTransitionSegmentId: true,
      clearPreviewVolume: true,
      clearPreviewSpeed: true,
      selectedRatio: EditorCropRatio.custom,
      customCropRect: const Rect.fromLTWH(0, 0, 1, 1),
      videoScale: 1.0,
      videoPan: Offset.zero,
      clearPreviewVideoScale: true,
      clearPreviewVideoPan: true,
      clearSelectedFilter: true,
      filterIntensity: 1.0,
      activeFilterCategory: FilterPresets.categories.first,
      textOverlays: const [],
      clearSelectedTextId: true,
      videoOverlays: const [],
      clearSelectedVideoOverlayId: true
    );

    try {
      final thumbs = await _editorService.generateThumbnails(
        inputPath: video.path,
        durationSeconds: durationSeconds,
        count: 1, // Just grab 1 frame for the filter icons
      );
      if (thumbs.isNotEmpty) {
        state = state.copyWith(
          filterThumbnail: thumbs.first,
          clearFilterThumbnail: false,
        );
      }
    } catch (_) {
      // Handle error, maybe log it
    }
  }

  Future<Map<String, dynamic>> prepareAndExportVideo({
    required Size previewCanvasSize,
    required Size originalVideoSize,
  }) async {
    final video = state.sourceVideo;
    if (video == null || state.isExporting) {
      throw Exception("No video source or already exporting.");
    }

    if (state.trimRange.end <= state.trimRange.start) {
      throw Exception("Choose a valid trim range.");
    }

    state = state.copyWith(isExporting: true);

    final geometry = _resolveExportGeometry(
      editorState: state,
      previewCanvasSize: previewCanvasSize,
      originalVideoSize: originalVideoSize,
    );

    final renderId = 'export_${DateTime.now().microsecondsSinceEpoch}';

    return {
      'sourceVideo': File(video.path),
      'segments': state.segments,
      'muteAudio': state.isMuted,
      'targetAspectRatio': geometry.aspectRatio,
      'customCropRect': geometry.cropRect,
      'originalVideoSize': originalVideoSize,
      'previewCanvasSize': previewCanvasSize,
      'renderId': renderId,
      'colorFilterMatrix':
          state.selectedFilter?.getInterpolatedMatrix(state.filterIntensity),
      'textOverlays': state.textOverlays.isEmpty
          ? null
          : state.textOverlays,
      'imageOverlays': state.imageOverlays.isEmpty
          ? null
          : state.imageOverlays,
      'videoOverlays': state.videoOverlays.isEmpty
          ? null
          : state.videoOverlays,
      'audioTracks': state.audioTracks,
      'backgroundType': state.backgroundType,
      'backgroundColor': state.backgroundColor,
      'backgroundBlurIntensity': state.backgroundBlurIntensity,
    };
  }

  Future<void> saveDraft() async {
    if (state.sourceVideo == null || state.draftId == null) return;

    String? thumbnailPath = state.thumbnailPath;
    
    // Save thumbnail to app documents if we have bytes but no file yet
    if (thumbnailPath == null && state.filterThumbnail != null) {
      try {
        final docDir = await getApplicationDocumentsDirectory();
        final file = File('${docDir.path}/draft_thumb_${state.draftId}.jpg');
        await file.writeAsBytes(state.filterThumbnail!);
        thumbnailPath = file.path;
        state = state.copyWith(thumbnailPath: thumbnailPath);
      } catch (_) {}
    }

    try {
      final draft = DraftProject(
        id: state.draftId!,
        sourceVideoPath: state.sourceVideo!.path,
        createdAt: DateTime.now(), // Real creation time would need to be tracked, but this is fine for updating
        updatedAt: DateTime.now(),
        durationSeconds: state.durationSeconds,
        thumbnailPath: thumbnailPath,
        segments: state.segments.map((e) => e.toJson()).toList(),
        textOverlays: state.textOverlays.map((e) => e.toJson()).toList(),
        imageOverlays: state.imageOverlays.map((e) => e.toJson()).toList(),
        videoOverlays: state.videoOverlays.map((e) => e.toJson()).toList(),
        audioTracks: state.audioTracks.map((e) => e.toJson()).toList(),
        selectedRatioName: state.selectedRatio.name,
        customCropRect: [
          state.customCropRect.left,
          state.customCropRect.top,
          state.customCropRect.width,
          state.customCropRect.height,
        ],
        videoScale: state.videoScale,
        videoPanX: state.videoPan.dx,
        videoPanY: state.videoPan.dy,
        filterName: state.selectedFilter?.name,
        filterIntensity: state.filterIntensity,
        backgroundType: state.backgroundType.name,
        backgroundColorValue: state.backgroundColor.value,
        backgroundBlurIntensity: state.backgroundBlurIntensity,
        isMuted: state.isMuted,
      );

      print('DEBUG: Calling DraftService.saveDraft');
      await DraftService.saveDraft(draft);
      print('DEBUG: Draft saved successfully');
    } catch (e, stack) {
      print('DEBUG: Error saving draft: $e');
      print(stack);
    }
  }

  Future<void> loadDraft(DraftProject draft) async {
    final video = XFile(draft.sourceVideoPath);
    
    state = state.copyWith(
      draftId: draft.id,
      thumbnailPath: draft.thumbnailPath,
      sourceVideo: video,
      durationSeconds: draft.durationSeconds,
      trimRange: RangeValues(0, draft.durationSeconds), // Will be updated if segments exist
      segments: draft.segments.map((e) => VideoSegment.fromJson(e)).toList(),
      textOverlays: draft.textOverlays.map((e) => TextOverlayModel.fromJson(e)).toList(),
      imageOverlays: draft.imageOverlays.map((e) => ImageOverlayModel.fromJson(e)).toList(),
      videoOverlays: draft.videoOverlays.map((e) => VideoOverlayModel.fromJson(e)).toList(),
      audioTracks: draft.audioTracks.map((e) => AudioTrackModel.fromJson(e)).toList(),
      selectedRatio: EditorCropRatio.values.firstWhere(
        (e) => e.name == draft.selectedRatioName,
        orElse: () => EditorCropRatio.custom,
      ),
      customCropRect: draft.customCropRect.length == 4
          ? Rect.fromLTWH(
              draft.customCropRect[0],
              draft.customCropRect[1],
              draft.customCropRect[2],
              draft.customCropRect[3],
            )
          : const Rect.fromLTWH(0, 0, 1, 1),
      videoScale: draft.videoScale,
      videoPan: Offset(draft.videoPanX, draft.videoPanY),
      selectedFilter: draft.filterName != null
          ? FilterPresets.allPresets.firstWhere(
              (f) => f.name == draft.filterName,
              orElse: () => FilterPresets.allPresets.first,
            )
          : null,
      clearSelectedFilter: draft.filterName == null,
      filterIntensity: draft.filterIntensity,
      backgroundType: EditorBackgroundType.values.firstWhere(
        (e) => e.name == draft.backgroundType,
        orElse: () => EditorBackgroundType.black,
      ),
      backgroundColor: Color(draft.backgroundColorValue),
      backgroundBlurIntensity: draft.backgroundBlurIntensity,
      isMuted: draft.isMuted,
      isPlaying: false,
      isExporting: false,
      currentMenuId: 'root',
      clearActiveToolId: true,
      clearSelectedSegmentId: true,
      clearSelectedTextId: true,
      clearSelectedImageId: true,
      clearSelectedVideoOverlayId: true,
      clearSelectedAudioId: true,
      clearSelectedTransitionSegmentId: true,
      isClipSelected: false,
    );

    // Update trimRange based on first segment to give a valid initial state
    if (state.segments.isNotEmpty) {
      state = state.copyWith(
        trimRange: RangeValues(
          state.segments.first.sourceStart,
          state.segments.first.sourceEnd,
        ),
      );
    }
    
    // Load thumbnail for filters if available, else we could try to generate it
    if (draft.thumbnailPath != null) {
      final file = File(draft.thumbnailPath!);
      if (file.existsSync()) {
        try {
          final bytes = await file.readAsBytes();
          state = state.copyWith(filterThumbnail: bytes);
        } catch (_) {}
      }
    }
    
    if (state.filterThumbnail == null) {
      try {
        final thumbs = await _editorService.generateThumbnails(
          inputPath: video.path,
          durationSeconds: draft.durationSeconds,
          count: 1,
        );
        if (thumbs.isNotEmpty) {
          state = state.copyWith(filterThumbnail: thumbs.first);
          // Don't auto-save immediately, it'll save on exit
        }
      } catch (_) {}
    }
  }

  void setPlaying(bool isPlaying) {
    state = state.copyWith(isPlaying: isPlaying);
  }

  void setExporting(bool isExporting) {
    state = state.copyWith(isExporting: isExporting);
  }

  void updatePlaybackPosition(double positionSeconds) {
    state = state.copyWith(currentPlaybackPosition: positionSeconds);
  }

  VideoSegment? getActiveSegment() {
    if (state.segments.isEmpty) return null;
    if (state.segments.length == 1) return state.segments.first;
    if (!state.isClipSelected || state.selectedSegmentId == null) return null;
    try {
      return state.segments.firstWhere((s) => s.id == state.selectedSegmentId);
    } catch (_) {
      return null;
    }
  }

  void togglePreview() {
    if (state.segments.isEmpty) return;

    final currentSeconds = state.currentPlaybackPosition;
    final inSegment = state.segments.any(
      (segment) =>
          currentSeconds >= segment.sourceStart &&
          currentSeconds < segment.sourceEnd,
    );
    
    // We will let the VideoEditorScreen handle the actual controller.play() and seek logic 
    // by reacting to state.isPlaying changes.
    if (state.isPlaying) {
      state = state.copyWith(isPlaying: false);
    } else {
      state = state.copyWith(isPlaying: true, clearSelectedTextId: true);
    }
  }

  void setMuted(bool isMuted) {
    state = state.copyWith(isMuted: isMuted);
  }

  void setCurrentMenu(String menuId) {
    state = state.copyWith(currentMenuId: menuId);
  }

  void setActiveTool(String? toolId) {
    state = state.copyWith(
      activeToolId: toolId,
      clearActiveToolId: toolId == null,
    );
  }

  void closeActiveTool() {
    state = state.copyWith(
      clearActiveToolId: true,
      clearPreviewVolume: true,
      clearPreviewSpeed: true,
      clearPreviewVideoScale: true,
      clearPreviewVideoPan: true,
    );
  }

  void setFilterThumbnail(Uint8List? bytes) {
    state = state.copyWith(
      filterThumbnail: bytes,
      clearFilterThumbnail: bytes == null,
    );
  }

  void deselectAll() {
    state = state.copyWith(
      clearSelectedSegmentId: true,
      clearSelectedTextId: true,
      clearSelectedImageId: true,
      clearSelectedVideoOverlayId: true,
      clearSelectedAudioId: true,
      isClipSelected: false,
      clearActiveToolId: true,
      clearSelectedTransitionSegmentId: true,
      currentMenuId: 'root',
    );
  }

  void selectSegment(String id) {
    if (state.selectedSegmentId == id && state.isClipSelected) return;
    state = state.copyWith(
      selectedSegmentId: id,
      isClipSelected: true,
      clearSelectedTextId: true,
      clearSelectedImageId: true,
      clearSelectedVideoOverlayId: true,
      clearSelectedAudioId: true,
      clearSelectedTransitionSegmentId: true,
      trimRange: RangeValues(
        state.segments.firstWhere((s) => s.id == id).sourceStart,
        state.segments.firstWhere((s) => s.id == id).sourceEnd,
      ),
    );
  }

  void setClipSelected(bool isSelected) {
    state = state.copyWith(isClipSelected: isSelected);
  }

  void setTrimRange(RangeValues value) {
    final normalized = RangeValues(
      value.start.clamp(0.0, state.durationSeconds).toDouble(),
      value.end.clamp(0.0, state.durationSeconds).toDouble(),
    );

    if (state.selectedSegmentId == null) {
      state = state.copyWith(trimRange: normalized);
      return;
    }

    final index = state.segments.indexWhere(
      (segment) => segment.id == state.selectedSegmentId,
    );
    if (index == -1) {
      state = state.copyWith(trimRange: normalized);
      return;
    }

    double minStart = 0.0;
    double maxEnd = state.durationSeconds;
    if (index > 0) {
      minStart = state.segments[index - 1].sourceEnd;
    }
    if (index < state.segments.length - 1) {
      maxEnd = state.segments[index + 1].sourceStart;
    }

    final clampedStart = normalized.start.clamp(minStart, maxEnd).toDouble();
    final clampedEnd = normalized.end.clamp(minStart, maxEnd).toDouble();
    final nextRange = RangeValues(clampedStart, clampedEnd);
    final updatedSegments = [...state.segments];
    updatedSegments[index] = updatedSegments[index].copyWith(
      sourceStart: clampedStart,
      sourceEnd: clampedEnd,
    );

    state = state.copyWith(trimRange: nextRange, segments: updatedSegments);
  }

  Future<void> setTrimRangeAndSeek(RangeValues value, Player player) async {
    setTrimRange(value);

    final currentSeconds = player.state.position.inMilliseconds / 1000.0;
    double? seekTarget;
    if (currentSeconds < value.start) {
      seekTarget = value.start;
    } else if (currentSeconds > value.end) {
      seekTarget = value.end;
    }

    if (seekTarget != null) {
      await player.seek(
        Duration(milliseconds: (seekTarget * 1000).round()),
      );
    }
  }

  void saveStateForUndo() {
    _undoStack.add(state);
    _redoStack.clear();
    state = state.copyWith(canUndo: true, canRedo: false);
  }

  void splitAtPosition(double positionSeconds) {
    final selectedIndex = state.segments.indexWhere(
      (segment) => segment.id == state.selectedSegmentId,
    );
    if (selectedIndex == -1) {
      throw Exception("No segment selected to split.");
    }

    final selectedSegment = state.segments[selectedIndex];
    const edgePaddingSeconds = 0.35;
    if (positionSeconds <= selectedSegment.sourceStart + edgePaddingSeconds ||
        positionSeconds >= selectedSegment.sourceEnd - edgePaddingSeconds) {
      throw Exception("Cannot split too close to segment edges.");
    }

    final rightSegment = VideoSegment(
      id: 'segment_${DateTime.now().microsecondsSinceEpoch}',
      sourceStart: positionSeconds,
      sourceEnd: selectedSegment.sourceEnd,
    );
    final leftSegment = selectedSegment.copyWith(sourceEnd: positionSeconds);
    final updatedSegments = [...state.segments]
      ..[selectedIndex] = leftSegment
      ..insert(selectedIndex + 1, rightSegment);

    saveStateForUndo();
    state = state.copyWith(
      segments: updatedSegments,
      selectedSegmentId: rightSegment.id,
      isClipSelected: true,
      trimRange: RangeValues(rightSegment.sourceStart, rightSegment.sourceEnd),
    );
  }

  void splitAtPlayhead(double position) {
    splitAtPosition(position);
  }

  void deleteSelectedSegment() {
    if (state.segments.length <= 1 || state.selectedSegmentId == null) return;
    final selectedIndex = state.segments.indexWhere(
      (segment) => segment.id == state.selectedSegmentId,
    );
    if (selectedIndex == -1) return;

    final updatedSegments = [...state.segments]..removeAt(selectedIndex);
    final nextIndex = selectedIndex.clamp(0, updatedSegments.length - 1).toInt();
    final nextSegment = updatedSegments[nextIndex];

    saveStateForUndo();
    state = state.copyWith(
      segments: updatedSegments,
      selectedSegmentId: nextSegment.id,
      isClipSelected: true,
      trimRange: RangeValues(nextSegment.sourceStart, nextSegment.sourceEnd),
    );
  }

  void toggleReverse(String segmentId) {
    final index = state.segments.indexWhere((s) => s.id == segmentId);
    if (index == -1) return;
    saveStateForUndo();
    final updatedSegments = [...state.segments];
    updatedSegments[index] = updatedSegments[index].copyWith(
      isReversed: !updatedSegments[index].isReversed,
    );
    state = state.copyWith(segments: updatedSegments);
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(state);
    final previousState = _undoStack.removeLast();
    state = previousState.copyWith(
      canUndo: _undoStack.isNotEmpty,
      canRedo: _redoStack.isNotEmpty,
      isPlaying: false,
    );
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(state);
    final nextState = _redoStack.removeLast();
    state = nextState.copyWith(
      canUndo: _undoStack.isNotEmpty,
      canRedo: _redoStack.isNotEmpty,
      isPlaying: false,
    );
  }



  void setPreviewVolume(double? value) {
    state = state.copyWith(
      previewVolume: value,
      clearPreviewVolume: value == null,
    );
  }

  void commitPreviewVolume() {
    final activeSegment = getActiveSegment();
    if (activeSegment == null || state.previewVolume == null) return;
    final index = state.segments.indexWhere((s) => s.id == activeSegment.id);
    if (index == -1) return;

    saveStateForUndo();
    final updatedSegments = [...state.segments];
    updatedSegments[index] = updatedSegments[index].copyWith(
      volume: state.previewVolume!,
    );
    state = state.copyWith(
      segments: updatedSegments,
      clearPreviewVolume: true,
    );
  }

  void setPreviewSpeed(double? value) {
    state = state.copyWith(
      previewSpeed: value,
      clearPreviewSpeed: value == null,
    );
  }

  void commitPreviewSpeed() {
    final activeSegment = getActiveSegment();
    if (activeSegment == null || state.previewSpeed == null) return;
    final index = state.segments.indexWhere((s) => s.id == activeSegment.id);
    if (index == -1) return;

    saveStateForUndo();
    final updatedSegments = [...state.segments];
    updatedSegments[index] = updatedSegments[index].copyWith(
      speed: state.previewSpeed!,
    );
    state = state.copyWith(
      segments: updatedSegments,
      clearPreviewSpeed: true,
    );
  }

  void setSelectedRatio(EditorCropRatio ratio) {
    state = state.copyWith(selectedRatio: ratio);
  }

  void setCustomCropRect(Rect rect) {
    state = state.copyWith(customCropRect: rect);
  }

  void setBackgroundType(EditorBackgroundType type) {
    saveStateForUndo();
    state = state.copyWith(backgroundType: type);
  }

  void setBackgroundColor(Color color) {
    saveStateForUndo();
    state = state.copyWith(backgroundColor: color);
  }

  void setBackgroundBlurIntensity(double intensity) {
    state = state.copyWith(backgroundBlurIntensity: intensity);
  }

  void setVideoTransform({
    double? videoScale,
    Offset? videoPan,
  }) {
    state = state.copyWith(
      videoScale: videoScale ?? state.videoScale,
      videoPan: videoPan ?? state.videoPan,
    );
  }

  void setPreviewVideoTransform({
    double? previewVideoScale,
    Offset? previewVideoPan,
  }) {
    state = state.copyWith(
      previewVideoScale: previewVideoScale,
      previewVideoPan: previewVideoPan,
    );
  }

  void clearPreviewVideoTransform() {
    state = state.copyWith(
      clearPreviewVideoScale: true,
      clearPreviewVideoPan: true,
    );
  }

  void commitPreviewVideoTransform() {
    if (state.previewVideoScale == null) return;
    saveStateForUndo();
    state = state.copyWith(
      videoScale: state.previewVideoScale!,
      videoPan: state.previewVideoPan ?? state.videoPan,
      clearPreviewVideoScale: true,
      clearPreviewVideoPan: true,
    );
  }

  void setSelectedFilter(FilterPreset? filter) {
    saveStateForUndo();
    state = state.copyWith(
      selectedFilter: filter,
      clearSelectedFilter: filter == null,
      filterIntensity: 1.0,
    );
  }

  void setFilterIntensity(double intensity) {
    state = state.copyWith(filterIntensity: intensity);
  }

  void setActiveFilterCategory(String category) {
    state = state.copyWith(activeFilterCategory: category);
  }

  void selectAudioTrack(String? id) {
    if (id != null) {
      // De-select everything else, and set audio menu
      state = state.copyWith(
        selectedAudioId: id,
        clearSelectedSegmentId: true,
        clearSelectedTextId: true,
        clearSelectedImageId: true,
        clearSelectedVideoOverlayId: true,
        clearSelectedTransitionSegmentId: true,
        clearActiveToolId: true,
        isClipSelected: false,
      );
    } else {
      state = state.copyWith(clearSelectedAudioId: true);
      // Close volume/speed panels if they were open for audio
      if (state.activeToolId == 'volume' || state.activeToolId == 'speed') {
         state = state.copyWith(clearActiveToolId: true);
      }
    }
  }

  void selectTransition(String segmentId) {
    state = state.copyWith(
      selectedTransitionSegmentId: segmentId,
      clearSelectedSegmentId: true,
      clearSelectedTextId: true,
      clearSelectedImageId: true,
      clearSelectedVideoOverlayId: true,
      clearSelectedAudioId: true,
      clearActiveToolId: true,
      isClipSelected: false,
      currentMenuId: 'transition',
    );
  }

  void setSegmentTransition(String? type, [double? duration]) {
    if (state.selectedTransitionSegmentId == null) return;
    
    final index = state.segments.indexWhere((s) => s.id == state.selectedTransitionSegmentId);
    if (index == -1) return;

    saveStateForUndo();
    final updatedSegments = [...state.segments];
    updatedSegments[index] = updatedSegments[index].copyWith(
      transitionType: type,
      clearTransitionType: type == null,
      transitionDuration: duration,
      clearTransitionDuration: duration == null,
    );
    
    state = state.copyWith(segments: updatedSegments);
  }

  void splitAudioTrack(double globalPlayhead) {
    if (state.selectedAudioId == null) return;
    
    final id = state.selectedAudioId!;
    final audioTrack = state.audioTracks.firstWhere((a) => a.id == id, orElse: () => throw Exception('Audio track not found'));
    
    // Check if playhead is within this audio track's bounds
    if (globalPlayhead <= audioTrack.timelineStart || globalPlayhead >= audioTrack.timelineEnd) {
      throw Exception('Playhead is outside the selected audio track');
    }

    final splitOffset = globalPlayhead - audioTrack.timelineStart;
    final splitSourceTime = audioTrack.sourceStart + splitOffset;

    final firstHalf = audioTrack.copyWith(
      sourceEnd: splitSourceTime,
    );

    final secondHalf = audioTrack.copyWith(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      sourceStart: splitSourceTime,
      timelineStart: globalPlayhead,
    );

    final newTracks = <AudioTrackModel>[];
    for (final track in state.audioTracks) {
      if (track.id == id) {
        newTracks.add(firstHalf);
        newTracks.add(secondHalf);
      } else {
        newTracks.add(track);
      }
    }

    saveStateForUndo();
    state = state.copyWith(
      audioTracks: newTracks,
      selectedAudioId: secondHalf.id,
    );
  }

  bool _overlaps(Duration start1, Duration end1, Duration start2, Duration end2) {
    return start1 < end2 && start2 < end1;
  }

  int _findAvailableLane(Duration startTime, Duration endTime, {String? excludeId, int startLane = 0}) {
    int lane = startLane;
    while (true) {
      bool collision = false;
      
      for (final item in state.textOverlays) {
        if (item.id == excludeId) continue;
        if (item.laneIndex == lane && _overlaps(startTime, endTime, item.startTime, item.endTime)) {
          collision = true;
          break;
        }
      }
      if (collision) { lane++; continue; }

      for (final item in state.imageOverlays) {
        if (item.id == excludeId) continue;
        if (item.laneIndex == lane && _overlaps(startTime, endTime, item.startTime, item.endTime)) {
          collision = true;
          break;
        }
      }
      if (collision) { lane++; continue; }

      for (final item in state.videoOverlays) {
        if (item.id == excludeId) continue;
        if (item.laneIndex == lane && _overlaps(startTime, endTime, item.timelineStart, item.timelineEnd)) {
          collision = true;
          break;
        }
      }
      if (collision) { lane++; continue; }

      for (final item in state.audioTracks) {
        if (item.id == excludeId) continue;
        final trackStart = Duration(milliseconds: (item.timelineStart * 1000).round());
        final trackEnd = Duration(milliseconds: (item.timelineEnd * 1000).round());
        if (item.laneIndex == lane && _overlaps(startTime, endTime, trackStart, trackEnd)) {
          collision = true;
          break;
        }
      }
      if (collision) { lane++; continue; }

      return lane;
    }
  }

  /// Moves `draggedId` to `targetLane`. If something already occupies that
  /// lane at the same time range, swap their lane indices. This gives
  /// smooth one-lane-at-a-time swap behavior (like reordering layers).
  void _swapToLane(String draggedId, int targetLane, Duration startTime, Duration endTime) {
    // Find any item currently sitting at targetLane that overlaps our time range.
    // If found, give it our old lane. Then set ours to targetLane.

    // First, find the dragged item's current lane across all item types.
    int? draggedCurrentLane;
    for (final t in state.textOverlays) {
      if (t.id == draggedId) { draggedCurrentLane = t.laneIndex; break; }
    }
    if (draggedCurrentLane == null) {
      for (final i in state.imageOverlays) {
        if (i.id == draggedId) { draggedCurrentLane = i.laneIndex; break; }
      }
    }
    if (draggedCurrentLane == null) {
      for (final v in state.videoOverlays) {
        if (v.id == draggedId) { draggedCurrentLane = v.laneIndex; break; }
      }
    }
    if (draggedCurrentLane == null) {
      for (final a in state.audioTracks) {
        if (a.id == draggedId) { draggedCurrentLane = a.laneIndex; break; }
      }
    }
    if (draggedCurrentLane == null || draggedCurrentLane == targetLane) return;

    // Now search for a conflicting item at targetLane and swap it to draggedCurrentLane.
    var textOverlays = [...state.textOverlays];
    var imageOverlays = [...state.imageOverlays];
    var videoOverlays = [...state.videoOverlays];
    var audioTracks = [...state.audioTracks];

    // Swap conflicting text overlays
    for (int i = 0; i < textOverlays.length; i++) {
      final item = textOverlays[i];
      if (item.id == draggedId) continue;
      if (item.laneIndex == targetLane && _overlaps(startTime, endTime, item.startTime, item.endTime)) {
        textOverlays[i] = item.copyWith(laneIndex: draggedCurrentLane);
      }
    }

    // Swap conflicting image overlays
    for (int i = 0; i < imageOverlays.length; i++) {
      final item = imageOverlays[i];
      if (item.id == draggedId) continue;
      if (item.laneIndex == targetLane && _overlaps(startTime, endTime, item.startTime, item.endTime)) {
        imageOverlays[i] = item.copyWith(laneIndex: draggedCurrentLane);
      }
    }

    // Swap conflicting video overlays
    for (int i = 0; i < videoOverlays.length; i++) {
      final item = videoOverlays[i];
      if (item.id == draggedId) continue;
      if (item.laneIndex == targetLane && _overlaps(startTime, endTime, item.timelineStart, item.timelineEnd)) {
        videoOverlays[i] = item.copyWith(laneIndex: draggedCurrentLane);
      }
    }

    // Swap conflicting audio tracks
    for (int i = 0; i < audioTracks.length; i++) {
      final item = audioTracks[i];
      if (item.id == draggedId) continue;
      final trackStart = Duration(milliseconds: (item.timelineStart * 1000).round());
      final trackEnd = Duration(milliseconds: (item.timelineEnd * 1000).round());
      if (item.laneIndex == targetLane && _overlaps(startTime, endTime, trackStart, trackEnd)) {
        audioTracks[i] = item.copyWith(laneIndex: draggedCurrentLane);
      }
    }

    // Now set the dragged item to targetLane
    for (int i = 0; i < textOverlays.length; i++) {
      if (textOverlays[i].id == draggedId) {
        textOverlays[i] = textOverlays[i].copyWith(laneIndex: targetLane);
      }
    }
    for (int i = 0; i < imageOverlays.length; i++) {
      if (imageOverlays[i].id == draggedId) {
        imageOverlays[i] = imageOverlays[i].copyWith(laneIndex: targetLane);
      }
    }
    for (int i = 0; i < videoOverlays.length; i++) {
      if (videoOverlays[i].id == draggedId) {
        videoOverlays[i] = videoOverlays[i].copyWith(laneIndex: targetLane);
      }
    }
    for (int i = 0; i < audioTracks.length; i++) {
      if (audioTracks[i].id == draggedId) {
        audioTracks[i] = audioTracks[i].copyWith(laneIndex: targetLane);
      }
    }

    state = state.copyWith(
      textOverlays: textOverlays,
      imageOverlays: imageOverlays,
      videoOverlays: videoOverlays,
      audioTracks: audioTracks,
    );
  }

  void addTextOverlay(TextOverlayModel overlay) {
    saveStateForUndo();
    final lane = _findAvailableLane(overlay.startTime, overlay.endTime);
    final placedOverlay = overlay.copyWith(laneIndex: lane);
    state = state.copyWith(
      textOverlays: [...state.textOverlays, placedOverlay],
      selectedTextId: placedOverlay.id,
      isClipSelected: false,
    );
  }

  void selectTextOverlay(String? overlayId) {
    state = state.copyWith(
      selectedTextId: overlayId,
      clearSelectedTextId: overlayId == null,
      clearSelectedImageId: overlayId != null,
      clearSelectedVideoOverlayId: overlayId != null,
      clearSelectedSegmentId: overlayId != null,
      isClipSelected: overlayId == null ? state.isClipSelected : false,
      currentMenuId: 'root',
    );
  }

  void updateTextOverlay(String id, TextOverlayModel Function(TextOverlayModel) update, {int? newLaneIndex}) {
    final index = state.textOverlays.indexWhere((text) => text.id == id);
    if (index == -1) return;
    saveStateForUndo();
    final updated = [...state.textOverlays];
    final item = update(updated[index]);
    updated[index] = item;
    state = state.copyWith(textOverlays: updated);
    if (newLaneIndex != null && newLaneIndex != item.laneIndex) {
      _swapToLane(id, newLaneIndex, item.startTime, item.endTime);
    }
  }

  void deleteTextOverlay(String id) {
    saveStateForUndo();
    state = state.copyWith(
      textOverlays: state.textOverlays.where((text) => text.id != id).toList(),
      clearSelectedTextId: state.selectedTextId == id,
    );
  }

  void duplicateTextOverlay(String id) {
    final source = state.textOverlays.where((text) => text.id == id);
    if (source.isEmpty) return;
    saveStateForUndo();
    final overlay = source.first;
    final duplicated = overlay.copyWith(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      position: overlay.position + const Offset(20, 20),
    );
    state = state.copyWith(
      textOverlays: [...state.textOverlays, duplicated],
      selectedTextId: duplicated.id,
      clearSelectedImageId: true,
      clearSelectedVideoOverlayId: true,
      isClipSelected: false,
    );
  }

  void addImageOverlay(ImageOverlayModel overlay) {
    saveStateForUndo();
    final lane = _findAvailableLane(overlay.startTime, overlay.endTime);
    final placedOverlay = overlay.copyWith(laneIndex: lane);
    state = state.copyWith(
      imageOverlays: [...state.imageOverlays, placedOverlay],
      selectedImageId: placedOverlay.id,
      clearSelectedTextId: true,
      clearSelectedVideoOverlayId: true,
      clearSelectedSegmentId: true,
      isClipSelected: false,
      currentMenuId: 'image_overlay',
    );
  }

  void selectImageOverlay(String? overlayId) {
    state = state.copyWith(
      selectedImageId: overlayId,
      clearSelectedImageId: overlayId == null,
      clearSelectedTextId: overlayId != null,
      clearSelectedVideoOverlayId: overlayId != null,
      clearSelectedSegmentId: overlayId != null,
      isClipSelected: overlayId == null ? state.isClipSelected : false,
      currentMenuId: overlayId != null ? 'image_overlay' : 'root',
    );
  }

  void updateImageOverlay(String id, ImageOverlayModel Function(ImageOverlayModel) update, {int? newLaneIndex}) {
    final index = state.imageOverlays.indexWhere((img) => img.id == id);
    if (index == -1) return;
    saveStateForUndo();
    final updated = [...state.imageOverlays];
    final item = update(updated[index]);
    updated[index] = item;
    state = state.copyWith(imageOverlays: updated);
    if (newLaneIndex != null && newLaneIndex != item.laneIndex) {
      _swapToLane(id, newLaneIndex, item.startTime, item.endTime);
    }
  }

  void deleteImageOverlay(String id) {
    saveStateForUndo();
    state = state.copyWith(
      imageOverlays: state.imageOverlays.where((img) => img.id != id).toList(),
      clearSelectedImageId: state.selectedImageId == id,
    );
  }

  void duplicateImageOverlay(String id) {
    final source = state.imageOverlays.where((img) => img.id == id);
    if (source.isEmpty) return;
    saveStateForUndo();
    final overlay = source.first;
    final duplicated = overlay.copyWith(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      position: overlay.position + const Offset(20, 20),
    );
    state = state.copyWith(
      imageOverlays: [...state.imageOverlays, duplicated],
      selectedImageId: duplicated.id,
      clearSelectedTextId: true,
      isClipSelected: false,
    );
  }

  // --- Video Overlay Logic ---
  void addVideoOverlay(VideoOverlayModel overlay) {
    saveStateForUndo();
    final lane = _findAvailableLane(overlay.timelineStart, overlay.timelineEnd);
    final placedOverlay = overlay.copyWith(laneIndex: lane);
    state = state.copyWith(
      videoOverlays: [...state.videoOverlays, placedOverlay],
      selectedVideoOverlayId: placedOverlay.id,
      clearSelectedTextId: true,
      clearSelectedImageId: true,
      clearSelectedSegmentId: true,
      isClipSelected: false,
      currentMenuId: 'video_overlay',
    );
  }

  void selectVideoOverlay(String? overlayId) {
    state = state.copyWith(
      selectedVideoOverlayId: overlayId,
      clearSelectedVideoOverlayId: overlayId == null,
      clearSelectedTextId: overlayId != null,
      clearSelectedImageId: overlayId != null,
      clearSelectedSegmentId: overlayId != null,
      isClipSelected: overlayId == null ? state.isClipSelected : false,
      currentMenuId: overlayId != null ? 'video_overlay' : 'root',
    );
  }

  void updateVideoOverlay(String id, VideoOverlayModel Function(VideoOverlayModel) update, {int? newLaneIndex}) {
    final index = state.videoOverlays.indexWhere((vid) => vid.id == id);
    if (index == -1) return;
    saveStateForUndo();
    final updated = [...state.videoOverlays];
    final item = update(updated[index]);
    updated[index] = item;
    state = state.copyWith(videoOverlays: updated);
    if (newLaneIndex != null && newLaneIndex != item.laneIndex) {
      _swapToLane(id, newLaneIndex, item.timelineStart, item.timelineEnd);
    }
  }

  void deleteVideoOverlay(String id) {
    saveStateForUndo();
    state = state.copyWith(
      videoOverlays: state.videoOverlays.where((vid) => vid.id != id).toList(),
      clearSelectedVideoOverlayId: state.selectedVideoOverlayId == id,
    );
  }

  void duplicateVideoOverlay(String id) {
    final source = state.videoOverlays.where((vid) => vid.id == id);
    if (source.isEmpty) return;
    saveStateForUndo();
    final overlay = source.first;
    final duplicated = overlay.copyWith(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      position: overlay.position + const Offset(20, 20),
    );
    state = state.copyWith(
      videoOverlays: [...state.videoOverlays, duplicated],
      selectedVideoOverlayId: duplicated.id,
      clearSelectedTextId: true,
      clearSelectedImageId: true,
      isClipSelected: false,
    );
  }

  void splitVideoOverlay(double globalPlayhead) {
    if (state.selectedVideoOverlayId == null) return;
    
    final id = state.selectedVideoOverlayId!;
    final videoOverlay = state.videoOverlays.firstWhere((v) => v.id == id, orElse: () => throw Exception('Video overlay not found'));
    
    // Check if playhead is within this video overlay's bounds
    final playheadDuration = Duration(milliseconds: (globalPlayhead * 1000).round());
    if (playheadDuration <= videoOverlay.timelineStart || playheadDuration >= videoOverlay.timelineEnd) {
      throw Exception('Playhead is outside the selected video overlay');
    }

    final splitOffset = playheadDuration - videoOverlay.timelineStart;
    final splitSourceTime = videoOverlay.sourceStart + (splitOffset.inMilliseconds / 1000.0);

    saveStateForUndo();
    
    final firstHalf = videoOverlay.copyWith(
      timelineEnd: playheadDuration,
      sourceEnd: splitSourceTime,
    );

    final secondHalf = videoOverlay.copyWith(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      timelineStart: playheadDuration,
      sourceStart: splitSourceTime,
    );

    final updatedOverlays = state.videoOverlays.map((v) => v.id == id ? firstHalf : v).toList();
    updatedOverlays.add(secondHalf);

    state = state.copyWith(
      videoOverlays: updatedOverlays,
      selectedVideoOverlayId: secondHalf.id,
    );
  }


  void setOverlayOpacity(double opacity) {
    if (state.selectedImageId != null) {
      updateImageOverlay(
        state.selectedImageId!,
        (overlay) => overlay.copyWith(opacity: opacity),
      );
    } else if (state.selectedVideoOverlayId != null) {
      updateVideoOverlay(
        state.selectedVideoOverlayId!,
        (overlay) => overlay.copyWith(opacity: opacity),
      );
    }
  }

  void setOverlayAnimation({
    String? animationIn,
    String? animationOut,
    double? animationInDuration,
    double? animationOutDuration,
  }) {
    if (state.selectedTextId != null) {
      updateTextOverlay(
        state.selectedTextId!,
        (overlay) => overlay.copyWith(
          inAnimation: animationIn ?? overlay.inAnimation,
          outAnimation: animationOut ?? overlay.outAnimation,
        ),
      );
    } else if (state.selectedImageId != null) {
      updateImageOverlay(
        state.selectedImageId!,
        (overlay) => overlay.copyWith(
          clearAnimationIn: animationIn == 'none',
          animationIn: animationIn == 'none' ? null : (animationIn ?? overlay.animationIn),
          clearAnimationOut: animationOut == 'none',
          animationOut: animationOut == 'none' ? null : (animationOut ?? overlay.animationOut),
          animationInDuration: animationInDuration ?? overlay.animationInDuration,
          animationOutDuration: animationOutDuration ?? overlay.animationOutDuration,
        ),
      );
    } else if (state.selectedVideoOverlayId != null) {
      updateVideoOverlay(
        state.selectedVideoOverlayId!,
        (overlay) => overlay.copyWith(
          clearAnimationIn: animationIn == 'none',
          animationIn: animationIn == 'none' ? null : (animationIn ?? overlay.animationIn),
          clearAnimationOut: animationOut == 'none',
          animationOut: animationOut == 'none' ? null : (animationOut ?? overlay.animationOut),
          animationInDuration: animationInDuration ?? overlay.animationInDuration,
          animationOutDuration: animationOutDuration ?? overlay.animationOutDuration,
        ),
      );
    }
  }

  // --- Audio Track Logic ---
  void addAudioTrack(AudioTrackModel track) {
    saveStateForUndo();
    final trackStart = Duration(milliseconds: (track.timelineStart * 1000).round());
    final trackEnd = Duration(milliseconds: (track.timelineEnd * 1000).round());
    final lane = _findAvailableLane(trackStart, trackEnd);
    final placedTrack = track.copyWith(laneIndex: lane);
    state = state.copyWith(
      audioTracks: [...state.audioTracks, placedTrack],
      selectedAudioId: placedTrack.id,
    );
  }

  void updateAudioTrack(AudioTrackModel updatedTrack, {int? newLaneIndex}) {
    saveStateForUndo();
    final item = updatedTrack;
    state = state.copyWith(
      audioTracks: state.audioTracks.map((t) => t.id == item.id ? item : t).toList(),
    );
    if (newLaneIndex != null && newLaneIndex != item.laneIndex) {
      final trackStart = Duration(milliseconds: (item.timelineStart * 1000).round());
      final trackEnd = Duration(milliseconds: (item.timelineEnd * 1000).round());
      _swapToLane(item.id, newLaneIndex, trackStart, trackEnd);
    }
  }

  void deleteAudioTrack(String id) {
    saveStateForUndo();
    state = state.copyWith(
      audioTracks: state.audioTracks.where((t) => t.id != id).toList(),
      selectedAudioId: state.selectedAudioId == id ? null : state.selectedAudioId,
      clearSelectedAudioId: state.selectedAudioId == id,
    );
  }

  void setSelectedAudioId(String? id) {
    state = state.copyWith(
      selectedAudioId: id,
      clearSelectedAudioId: id == null,
    );
  }

}

final videoEditorProvider =
    StateNotifierProvider.autoDispose<VideoEditorNotifier, VideoEditorState>(
      (ref) => VideoEditorNotifier(VideoEditorService()),
    );

final totalEditedDurationProvider = Provider.autoDispose<double>((ref) {
  final state = ref.watch(videoEditorProvider);
  final videoDuration = state.segments.fold(0.0, (sum, segment) => sum + segment.duration);
  final maxAudioEnd = state.audioTracks.fold(0.0, (maxEnd, track) => max(maxEnd, track.timelineEnd));
  return max(videoDuration, maxAudioEnd);
});

final activeSegmentProvider = Provider.autoDispose<VideoSegment?>((ref) {
  final editorState = ref.watch(videoEditorProvider);
  if (editorState.segments.isEmpty) return null;
  if (editorState.segments.length == 1) return editorState.segments.first;
  if (!editorState.isClipSelected || editorState.selectedSegmentId == null) return null;
  try {
    return editorState.segments.firstWhere((s) => s.id == editorState.selectedSegmentId);
  } catch (_) {
    return null;
  }
});

final canDeleteSegmentProvider = Provider.autoDispose<bool>((ref) {
  final editorState = ref.watch(videoEditorProvider);
  return !(editorState.segments.length <= 1 || editorState.selectedSegmentId == null);
});

final playerProvider = StateProvider<Player?>((ref) => null);
final videoCanvasSizeProvider = StateProvider<Size?>((ref) => null);

final isSplitToolEnabledProvider = Provider.autoDispose<bool>((ref) {
  final editorState = ref.watch(videoEditorProvider);
  final selectedSegment = ref.watch(activeSegmentProvider);
  if (selectedSegment == null) return false;

  // Split is only enabled if a segment is selected and it's not too close to the edges
  // This logic mirrors the check in splitAtPosition
  final positionSeconds = editorState.currentPlaybackPosition;
  const edgePaddingSeconds = 0.35;

  return editorState.isClipSelected &&
      positionSeconds > selectedSegment.sourceStart + edgePaddingSeconds &&
      positionSeconds < selectedSegment.sourceEnd - edgePaddingSeconds;
});

final exportPayloadProvider = Provider.autoDispose<Map<String, dynamic>?>((ref) {
  final editorState = ref.watch(videoEditorProvider);
  final player = ref.watch(playerProvider);
  final videoCanvasSize = ref.watch(videoCanvasSizeProvider);

  if (editorState.sourceVideo == null || editorState.isExporting || player == null || videoCanvasSize == null) {
    return null;
  }

  if (editorState.trimRange.end <= editorState.trimRange.start) {
    return null;
  }

  final originalVideoSize = Size(
    player.state.width?.toDouble() ?? 0,
    player.state.height?.toDouble() ?? 0,
  );

  final geometry = _resolveExportGeometry(
    editorState: editorState,
    previewCanvasSize: videoCanvasSize,
    originalVideoSize: originalVideoSize,
  );

  final renderId = 'export_${DateTime.now().microsecondsSinceEpoch}';

  return {
    'sourceVideo': File(editorState.sourceVideo!.path),
    'segments': editorState.segments,
    'muteAudio': editorState.isMuted,
    'targetAspectRatio': geometry.aspectRatio,
    'customCropRect': geometry.cropRect,
    'originalVideoSize': originalVideoSize,
    'previewCanvasSize': videoCanvasSize,
    'renderId': renderId,
    'colorFilterMatrix':
        editorState.selectedFilter?.getInterpolatedMatrix(editorState.filterIntensity),
    'textOverlays': editorState.textOverlays.isEmpty
        ? null
        : editorState.textOverlays,
    'imageOverlays': editorState.imageOverlays.isEmpty
        ? null
        : editorState.imageOverlays,
    'videoOverlays': editorState.videoOverlays.isEmpty
        ? null
        : editorState.videoOverlays,
    'audioTracks': editorState.audioTracks,
    'backgroundType': editorState.backgroundType,
    'backgroundColor': editorState.backgroundColor,
    'backgroundBlurIntensity': editorState.backgroundBlurIntensity,
  };
});
