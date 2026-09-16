import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/models/draft_project.dart';
import '../../../core/services/draft_service.dart';
import '../../../core/utils/file_utils.dart';
import '../logic/animation/animatable_double.dart';
import '../logic/animation/clip_keyframes.dart';
import '../logic/animation/clip_keyframes.dart' as kf;
import '../logic/effects/effect_catalog.dart';
import '../logic/filter_presets.dart';
import '../logic/timeline/timeline_geometry.dart';
import '../models/filter_preset.dart';
import '../models/text_overlay_model.dart';
import '../models/image_overlay_model.dart';
import '../models/video_overlay_model.dart';
import '../models/audio_track_model.dart';
import '../models/media_asset.dart';
import '../models/video_editor_state.dart';
import '../models/video_segment.dart';
import '../services/media_import_service.dart';
import '../services/video_editor_service.dart';
import '../services/video_thumbnail_service.dart';

/// True when a stored crop rect is the whole frame — i.e. not a crop at all.
///
/// The last survivor of the legacy export geometry: crop, zoom and pan now
/// reach the renderer as one content rect (`logic/canvas_geometry.dart`), and
/// this only tells draft migration whether a `custom` ratio meant a real crop.
bool _isNearlyFullFrame(Rect rect) {
  return rect.left.abs() < 0.0001 &&
      rect.top.abs() < 0.0001 &&
      (1.0 - rect.right).abs() < 0.0001 &&
      (1.0 - rect.bottom).abs() < 0.0001;
}

/// Ratio a draft reopens with.
///
/// Drafts written while `custom` was the app default carry `custom` plus a
/// full-frame crop rect — that combination was the implicit 9:16 default, not
/// a crop the user made, so it maps to the 9:16 default (rendering is
/// identical). Only a draft with a real crop rect keeps the custom path.
EditorCropRatio _ratioFromDraft(DraftProject draft) {
  final ratio = EditorCropRatio.values.firstWhere(
    (e) => e.name == draft.selectedRatioName,
    orElse: () => EditorCropRatio.ratio9x16,
  );
  if (ratio != EditorCropRatio.custom) return ratio;

  final r = draft.customCropRect;
  final isFullFrame = r.length != 4 ||
      _isNearlyFullFrame(Rect.fromLTWH(r[0], r[1], r[2], r[3]));
  return isFullFrame ? EditorCropRatio.ratio9x16 : EditorCropRatio.custom;
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

  /// Starts a project from one or more imported files.
  ///
  /// Assets land as clips in import order. The first asset also decides the
  /// project's shape — later clips are fitted inside it rather than changing
  /// the canvas underneath the ones already placed.
  Future<void> loadProject({
    required List<MediaAsset> assets,
    String? draftId,
  }) async {
    if (assets.isEmpty) return;

    final newDraftId =
        draftId ?? DateTime.now().millisecondsSinceEpoch.toString();
    final segments = <VideoSegment>[
      for (var index = 0; index < assets.length; index++)
        _segmentForAsset(assets[index], index),
    ];
    final firstAsset = assets.first;

    state = state.copyWith(
      draftId: newDraftId,
      assets: assets,
      durationSeconds: firstAsset.durationSeconds,
      trimRange: RangeValues(segments.first.sourceStart, segments.first.sourceEnd),
      segments: segments,
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
      selectedRatio: EditorCropRatio.ratio9x16,
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
      clearSelectedVideoOverlayId: true,
    );

    try {
      final frame = await _coverFrame(
        firstAsset.path,
        firstAsset.durationSeconds,
      );
      if (frame != null) {
        state = state.copyWith(
          filterThumbnail: frame,
          clearFilterThumbnail: false,
        );
      }
    } catch (_) {
      // A missing preview frame is cosmetic; filters still work without it.
    }
  }

  /// Appends more imported files to the end of the existing timeline.
  void addAssets(List<MediaAsset> assets) {
    if (assets.isEmpty) return;

    saveStateForUndo();
    final offset = state.segments.length;
    state = state.copyWith(
      assets: [...state.assets, ...assets],
      segments: [
        ...state.segments,
        for (var index = 0; index < assets.length; index++)
          _segmentForAsset(assets[index], offset + index),
      ],
    );
  }

  /// Moves the clip at [oldIndex] to [newIndex].
  ///
  /// Transitions belong to the boundary *after* a clip, so reordering carries
  /// each clip's transition with it — and the clip that ends up last cannot
  /// keep one, because it no longer has a neighbour to transition into.
  /// Moves the clip at [fromIndex] so that it ends up at [toIndex].
  ///
  /// [toIndex] is the position in the **final** list, not an insertion point in
  /// the list before removal — dragging the first clip to the end is
  /// `reorderSegment(0, segments.length - 1)`.
  void reorderSegment(int fromIndex, int toIndex) {
    final segments = state.segments;
    if (fromIndex < 0 || fromIndex >= segments.length) return;

    final target = toIndex.clamp(0, segments.length - 1);
    if (target == fromIndex) return;

    saveStateForUndo();
    final reordered = [...segments];
    reordered.insert(target, reordered.removeAt(fromIndex));

    // Whatever ends up last has nothing to transition into. A transition left
    // on it would be a window with no incoming clip, which the composer and the
    // engine would both have to special-case.
    final last = reordered.length - 1;
    if (reordered[last].transitionType != null) {
      reordered[last] = reordered[last].copyWith(
        clearTransitionType: true,
        clearTransitionDuration: true,
      );
    }

    state = state.copyWith(segments: reordered);
  }

  VideoSegment _segmentForAsset(MediaAsset asset, int index) {
    final seed = MediaImportService.seedFor(asset);
    return VideoSegment(
      id: 'clip_${DateTime.now().microsecondsSinceEpoch}_$index',
      assetId: seed.assetId,
      sourceStart: seed.sourceStart,
      sourceEnd: seed.sourceEnd,
    );
  }

  /// A representative frame for filter tiles and draft covers.
  ///
  /// Taken a little way in rather than at zero, because the opening frame of a
  /// clip is often black or a fade.
  Future<Uint8List?> _coverFrame(String path, double durationSeconds) {
    final atSeconds = durationSeconds <= 0 ? 0.0 : (durationSeconds * 0.1).clamp(0.0, 3.0);
    return VideoThumbnailService.instance.singleFrame(
      path: path,
      timeMs: (atSeconds * 1000).round(),
    );
  }

  /// Sets the project's cover image and persists it with the draft.
  ///
  /// Written under a timestamped name on purpose: `FileImage` caches by path,
  /// so overwriting one cover file would keep showing the old picture
  /// everywhere it had already been drawn. The previous cover file is deleted
  /// once the state points away from it.
  Future<bool> setCoverImage(Uint8List bytes) async {
    final draftId = state.draftId;
    if (draftId == null || bytes.isEmpty) return false;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final file = File(
        '${docDir.path}/cover_${draftId}_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(bytes);

      final previous = state.thumbnailPath;
      state = state.copyWith(thumbnailPath: file.path);
      if (previous != null && previous.contains('cover_$draftId')) {
        unawaited(() async {
          try {
            await File(previous).delete();
          } catch (_) {}
        }());
      }
      await saveDraft();
      return true;
    } catch (_) {
      return false;
    }
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
        createdAt:
            DateTime.now(), // Real creation time would need to be tracked, but this is fine for updating
        updatedAt: DateTime.now(),
        durationSeconds: state.durationSeconds,
        thumbnailPath: thumbnailPath,
        assets: state.assets.map((e) => e.toJson()).toList(),
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

  /// Rebuilds the asset pool, migrating drafts saved before it existed.
  ///
  /// An older draft names a single `sourceVideoPath` and its clips carry no
  /// asset id, so one asset is synthesised for that file and every clip is
  /// pointed at it.
  List<MediaAsset> _restoreAssets(DraftProject draft) {
    if (draft.assets.isNotEmpty) {
      return draft.assets.map(MediaAsset.fromJson).toList();
    }

    if (draft.sourceVideoPath.isEmpty) return const [];
    return [
      MediaAsset(
        id: _migratedAssetId,
        path: draft.sourceVideoPath,
        type: MediaAssetType.video,
        durationSeconds: draft.durationSeconds,
        // Dimensions were never stored; probing happens lazily and the canvas
        // falls back to the preview's own aspect until then.
        width: 0,
        height: 0,
        hasAudio: true,
      ),
    ];
  }

  List<VideoSegment> _restoreSegments(
    DraftProject draft,
    List<MediaAsset> assets,
  ) {
    final fallbackAssetId = assets.isEmpty ? '' : assets.first.id;
    return draft.segments.map((json) {
      final segment = VideoSegment.fromJson(json);
      if (segment.assetId.isNotEmpty) return segment;
      return segment.copyWith(assetId: fallbackAssetId);
    }).toList();
  }

  static const _migratedAssetId = 'asset_migrated_source';

  Future<void> loadDraft(DraftProject draft) async {
    final assets = _restoreAssets(draft);
    final segments = _restoreSegments(draft, assets);

    state = state.copyWith(
      draftId: draft.id,
      thumbnailPath: draft.thumbnailPath,
      assets: assets,
      durationSeconds: assets.isEmpty ? 0.0 : assets.first.durationSeconds,
      trimRange: RangeValues(
        0,
        draft.durationSeconds,
      ), // Will be updated if segments exist
      segments: segments,
      textOverlays: draft.textOverlays
          .map((e) => TextOverlayModel.fromJson(e))
          .toList(),
      imageOverlays: draft.imageOverlays
          .map((e) => ImageOverlayModel.fromJson(e))
          .toList(),
      videoOverlays: draft.videoOverlays
          .map((e) => VideoOverlayModel.fromJson(e))
          .toList(),
      audioTracks: draft.audioTracks
          .map((e) => AudioTrackModel.fromJson(e))
          .toList(),
      selectedRatio: _ratioFromDraft(draft),
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
      // Derived rather than stored: a draft holding per-clip grades must not
      // reopen with the sheet set to "apply to all", because the next filter
      // the user picked would then wipe every one of those grades.
      filterAppliesToAll: !segments.any((s) => s.filterId != null),
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
      final cover = state.assets.isEmpty ? null : state.assets.first;
      if (cover != null) {
        try {
          final frame = await _coverFrame(cover.path, cover.durationSeconds);
          if (frame != null) {
            state = state.copyWith(filterThumbnail: frame);
            // Don't auto-save immediately, it'll save on exit
          }
        } catch (_) {}
      }
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

  /// Selects the clip under the playhead, if there is one.
  ///
  /// For tools on the **root** menu that act on a clip — Transform is the
  /// first. The root menu shows when nothing is selected, so "the clip the
  /// user means" is the one they are looking at: the one under the playhead.
  /// Resolved through `segmentIndexAt`, the same geometry the filmstrip and
  /// playback use, so a transition overlap resolves to the clip actually on
  /// screen. Returns whether a clip was selected.
  bool selectSegmentAtPlayhead() {
    final index = segmentIndexAt(state.currentPlaybackPosition, state.segments);
    if (index < 0 || index >= state.segments.length) return false;
    selectSegment(state.segments[index].id);
    return true;
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
    if (state.selectedSegmentId == null) {
      state = state.copyWith(trimRange: value);
      return;
    }

    final index = state.segments.indexWhere(
      (segment) => segment.id == state.selectedSegmentId,
    );
    if (index == -1) {
      state = state.copyWith(trimRange: value);
      return;
    }

    final segment = state.segments[index];
    final asset = state.assetFor(segment);

    // A photo has no source to run out of, so it can be stretched as long as
    // the user likes; a video is bounded by its own duration.
    final sourceLimit = asset == null
        ? state.durationSeconds
        : (asset.isImage ? double.infinity : asset.durationSeconds);

    final normalized = RangeValues(
      value.start.clamp(0.0, sourceLimit).toDouble(),
      value.end.clamp(0.0, sourceLimit).toDouble(),
    );

    // Neighbours only constrain a clip when they are cut from the *same* file:
    // that is the split case, where two clips share one source timeline and
    // must not overlap in it. Clips from different assets have no relationship
    // in source time at all, and clamping across them would drag a clip's
    // range to a position that means nothing in its own file.
    double minStart = 0.0;
    double maxEnd = sourceLimit;
    if (index > 0 && _sharesAsset(state.segments[index - 1], segment)) {
      minStart = state.segments[index - 1].sourceEnd;
    }
    if (index < state.segments.length - 1 &&
        _sharesAsset(state.segments[index + 1], segment)) {
      maxEnd = state.segments[index + 1].sourceStart;
    }

    final clampedStart = normalized.start.clamp(minStart, maxEnd).toDouble();
    final clampedEnd = normalized.end.clamp(minStart, maxEnd).toDouble();
    final nextRange = RangeValues(clampedStart, clampedEnd);
    final updatedSegments = [...state.segments];
    final selectedSegment = updatedSegments[index];
    if (!selectedSegment.isReversed &&
        selectedSegment.overrideVideoPath != null) {
      unawaited(FileUtils.deleteFile(selectedSegment.overrideVideoPath));
    }
    updatedSegments[index] = selectedSegment.copyWith(
      sourceStart: clampedStart,
      sourceEnd: clampedEnd,
      clearOverrideVideoPath: !selectedSegment.isReversed,
    );

    state = state.copyWith(trimRange: nextRange, segments: updatedSegments);
  }

  /// Whether two clips are cut from the same imported file.
  bool _sharesAsset(VideoSegment a, VideoSegment b) {
    if (a.assetId.isEmpty || b.assetId.isEmpty) {
      // Pre-migration drafts: every clip came from the one source file.
      return state.assets.length <= 1;
    }
    return a.assetId == b.assetId;
  }

  void saveStateForUndo() {
    _undoStack.add(state);
    _redoStack.clear();
    state = state.copyWith(canUndo: true, canRedo: false);
  }

  /// Cuts the clip under the playhead in two, at the playhead.
  ///
  /// [timelineSeconds] is a **timeline** instant, which is what the playhead
  /// reports. It is not a source instant: the two only coincide for a single
  /// untrimmed clip that starts at zero, which is why this used to appear to
  /// cut in the wrong place as soon as a project had more than one clip or any
  /// clip had been trimmed. The clip is found with [segmentIndexAt] and the
  /// instant converted with [VideoSegment.sourceAtOffset] — the same mapping
  /// playback and the filmstrip use — so the cut lands under the playhead
  /// through trims, speed changes and reversal alike.
  void splitAtPosition(double timelineSeconds) {
    final segments = state.segments;
    if (segments.isEmpty) {
      throw Exception('There is nothing to split.');
    }

    // The playhead decides which clip is cut, not the selection: the blade cuts
    // where the user can see it. They coincide whenever the playhead is inside
    // the selected clip, which is the usual case.
    final index = segmentIndexAt(timelineSeconds, segments);
    if (index < 0) {
      throw Exception('There is nothing to split.');
    }

    final segment = segments[index];
    final starts = segmentTimelineStarts(segments);
    final offsetIntoClip = timelineSeconds - starts[index];

    // Measured in timeline seconds, so the rule matches the gap the user can
    // actually see. The same test in source seconds would tighten or loosen
    // with the clip's speed.
    if (offsetIntoClip < kMinClipDurationSeconds ||
        segment.duration - offsetIntoClip < kMinClipDurationSeconds) {
      throw Exception('Move the playhead further into the clip to split it.');
    }

    final sourceSplit = segment.sourceAtOffset(offsetIntoClip);

    // A reversed clip runs backwards through its source, so the half that plays
    // first is the one nearer the source *end*.
    final leftRange = segment.isReversed
        ? (start: sourceSplit, end: segment.sourceEnd)
        : (start: segment.sourceStart, end: sourceSplit);
    final rightRange = segment.isReversed
        ? (start: segment.sourceStart, end: sourceSplit)
        : (start: sourceSplit, end: segment.sourceEnd);

    final leftSegment = segment.copyWith(
      sourceStart: leftRange.start,
      sourceEnd: leftRange.end,
      // The outgoing transition belongs to the boundary this clip used to have
      // with the *next* clip. That boundary is now the right half's, and the
      // new seam between the halves is a hard cut — splitting a clip must not
      // silently invent a transition inside it.
      clearTransitionType: true,
      clearTransitionDuration: true,
      // Any prepared proxy was rendered for the old, wider source range and no
      // longer describes either half.
      clearOverrideVideoPath: true,
    );

    final rightSegment = VideoSegment(
      id: 'segment_${DateTime.now().microsecondsSinceEpoch}',
      // Both halves keep reading from the file the clip was cut from.
      assetId: segment.assetId,
      sourceStart: rightRange.start,
      sourceEnd: rightRange.end,
      speed: segment.speed,
      volume: segment.volume,
      isReversed: segment.isReversed,
      transitionType: segment.transitionType,
      transitionDuration: segment.transitionDuration,
      // Both halves are the same footage with the same look and the same
      // placement; a split is a cut, not a reason to lose either.
      filterId: segment.filterId,
      filterIntensity: segment.filterIntensity,
      effectId: segment.effectId,
      effectIntensity: segment.effectIntensity,
      canvasScale: segment.canvasScale,
      canvasOffsetX: segment.canvasOffsetX,
      canvasOffsetY: segment.canvasOffsetY,
    );

    // Keyframes are clip-relative, so each half gets its own rescaled copy.
    // A reversed clip plays its source backwards, but *progress* is timeline
    // order in both cases — the left half is always the one that plays first —
    // so the cut fraction is the same either way.
    final cut = (offsetIntoClip / segment.duration).clamp(0.0, 1.0).toDouble();
    final updatedSegments = [...segments]
      ..[index] = _splitKeyframes(leftSegment, segment, cut, isLeft: true)
      ..insert(
        index + 1,
        _splitKeyframes(rightSegment, segment, cut, isLeft: false),
      );

    saveStateForUndo();
    state = state.copyWith(
      segments: updatedSegments,
      selectedSegmentId: rightSegment.id,
      isClipSelected: true,
      trimRange: RangeValues(rightSegment.sourceStart, rightSegment.sourceEnd),
    );
  }

  /// One half of a split clip, with every keyframe rescaled into its own 0..1.
  ///
  /// **A keyframe's progress is clip-relative, so a split has to rescale it.**
  /// Copying the lists verbatim leaves the left half's later keyframes sitting
  /// past its own end — where the value holds, silently freezing the move — and
  /// bunches the right half's earlier ones before its start.
  ///
  /// [cut] is where the split falls in the *original* clip's progress. For the
  /// left half keyframes at or before it map `p -> p / cut`; for the right,
  /// those at or after map `p -> (p - cut) / (1 - cut)`.
  ///
  /// **A keyframe is captured at the cut first**, so the value at the seam is
  /// identical on either side and the split is invisible in the picture. Doing
  /// it before the rescale is what makes the two halves meet: without it the
  /// left half's last keyframe and the right half's first would be whatever
  /// happened to be nearest, and the move would jump at the cut.
  ///
  /// A degenerate cut (at 0 or 1) leaves one half unkeyframed rather than
  /// dividing by zero — the split guard makes that unreachable in practice, but
  /// this must not be the thing that throws if it ever changes.
  VideoSegment _splitKeyframes(
    VideoSegment half,
    VideoSegment original,
    double cut, {
    required bool isLeft,
  }) {
    if (!original.hasKeyframes) return half;
    if (cut <= 0.0 || cut >= 1.0) return half;

    // Pin the seam on the original, so both halves read the same value there.
    final pinned = captureKeyframe(original, cut);

    var out = half;
    for (final property in ClipProperty.values) {
      final param = clipParameter(pinned, property);
      final kept = <Keyframe>[];
      for (final k in param.keyframes) {
        if (isLeft) {
          if (k.progress > cut + kKeyframeMatchProgress) continue;
          kept.add(Keyframe(
            progress: (k.progress / cut).clamp(0.0, 1.0).toDouble(),
            value: k.value,
            interpolation: k.interpolation,
          ));
        } else {
          if (k.progress < cut - kKeyframeMatchProgress) continue;
          kept.add(Keyframe(
            progress:
                ((k.progress - cut) / (1 - cut)).clamp(0.0, 1.0).toDouble(),
            value: k.value,
            interpolation: k.interpolation,
          ));
        }
      }
      out = withClipParameter(
        out,
        property,
        AnimatableDouble.sorted(
          baseValue: param.baseValue,
          envelope: param.envelope,
          keyframes: kept,
        ),
      );
    }
    return out;
  }

  void splitAtPlayhead(double timelineSeconds) {
    splitAtPosition(timelineSeconds);
  }

  /// A pinch/drag on the canvas is starting to reposition the selected clip.
  ///
  /// The undo snapshot is taken here, once, so the whole gesture undoes as one
  /// step rather than as sixty.
  void beginClipCanvasTransform() {
    if (state.selectedSegmentId == null) return;
    saveStateForUndo();
    state = state.copyWith(isClipTransformActive: true);
  }

  /// Live values from the gesture, written into the selected clip.
  ///
  /// The editor deliberately does not push a timeline per call — the engine is
  /// updated through its own lightweight override channel and catches up from
  /// this state once on release.
  void updateClipCanvasTransform({
    required double scale,
    required double offsetX,
    required double offsetY,
    double? rotation,
  }) {
    // **Three properties, one instant.** Routed through the edit rule like
    // every other control, so the gesture keyframes itself on a clip carrying
    // diamonds and writes base values on one that does not — without knowing
    // the feature exists. The three writes share one resolved progress, so a
    // single diamond is placed rather than three at almost-identical instants.
    //
    // No undo snapshot per frame: `beginClipCanvasTransform` took one, which is
    // what makes the whole drag one step.
    _editSelectedClip(
      takeUndoSnapshot: false,
      (segment, progress) {
        var out = _writeClipValue(
          segment,
          ClipProperty.canvasScale,
          scale.clamp(kMinClipCanvasScale, kMaxClipCanvasScale).toDouble(),
          playheadProgress: progress,
        );
        out = _writeClipValue(
          out,
          ClipProperty.canvasOffsetX,
          offsetX.clamp(-1.5, 1.5).toDouble(),
          playheadProgress: progress,
        );
        out = _writeClipValue(
          out,
          ClipProperty.canvasOffsetY,
          offsetY.clamp(-1.5, 1.5).toDouble(),
          playheadProgress: progress,
        );
        // Optional on purpose: the pinch gesture has no angle to give, and
        // writing zero for it would silently un-rotate a clip the moment it
        // was moved.
        if (rotation == null) return out;
        return _writeClipValue(
          out,
          ClipProperty.canvasRotation,
          normaliseDegrees(rotation),
          playheadProgress: progress,
        );
      },
    );
  }

  void endClipCanvasTransform() {
    if (!state.isClipTransformActive) return;
    state = state.copyWith(isClipTransformActive: false);
  }

  /// Puts the selected clip back to its automatic fit — centred, unscaled.
  void resetClipCanvasTransform() {
    final targetId = state.selectedSegmentId;
    if (targetId == null) return;
    saveStateForUndo();
    state = state.copyWith(
      segments: [
        for (final segment in state.segments)
          if (segment.id == targetId)
            // A reset puts the clip back to the plain fit outright, keyframes
            // and all: "reset" that left a move running would not be one.
            segment.copyWith(
              canvasScale: kUnitParameter,
              canvasOffsetX: kZeroParameter,
              canvasOffsetY: kZeroParameter,
              canvasRotation: kZeroParameter,
            )
          else
            segment,
      ],
    );
  }

  Future<bool> preparePlaybackProxyForSegment(String segmentId) async {
    final index = state.segments.indexWhere((s) => s.id == segmentId);
    if (index == -1) return false;

    final segment = state.segments[index];
    if (!_needsPlaybackProxyForSegment(index)) return false;

    final asset = state.assetFor(segment);
    if (asset == null || asset.isImage) return false;
    final sourceVideoPath = asset.path;
    if (sourceVideoPath.isEmpty) return false;

    final oldProxyPath = segment.overrideVideoPath;
    final proxyPath = await _editorService.createClipPlaybackProxy(
      inputPath: sourceVideoPath,
      sourceStart: segment.sourceStart,
      sourceEnd: segment.sourceEnd,
    );

    final currentIndex = state.segments.indexWhere((s) => s.id == segmentId);
    if (currentIndex == -1) {
      await FileUtils.deleteFile(proxyPath);
      return false;
    }

    final currentSegment = state.segments[currentIndex];
    if (currentSegment.isReversed ||
        (currentSegment.sourceStart - segment.sourceStart).abs() > 0.001 ||
        (currentSegment.sourceEnd - segment.sourceEnd).abs() > 0.001) {
      await FileUtils.deleteFile(proxyPath);
      return false;
    }

    final updatedSegments = [...state.segments];
    updatedSegments[currentIndex] = currentSegment.copyWith(
      overrideVideoPath: proxyPath,
    );
    state = state.copyWith(segments: updatedSegments);

    await FileUtils.deleteFile(oldProxyPath);
    return true;
  }

  /// Whether this clip should be rendered to a standalone file for smoother
  /// playback.
  ///
  /// Only worth doing when a neighbour cut from the *same* file leaves a gap in
  /// source time, which is what forces the decoder to jump. Clips from
  /// different assets are separate media items anyway, so a proxy buys nothing.
  bool _needsPlaybackProxyForSegment(int index) {
    final segment = state.segments[index];
    if (segment.isReversed ||
        segment.overrideVideoPath != null ||
        segment.sourceEnd <= segment.sourceStart) {
      return false;
    }
    if (state.assetFor(segment)?.isImage ?? false) return false;

    const epsilon = 0.001;
    if (index > 0) {
      final previous = state.segments[index - 1];
      if (_sharesAsset(previous, segment) &&
          !previous.isReversed &&
          previous.overrideVideoPath == null &&
          segment.sourceStart > previous.sourceEnd + epsilon) {
        return true;
      }
    }

    if (index < state.segments.length - 1) {
      final next = state.segments[index + 1];
      if (_sharesAsset(next, segment) &&
          !next.isReversed &&
          next.overrideVideoPath == null &&
          next.sourceStart > segment.sourceEnd + epsilon) {
        return true;
      }
    }

    return false;
  }

  void deleteSelectedSegment() {
    if (state.segments.length <= 1 || state.selectedSegmentId == null) return;
    final selectedIndex = state.segments.indexWhere(
      (segment) => segment.id == state.selectedSegmentId,
    );
    if (selectedIndex == -1) return;

    final updatedSegments = [...state.segments]..removeAt(selectedIndex);
    final nextIndex = selectedIndex
        .clamp(0, updatedSegments.length - 1)
        .toInt();
    final nextSegment = updatedSegments[nextIndex];

    saveStateForUndo();
    state = state.copyWith(
      segments: updatedSegments,
      selectedSegmentId: nextSegment.id,
      isClipSelected: true,
      trimRange: RangeValues(nextSegment.sourceStart, nextSegment.sourceEnd),
    );
  }

  Future<void> toggleReverse(String segmentId) async {
    final index = state.segments.indexWhere((s) => s.id == segmentId);
    if (index == -1) return;

    final segment = state.segments[index];
    if (segment.isReversed) {
      saveStateForUndo();
      final proxyPath = segment.overrideVideoPath;
      final updatedSegments = [...state.segments];
      updatedSegments[index] = segment.copyWith(
        isReversed: false,
        clearOverrideVideoPath: true,
      );
      state = state.copyWith(segments: updatedSegments);
      await FileUtils.deleteFile(proxyPath);
      return;
    }

    final asset = state.assetFor(segment);
    if (asset == null || asset.path.isEmpty) {
      throw StateError('Cannot reverse a clip without a source video.');
    }
    if (asset.isImage) {
      throw StateError('A photo has nothing to reverse.');
    }
    final sourceVideoPath = asset.path;

    final proxyPath = await _editorService.createReverseProxy(
      inputPath: sourceVideoPath,
      sourceStart: segment.sourceStart,
      sourceEnd: segment.sourceEnd,
    );

    final currentIndex = state.segments.indexWhere((s) => s.id == segmentId);
    if (currentIndex == -1) {
      await FileUtils.deleteFile(proxyPath);
      return;
    }

    final currentSegment = state.segments[currentIndex];
    if (currentSegment.isReversed ||
        currentSegment.overrideVideoPath != segment.overrideVideoPath ||
        (currentSegment.sourceStart - segment.sourceStart).abs() > 0.001 ||
        (currentSegment.sourceEnd - segment.sourceEnd).abs() > 0.001) {
      await FileUtils.deleteFile(proxyPath);
      return;
    }

    saveStateForUndo();
    final updatedSegments = [...state.segments];
    updatedSegments[currentIndex] = currentSegment.copyWith(
      isReversed: true,
      overrideVideoPath: proxyPath,
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
    // Through the edit rule, so a clip carrying diamonds keyframes the volume
    // at the playhead instead of flattening the fade to one level. Resolved
    // against *this* clip rather than `selectedClipProgress`, because
    // `getActiveSegment` falls back to the only clip when nothing is selected
    // and the two would then disagree about which clip is being edited.
    final target = state.segments[index];
    final starts = segmentTimelineStarts(state.segments);
    final progress = index < starts.length
        ? target.clipProgressAt(state.currentPlaybackPosition, starts[index])
        : null;
    final updatedSegments = [...state.segments];
    updatedSegments[index] = _writeClipValue(
      target,
      ClipProperty.volume,
      state.previewVolume!,
      playheadProgress: progress,
    );
    state = state.copyWith(segments: updatedSegments, clearPreviewVolume: true);
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
    state = state.copyWith(segments: updatedSegments, clearPreviewSpeed: true);
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

  void setVideoTransform({double? videoScale, Offset? videoPan}) {
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

  /// Applies a filter, either to the whole project or to the selected clip.
  ///
  /// With [VideoEditorState.filterAppliesToAll] on this is the project look:
  /// one grade on the finished frame. With it off the filter belongs to the
  /// selected clip and is applied before a transition blends that clip, so two
  /// clips with different filters cross-fade between their looks.
  ///
  /// The two are kept mutually exclusive per clip: switching to the project
  /// look clears the per-clip grades, because leaving both would grade those
  /// clips twice.
  void setSelectedFilter(FilterPreset? filter) {
    saveStateForUndo();

    if (state.filterAppliesToAll) {
      state = state.copyWith(
        selectedFilter: filter,
        clearSelectedFilter: filter == null,
        filterIntensity: 1.0,
        segments: [
          for (final segment in state.segments)
            segment.copyWith(clearFilterId: true, filterIntensity: 1.0),
        ],
      );
      return;
    }

    final targetId = state.selectedSegmentId;
    if (targetId == null) return;

    state = state.copyWith(
      segments: [
        for (final segment in state.segments)
          if (segment.id == targetId)
            segment.copyWith(
              filterId: filter?.id,
              clearFilterId: filter == null,
              filterIntensity: 1.0,
            )
          else
            segment,
      ],
    );
  }

  void setFilterIntensity(double intensity) {
    if (state.filterAppliesToAll) {
      state = state.copyWith(filterIntensity: intensity);
      return;
    }

    final targetId = state.selectedSegmentId;
    if (targetId == null) return;

    state = state.copyWith(
      segments: [
        for (final segment in state.segments)
          if (segment.id == targetId)
            segment.copyWith(filterIntensity: intensity)
          else
            segment,
      ],
    );
  }

  /// Applies an effect to the **selected** clip, or clears it when [effectId]
  /// is null.
  ///
  /// An effect belongs to a clip, never to the project: unlike a filter there
  /// is no "apply to all" mode, because a multi-pass effect on every clip is a
  /// cost the user did not ask for. With no clip selected this does nothing
  /// rather than guessing at a target.
  ///
  /// [intensity] defaults to the catalog's own [VideoEffect.defaultIntensity]
  /// for [effectId], so tapping a tile is the whole interaction — the slider
  /// is there for anyone who wants to retune it, not a step on the way to
  /// seeing the effect at all.
  ///
  /// **Clearing goes through `clearEffectId`.** A bare `effectId: null` is
  /// ignored by `copyWith` for every nullable field in this codebase, so it
  /// would leave the old effect in place and read as a dead None tile.
  ///
  /// [takeUndoSnapshot] is false only for the slider's live frames: the
  /// gesture takes one snapshot on drag start, so a drag undoes as one step
  /// rather than a pixel at a time.
  void setClipEffect(
    String? effectId, {
    double? intensity,
    bool takeUndoSnapshot = true,
  }) {
    final targetId = state.selectedSegmentId;
    if (targetId == null) return;

    final effect = videoEffectById(effectId);
    // An id the catalog does not know draws nothing, so storing it would be a
    // tile that appears to work and does not. Treated as a clear.
    final resolvedId = effect?.id;
    final resolvedIntensity =
        intensity ?? effect?.defaultIntensity ?? defaultEffectIntensity;

    if (takeUndoSnapshot) saveStateForUndo();

    // **Changing the effect drops the *intensity's* keyframes** (see
    // [_nextEffectIntensity]) — that parameter belongs to the effect, and
    // carrying a curve onto a different shader would animate a strength the
    // user never shaped. It leaves the transform and volume keyframes standing:
    // those are the *clip's*, not the effect's, and the rejected design's habit
    // of taking them down with the effect is exactly the confusion of ownership
    // this rebuild exists to fix.
    state = state.copyWith(
      segments: [
        for (final segment in state.segments)
          if (segment.id == targetId)
            segment.copyWith(
              effectId: resolvedId,
              clearEffectId: resolvedId == null,
              effectIntensity: _nextEffectIntensity(
                segment: segment,
                resolvedId: resolvedId,
                baseValue: resolvedIntensity.clamp(0.0, 1.0),
              ),
            )
          else
            segment,
      ],
    );
  }

  /// The intensity parameter a clip should hold once [resolvedId] is applied
  /// at [baseValue].
  ///
  /// Two cases, and keeping them apart is what makes the slider safe:
  ///
  /// * **The effect is unchanged** — this is the slider moving, or the panel
  ///   re-sending the same id. Only [AnimatableDouble.baseValue] is written;
  ///   whatever envelope or keyframes the parameter carries survive untouched.
  ///   Retuning a strength must never silently discard the shape on it, and
  ///   the slider re-sends the id on every frame of a drag, so a rebuild-from-
  ///   scratch here would wipe the animation on the first pixel of movement.
  /// * **A different effect is applied** — the old effect's shape belongs to
  ///   the old effect (a glitch's pulse means nothing on a vignette), so the
  ///   parameter is rebuilt from the new effect's own
  ///   [VideoEffect.defaultEnvelope] and any keyframes are dropped. That is
  ///   also what makes one tap feel designed rather than static.
  ///
  /// Clearing the effect resets to a flat default: a clip with no effect
  /// holding a pulse would put an envelope back the moment any effect was
  /// applied, which the user never asked for.
  AnimatableDouble _nextEffectIntensity({
    required VideoSegment segment,
    required String? resolvedId,
    required double baseValue,
  }) {
    if (resolvedId == null) {
      return AnimatableDouble(baseValue: baseValue);
    }
    if (segment.effectId == resolvedId) {
      return segment.effectIntensity.copyWith(baseValue: baseValue);
    }
    return AnimatableDouble(
      baseValue: baseValue,
      envelope: videoEffectById(resolvedId)?.defaultEnvelope,
    );
  }

  // ── Keyframes ─────────────────────────────────────────────────────────────
  //
  // **A diamond is an instant of a clip, and every animatable property carries
  // a keyframe at it.** The pure functions live in `clip_keyframes.dart`; what
  // is here is the part that needs the playhead — which instant "here" means,
  // and whether a given edit is a base value or a keyframe.

  /// **The one place an edit decides whether it writes a base value or a
  /// keyframe.**
  ///
  /// This is what makes the diamond button the only keyframe control in the
  /// app. The pinch gesture, the volume slider and the effect intensity slider
  /// all route through here and inherit keyframing without knowing the feature
  /// exists. The alternative — a keyframe-aware variant of each control — is
  /// exactly how the rejected design ended up able to animate one number.
  ///
  /// - **No diamonds on the clip:** write the base. Byte-identical to what each
  ///   control did before this existed, which is what keeps an unkeyframed
  ///   project unchanged.
  /// - **Diamonds, playhead on one:** write that keyframe's value and leave the
  ///   base alone.
  /// - **Diamonds, playhead between them:** place a diamond first — capturing
  ///   every *other* property at that instant so nothing else moves — then
  ///   write into it.
  ///
  /// Takes no undo snapshot: the caller's gesture already took one, once.
  VideoSegment _writeClipValue(
    VideoSegment segment,
    ClipProperty property,
    double value, {
    required double? playheadProgress,
  }) {
    final param = clipParameter(segment, property);
    if (!segment.hasKeyframes || playheadProgress == null) {
      return withClipParameter(
          segment, property, param.copyWith(baseValue: value));
    }

    final tolerance = keyframeHitToleranceFor(segment);
    var out = segment;
    var target = keyframeProgressNear(segment, playheadProgress, tolerance);
    if (target == null) {
      out = captureKeyframe(segment, playheadProgress);
      target = playheadProgress;
    }
    final resolved = target;

    final p = clipParameter(out, property);
    return withClipParameter(
      out,
      property,
      AnimatableDouble.sorted(
        baseValue: p.baseValue,
        envelope: p.envelope,
        keyframes: [
          for (final k in p.keyframes)
            if ((k.progress - resolved).abs() <= kKeyframeMatchProgress)
              // The easing belongs to the keyframe, not to the edit: retuning a
              // value must not silently straighten the curve leaving it.
              Keyframe(
                progress: k.progress,
                value: value,
                interpolation: k.interpolation,
              )
            else
              k,
        ],
      ),
    );
  }

  /// Applies [write] to the selected clip, resolving the playhead's progress
  /// through it once.
  void _editSelectedClip(
    VideoSegment Function(VideoSegment segment, double? progress) write, {
    bool takeUndoSnapshot = true,
  }) {
    final targetId = state.selectedSegmentId;
    if (targetId == null) return;
    final progress = state.selectedClipProgress;
    if (takeUndoSnapshot) saveStateForUndo();
    state = state.copyWith(
      segments: [
        for (final segment in state.segments)
          if (segment.id == targetId) write(segment, progress) else segment,
      ],
    );
  }

  /// Writes one property of the selected clip through the edit rule.
  void setClipProperty(
    ClipProperty property,
    double value, {
    bool takeUndoSnapshot = true,
  }) {
    _editSelectedClip(
      takeUndoSnapshot: takeUndoSnapshot,
      (segment, progress) => _writeClipValue(
        segment,
        property,
        value,
        playheadProgress: progress,
      ),
    );
  }

  /// Places a diamond at the playhead, pinning every property at the value it
  /// already has there — so the picture does not change.
  void addKeyframeAtPlayhead() {
    _editSelectedClip(
      (segment, progress) =>
          progress == null ? segment : captureKeyframe(segment, progress),
    );
  }

  /// Removes the diamond under the playhead from every property.
  void removeKeyframeAtPlayhead() {
    _editSelectedClip(
      (segment, progress) => progress == null
          ? segment
          : removeKeyframe(
              segment, progress, keyframeHitToleranceFor(segment)),
    );
  }

  /// Sets the curve on the segment the playhead is inside.
  ///
  /// **Never places a diamond**, unlike every other write here. The plus button
  /// is the one control that creates instants; a curve picker that quietly
  /// added one was the device-reported fault — the user tapped it expecting to
  /// choose a shape and got a new point on their timeline instead.
  ///
  /// With nothing to ease ([VideoEditorState.canEditKeyframeCurve] false) this
  /// does nothing, and the icon is disabled so it should not be reachable.
  void setKeyframeCurve(KeyframeInterpolation curve) {
    if (!state.canEditKeyframeCurve) return;
    _editSelectedClip((segment, progress) {
      if (progress == null) return segment;
      // Aliased: the notifier method and the pure function share a name on
      // purpose — one is the command, the other is what it does.
      return kf.setKeyframeCurve(
        segment,
        progress,
        keyframeHitToleranceFor(segment),
        curve,
      );
    });
  }


  /// Moves the playhead onto a diamond.
  ///
  /// What makes tapping a diamond and then tapping minus remove it — the
  /// plus/minus flip reads the playhead, so the playhead has to actually be on
  /// the diamond. Not an undoable edit: it moves the playhead, nothing else.
  void seekToKeyframe(double progress) {
    final segment = state.selectedSegment;
    if (segment == null) return;
    final starts = segmentTimelineStarts(state.segments);
    final index = state.segments.indexWhere((s) => s.id == segment.id);
    if (index < 0 || index >= starts.length) return;
    updatePlaybackPosition(starts[index] + progress * segment.duration);
  }

  /// Switches between grading the whole project and grading one clip.
  ///
  /// Turning it **on** lifts the selected clip's filter up to the project so
  /// the look the user is already seeing carries over rather than vanishing;
  /// turning it **off** pushes the project filter down onto every clip, for the
  /// same reason. Either way the picture does not change at the moment the
  /// switch is flipped — only what a subsequent edit will affect.
  void setFilterAppliesToAll(bool appliesToAll) {
    if (state.filterAppliesToAll == appliesToAll) return;
    saveStateForUndo();

    if (appliesToAll) {
      final selected = state.selectedSegment;
      final preset = FilterPresets.byId(selected?.filterId);
      state = state.copyWith(
        filterAppliesToAll: true,
        selectedFilter: preset ?? state.selectedFilter,
        clearSelectedFilter: preset == null && state.selectedFilter == null,
        filterIntensity: selected?.filterIntensity ?? state.filterIntensity,
        segments: [
          for (final segment in state.segments)
            segment.copyWith(clearFilterId: true, filterIntensity: 1.0),
        ],
      );
      return;
    }

    final projectFilterId = state.selectedFilter?.id;
    state = state.copyWith(
      filterAppliesToAll: false,
      clearSelectedFilter: true,
      filterIntensity: 1.0,
      segments: [
        for (final segment in state.segments)
          segment.copyWith(
            filterId: projectFilterId,
            clearFilterId: projectFilterId == null,
            filterIntensity: state.filterIntensity,
          ),
      ],
    );
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

  /// Sets the transition on the selected seam, or on every seam.
  ///
  /// With [VideoEditorState.transitionAppliesToAll] on this writes the same
  /// transition to every cut, which is what "apply to all" means in the sheet.
  /// The **last** clip never takes one either way: a transition there would be
  /// a window with no incoming clip.
  void setSegmentTransition(String? type, [double? duration]) {
    if (state.transitionAppliesToAll) {
      _applyTransitionToAllSeams(type, duration);
      return;
    }

    if (state.selectedTransitionSegmentId == null) return;

    final index = state.segments.indexWhere(
      (s) => s.id == state.selectedTransitionSegmentId,
    );
    if (index == -1 || index >= state.segments.length - 1) return;

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

  void _applyTransitionToAllSeams(String? type, double? duration) {
    if (state.segments.length < 2) return;

    saveStateForUndo();
    final last = state.segments.length - 1;
    state = state.copyWith(
      segments: [
        for (var i = 0; i < state.segments.length; i++)
          if (i == last)
            state.segments[i].copyWith(
              clearTransitionType: true,
              clearTransitionDuration: true,
            )
          else
            state.segments[i].copyWith(
              transitionType: type,
              clearTransitionType: type == null,
              transitionDuration: duration,
              clearTransitionDuration: duration == null,
            ),
      ],
    );
  }

  /// Switches the transition sheet between one seam and every seam.
  ///
  /// Turning it on immediately spreads the selected seam's transition across
  /// the timeline, so the switch does what it says rather than only affecting
  /// the next choice the user makes.
  void setTransitionAppliesToAll(bool appliesToAll) {
    if (state.transitionAppliesToAll == appliesToAll) return;

    if (!appliesToAll) {
      state = state.copyWith(transitionAppliesToAll: false);
      return;
    }

    final selected = state.segments.firstWhere(
      (s) => s.id == state.selectedTransitionSegmentId,
      orElse: () => state.segments.isEmpty
          ? VideoSegment(id: '', sourceStart: 0, sourceEnd: 0)
          : state.segments.first,
    );

    state = state.copyWith(transitionAppliesToAll: true);
    if (selected.transitionType != null) {
      _applyTransitionToAllSeams(
        selected.transitionType,
        selected.transitionDuration,
      );
    }
  }

  void splitAudioTrack(double globalPlayhead) {
    if (state.selectedAudioId == null) return;

    final id = state.selectedAudioId!;
    final audioTrack = state.audioTracks.firstWhere(
      (a) => a.id == id,
      orElse: () => throw Exception('Audio track not found'),
    );

    // Check if playhead is within this audio track's bounds
    if (globalPlayhead <= audioTrack.timelineStart ||
        globalPlayhead >= audioTrack.timelineEnd) {
      throw Exception('Playhead is outside the selected audio track');
    }

    final splitOffset = globalPlayhead - audioTrack.timelineStart;
    final splitSourceTime = audioTrack.sourceStart + splitOffset;

    final firstHalf = audioTrack.copyWith(sourceEnd: splitSourceTime);

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

  bool _overlaps(
    Duration start1,
    Duration end1,
    Duration start2,
    Duration end2,
  ) {
    return start1 < end2 && start2 < end1;
  }

  int _findAvailableLane(
    Duration startTime,
    Duration endTime, {
    String? excludeId,
    int startLane = 0,
  }) {
    int lane = startLane;
    while (true) {
      bool collision = false;

      for (final item in state.textOverlays) {
        if (item.id == excludeId) continue;
        if (item.laneIndex == lane &&
            _overlaps(startTime, endTime, item.startTime, item.endTime)) {
          collision = true;
          break;
        }
      }
      if (collision) {
        lane++;
        continue;
      }

      for (final item in state.imageOverlays) {
        if (item.id == excludeId) continue;
        if (item.laneIndex == lane &&
            _overlaps(startTime, endTime, item.startTime, item.endTime)) {
          collision = true;
          break;
        }
      }
      if (collision) {
        lane++;
        continue;
      }

      for (final item in state.videoOverlays) {
        if (item.id == excludeId) continue;
        if (item.laneIndex == lane &&
            _overlaps(
              startTime,
              endTime,
              item.timelineStart,
              item.timelineEnd,
            )) {
          collision = true;
          break;
        }
      }
      if (collision) {
        lane++;
        continue;
      }

      for (final item in state.audioTracks) {
        if (item.id == excludeId) continue;
        final trackStart = Duration(
          milliseconds: (item.timelineStart * 1000).round(),
        );
        final trackEnd = Duration(
          milliseconds: (item.timelineEnd * 1000).round(),
        );
        if (item.laneIndex == lane &&
            _overlaps(startTime, endTime, trackStart, trackEnd)) {
          collision = true;
          break;
        }
      }
      if (collision) {
        lane++;
        continue;
      }

      return lane;
    }
  }

  /// Moves `draggedId` to `targetLane`. If something already occupies that
  /// lane at the same time range, swap their lane indices. This gives
  /// smooth one-lane-at-a-time swap behavior (like reordering layers).
  void _swapToLane(
    String draggedId,
    int targetLane,
    Duration startTime,
    Duration endTime,
  ) {
    // Find any item currently sitting at targetLane that overlaps our time range.
    // If found, give it our old lane. Then set ours to targetLane.

    // First, find the dragged item's current lane across all item types.
    int? draggedCurrentLane;
    for (final t in state.textOverlays) {
      if (t.id == draggedId) {
        draggedCurrentLane = t.laneIndex;
        break;
      }
    }
    if (draggedCurrentLane == null) {
      for (final i in state.imageOverlays) {
        if (i.id == draggedId) {
          draggedCurrentLane = i.laneIndex;
          break;
        }
      }
    }
    if (draggedCurrentLane == null) {
      for (final v in state.videoOverlays) {
        if (v.id == draggedId) {
          draggedCurrentLane = v.laneIndex;
          break;
        }
      }
    }
    if (draggedCurrentLane == null) {
      for (final a in state.audioTracks) {
        if (a.id == draggedId) {
          draggedCurrentLane = a.laneIndex;
          break;
        }
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
      if (item.laneIndex == targetLane &&
          _overlaps(startTime, endTime, item.startTime, item.endTime)) {
        textOverlays[i] = item.copyWith(laneIndex: draggedCurrentLane);
      }
    }

    // Swap conflicting image overlays
    for (int i = 0; i < imageOverlays.length; i++) {
      final item = imageOverlays[i];
      if (item.id == draggedId) continue;
      if (item.laneIndex == targetLane &&
          _overlaps(startTime, endTime, item.startTime, item.endTime)) {
        imageOverlays[i] = item.copyWith(laneIndex: draggedCurrentLane);
      }
    }

    // Swap conflicting video overlays
    for (int i = 0; i < videoOverlays.length; i++) {
      final item = videoOverlays[i];
      if (item.id == draggedId) continue;
      if (item.laneIndex == targetLane &&
          _overlaps(startTime, endTime, item.timelineStart, item.timelineEnd)) {
        videoOverlays[i] = item.copyWith(laneIndex: draggedCurrentLane);
      }
    }

    // Swap conflicting audio tracks
    for (int i = 0; i < audioTracks.length; i++) {
      final item = audioTracks[i];
      if (item.id == draggedId) continue;
      final trackStart = Duration(
        milliseconds: (item.timelineStart * 1000).round(),
      );
      final trackEnd = Duration(
        milliseconds: (item.timelineEnd * 1000).round(),
      );
      if (item.laneIndex == targetLane &&
          _overlaps(startTime, endTime, trackStart, trackEnd)) {
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

  void updateTextOverlay(
    String id,
    TextOverlayModel Function(TextOverlayModel) update, {
    int? newLaneIndex,
  }) {
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

  /// A gesture frame's worth of text transform, with **no undo snapshot**.
  ///
  /// The canvas handles call this every pointer move; going through
  /// [updateTextOverlay] pushed an undo entry per frame, so one drag filled
  /// the stack and "undo" walked back through it a pixel at a time. The
  /// gesture calls [saveStateForUndo] once when it starts, which makes the
  /// whole drag one step — the same shape as the clip canvas transform.
  void updateTextOverlayLive(
    String id,
    TextOverlayModel Function(TextOverlayModel) update,
  ) {
    final index = state.textOverlays.indexWhere((text) => text.id == id);
    if (index == -1) return;
    final updated = [...state.textOverlays];
    updated[index] = update(updated[index]);
    state = state.copyWith(textOverlays: updated);
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

  void updateImageOverlay(
    String id,
    ImageOverlayModel Function(ImageOverlayModel) update, {
    int? newLaneIndex,
  }) {
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

  void updateVideoOverlay(
    String id,
    VideoOverlayModel Function(VideoOverlayModel) update, {
    int? newLaneIndex,
  }) {
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
    final videoOverlay = state.videoOverlays.firstWhere(
      (v) => v.id == id,
      orElse: () => throw Exception('Video overlay not found'),
    );

    // Check if playhead is within this video overlay's bounds
    final playheadDuration = Duration(
      milliseconds: (globalPlayhead * 1000).round(),
    );
    if (playheadDuration <= videoOverlay.timelineStart ||
        playheadDuration >= videoOverlay.timelineEnd) {
      throw Exception('Playhead is outside the selected video overlay');
    }

    final splitOffset = playheadDuration - videoOverlay.timelineStart;
    final splitSourceTime =
        videoOverlay.sourceStart + (splitOffset.inMilliseconds / 1000.0);

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

    final updatedOverlays = state.videoOverlays
        .map((v) => v.id == id ? firstHalf : v)
        .toList();
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
          animationInDuration:
              animationInDuration ?? overlay.animationInDuration,
          animationOutDuration:
              animationOutDuration ?? overlay.animationOutDuration,
        ),
      );
    } else if (state.selectedImageId != null) {
      updateImageOverlay(
        state.selectedImageId!,
        (overlay) => overlay.copyWith(
          clearAnimationIn: animationIn == 'none',
          animationIn: animationIn == 'none'
              ? null
              : (animationIn ?? overlay.animationIn),
          clearAnimationOut: animationOut == 'none',
          animationOut: animationOut == 'none'
              ? null
              : (animationOut ?? overlay.animationOut),
          animationInDuration:
              animationInDuration ?? overlay.animationInDuration,
          animationOutDuration:
              animationOutDuration ?? overlay.animationOutDuration,
        ),
      );
    } else if (state.selectedVideoOverlayId != null) {
      updateVideoOverlay(
        state.selectedVideoOverlayId!,
        (overlay) => overlay.copyWith(
          clearAnimationIn: animationIn == 'none',
          animationIn: animationIn == 'none'
              ? null
              : (animationIn ?? overlay.animationIn),
          clearAnimationOut: animationOut == 'none',
          animationOut: animationOut == 'none'
              ? null
              : (animationOut ?? overlay.animationOut),
          animationInDuration:
              animationInDuration ?? overlay.animationInDuration,
          animationOutDuration:
              animationOutDuration ?? overlay.animationOutDuration,
        ),
      );
    }
  }

  // --- Audio Track Logic ---
  void addAudioTrack(AudioTrackModel track) {
    saveStateForUndo();
    final trackStart = Duration(
      milliseconds: (track.timelineStart * 1000).round(),
    );
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
      audioTracks: state.audioTracks
          .map((t) => t.id == item.id ? item : t)
          .toList(),
    );
    if (newLaneIndex != null && newLaneIndex != item.laneIndex) {
      final trackStart = Duration(
        milliseconds: (item.timelineStart * 1000).round(),
      );
      final trackEnd = Duration(
        milliseconds: (item.timelineEnd * 1000).round(),
      );
      _swapToLane(item.id, newLaneIndex, trackStart, trackEnd);
    }
  }

  void deleteAudioTrack(String id) {
    saveStateForUndo();
    state = state.copyWith(
      audioTracks: state.audioTracks.where((t) => t.id != id).toList(),
      selectedAudioId: state.selectedAudioId == id
          ? null
          : state.selectedAudioId,
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
  // Transitions overlap their clips, so the timeline is shorter than the sum
  // of the clip durations.
  final videoDuration = videoTimelineDuration(state.segments);

  // Audio and overlays may all outlast the video: playback then continues
  // over the background colour until the last of them ends, instead of the
  // timeline pretending they were cut off where the video stopped.
  var lastEnd = state.audioTracks.fold(
    videoDuration,
    (maxEnd, track) => max(maxEnd, track.timelineEnd),
  );
  for (final text in state.textOverlays) {
    lastEnd = max(lastEnd, text.endTime.inMilliseconds / 1000.0);
  }
  for (final image in state.imageOverlays) {
    lastEnd = max(lastEnd, image.endTime.inMilliseconds / 1000.0);
  }
  for (final video in state.videoOverlays) {
    lastEnd = max(lastEnd, video.timelineEnd.inMilliseconds / 1000.0);
  }
  return lastEnd;
});

final activeSegmentProvider = Provider.autoDispose<VideoSegment?>((ref) {
  final editorState = ref.watch(videoEditorProvider);
  if (editorState.segments.isEmpty) return null;
  if (editorState.segments.length == 1) return editorState.segments.first;
  if (!editorState.isClipSelected || editorState.selectedSegmentId == null)
    return null;
  try {
    return editorState.segments.firstWhere(
      (s) => s.id == editorState.selectedSegmentId,
    );
  } catch (_) {
    return null;
  }
});

final canDeleteSegmentProvider = Provider.autoDispose<bool>((ref) {
  final editorState = ref.watch(videoEditorProvider);
  return !(editorState.segments.length <= 1 ||
      editorState.selectedSegmentId == null);
});

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

/// The preview canvas size to export with, or null when the project is not in
/// a state that can be exported.
///
/// Native export composes the timeline from `VideoEditorState` itself, so the
/// only thing it needs from here is the canvas the overlays were laid out in.
/// This replaced a payload that flattened the whole project into a map for
/// `pro_video_editor`; nothing should reintroduce a second description of the
/// project, which is the timeline contract's whole point.
final exportCanvasSizeProvider = Provider.autoDispose<Size?>((ref) {
  final editorState = ref.watch(videoEditorProvider);
  final videoCanvasSize = ref.watch(videoCanvasSizeProvider);

  if (editorState.sourceVideo == null ||
      editorState.isExporting ||
      videoCanvasSize == null) {
    return null;
  }

  if (editorState.segments.isEmpty) return null;

  return videoCanvasSize;
});
