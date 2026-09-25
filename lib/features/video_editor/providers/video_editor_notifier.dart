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
import '../logic/animation/keyframe_core.dart';
import '../logic/animation/overlay_keyframes.dart';
import '../logic/canvas_geometry.dart';
import '../logic/animation/clip_keyframes.dart' as kf;
import '../logic/effects/effect_catalog.dart';
import '../logic/filter_presets.dart';
import '../logic/timeline/lane_layout.dart';
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
import '../logic/color/color_adjustments.dart';
import '../logic/mask/clip_mask.dart';
import '../../../core/services/draft_files.dart';
import '../logic/speed/speed_curve.dart';
import '../logic/chroma/chroma_key.dart';

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

/// Ratio a draft reopens with./// The draft's background type, with a photo that is gone read as black.
///
/// The project keeps its own copy of a background photo, but a cleared app
/// folder or a draft moved between devices can still leave the path pointing
/// at nothing. Reopening such a draft as `image` would hand the engine a file
/// it cannot decode on every push; black is what the project had before the
/// photo, and the path is kept so the tile can still offer a re-pick.
EditorBackgroundType _backgroundTypeFromDraft(DraftProject draft) {
  final type = EditorBackgroundType.values.firstWhere(
    (e) => e.name == draft.backgroundType,
    orElse: () => EditorBackgroundType.black,
  );
  if (type != EditorBackgroundType.image) return type;
  final path = draft.backgroundImagePath;
  return path != null && File(path).existsSync()
      ? type
      : EditorBackgroundType.black;
}


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

/// Longest side a frozen frame is decoded at. No export renders a still
/// larger, and a 4K decode for a 3-second hold is memory spent on nothing.
const double kFreezeFrameMaxPx = 1920.0;

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
        backgroundImagePath: state.backgroundImagePath,
        adjustments: state.adjustments,
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

  /// What a reopened draft had to give up, for the screen to say once.
  String? _loadNotice;

  /// The notice from the last [loadDraft], once; null when there was none or
  /// it has already been taken.
  String? takeLoadNotice() {
    final notice = _loadNotice;
    _loadNotice = null;
    return notice;
  }

  /// The draft's own proxies folder, or null for a project with no draft yet
  /// (the service then falls back to the temp directory, as before).
  Future<Directory?> _proxiesDir() async {
    final id = state.draftId;
    if (id == null) return null;
    try {
      return await DraftFiles.proxiesDir(id);
    } catch (_) {
      return null;
    }
  }

  /// Clips whose rendered proxy is gone stop pointing at it.
  ///
  /// The clip itself is fine — it plays from its source — and a reversed clip
  /// keeps its reversal; only the file is dead. Returns how many were healed,
  /// and the ids of reversed clips that need their proxy rendered again.
  ({List<VideoSegment> segments, int healed, List<String> reversedToRender})
      _healMissingProxies(List<VideoSegment> segments) {
    var healed = 0;
    final reversed = <String>[];
    final out = [
      for (final s in segments)
        if (s.overrideVideoPath != null && !DraftFiles.exists(s.overrideVideoPath))
          () {
            healed++;
            if (s.isReversed) reversed.add(s.id);
            return s.copyWith(clearOverrideVideoPath: true);
          }()
        else
          s,
    ];
    return (segments: out, healed: healed, reversedToRender: reversed);
  }

  /// Renders the reverse proxy for a clip that is already marked reversed —
  /// the second half of [toggleReverse], for a reopened draft whose proxy is
  /// gone. Leaves the clip as it is on any failure; it still plays forward
  /// from its source, and export names the problem.
  Future<void> _renderReverseProxy(String segmentId) async {
    final index = state.segments.indexWhere((s) => s.id == segmentId);
    if (index == -1) return;
    final segment = state.segments[index];
    if (!segment.isReversed || segment.overrideVideoPath != null) return;
    final asset = state.assetFor(segment);
    if (asset == null || asset.isImage || asset.path.isEmpty) return;
    try {
      final proxyPath = await _editorService.createReverseProxy(
        inputPath: asset.path,
        sourceStart: segment.sourceStart,
        sourceEnd: segment.sourceEnd,
        outputDir: await _proxiesDir(),
      );
      final currentIndex = state.segments.indexWhere((s) => s.id == segmentId);
      if (currentIndex == -1) {
        await FileUtils.deleteFile(proxyPath);
        return;
      }
      final current = state.segments[currentIndex];
      if (!current.isReversed ||
          current.overrideVideoPath != null ||
          (current.sourceStart - segment.sourceStart).abs() > 0.001 ||
          (current.sourceEnd - segment.sourceEnd).abs() > 0.001) {
        await FileUtils.deleteFile(proxyPath);
        return;
      }
      final updated = [...state.segments];
      updated[currentIndex] = current.copyWith(overrideVideoPath: proxyPath);
      state = state.copyWith(segments: updated);
    } catch (_) {
      // Left as it is; export refuses a reversed clip without a proxy by name.
    }
  }

  /// [rerenderMissingProxies] exists for tests, which have no FFmpeg.
  Future<void> loadDraft(
    DraftProject draft, {
    bool rerenderMissingProxies = true,
  }) async {
    final assets = _restoreAssets(draft);
    final healed = _healMissingProxies(_restoreSegments(draft, assets));
    final segments = healed.segments;
    _loadNotice = healed.healed == 0
        ? null
        : 'Some cached files for this project were missing and have been '
            'reset. Reversed clips are being re-rendered.';

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
      backgroundType: _backgroundTypeFromDraft(draft),
      backgroundColor: Color(draft.backgroundColorValue),
      backgroundBlurIntensity: draft.backgroundBlurIntensity,
      backgroundImagePath: draft.backgroundImagePath,
      adjustments: draft.adjustments,
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

    // A draft saved before the lane rules held can hold stacked overlays —
    // duplicates used to land exactly on top of their original — or gaps.
    _applyLanes(normalizeLanes(_laneSpans));

    if (rerenderMissingProxies) {
      for (final id in healed.reversedToRender) {
        unawaited(_renderReverseProxy(id));
      }
    }

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
    // Whatever ✕ could have restored belonged to the tool this replaces. A
    // tool can close without ✓ or ✕ (selecting audio clears it directly), so
    // the record is dropped on every open, not only on close.
    _toolEntry = null;
    state = state.copyWith(
      activeToolId: toolId,
      clearActiveToolId: toolId == null,
    );
  }

  /// What ✕ puts back: the selection as it stood when a slider tool opened,
  /// and how deep the undo stack was then. See [openRevertibleTool].
  ({
    int undoDepth,
    VideoSegment? segment,
    TextOverlayModel? text,
    ImageOverlayModel? image,
    VideoOverlayModel? video,
  })? _toolEntry;

  /// Opens [toolId] remembering the selected clip or overlay as it is, so ✕
  /// can put it back ([discardActiveTool]).
  ///
  /// For the Volume and Opacity panels, which — except a clip's Volume —
  /// write the model as the slider moves: the engine has to hear the value
  /// being dragged, and for overlays and clip opacity the model is how it
  /// hears it. Without a record, ✕ closed the panel and kept the change.
  void openRevertibleTool(String toolId) {
    setActiveTool(toolId);
    _toolEntry = (
      undoDepth: _undoStack.length,
      segment: state.selectedSegment,
      text: _selectedTextOverlay,
      image: _selectedImageOverlay,
      video: _selectedVideoOverlay,
    );
  }

  /// The ✕: closes the tool and discards what it did.
  ///
  /// **The target is put back, not the editor.** Restoring a snapshot would
  /// also move the playhead to where the drag began and undo anything else
  /// that happened meanwhile; replacing the one clip or overlay by id leaves
  /// all of that alone. The undo entries the drag pushed go too — they would
  /// undo to the value just restored, and an undo that undoes nothing is a
  /// lie — while those from before the tool opened stay. A tool opened
  /// without a record only closes.
  void discardActiveTool() {
    final entry = _toolEntry;
    if (entry != null) {
      final segment = entry.segment;
      final text = entry.text;
      final image = entry.image;
      final video = entry.video;
      if (_undoStack.length > entry.undoDepth) {
        _undoStack.removeRange(entry.undoDepth, _undoStack.length);
      }
      state = state.copyWith(
        segments: segment == null
            ? null
            : [
                for (final s in state.segments)
                  if (s.id == segment.id) segment else s,
              ],
        textOverlays: text == null
            ? null
            : [
                for (final o in state.textOverlays)
                  if (o.id == text.id) text else o,
              ],
        imageOverlays: image == null
            ? null
            : [
                for (final o in state.imageOverlays)
                  if (o.id == image.id) image else o,
              ],
        videoOverlays: video == null
            ? null
            : [
                for (final o in state.videoOverlays)
                  if (o.id == video.id) video else o,
              ],
        canUndo: _undoStack.isNotEmpty,
      );
    }
    closeActiveTool();
  }

  TextOverlayModel? get _selectedTextOverlay {
    final id = state.selectedTextId;
    if (id == null) return null;
    for (final o in state.textOverlays) {
      if (o.id == id) return o;
    }
    return null;
  }

  ImageOverlayModel? get _selectedImageOverlay {
    final id = state.selectedImageId;
    if (id == null) return null;
    for (final o in state.imageOverlays) {
      if (o.id == id) return o;
    }
    return null;
  }

  VideoOverlayModel? get _selectedVideoOverlay {
    final id = state.selectedVideoOverlayId;
    if (id == null) return null;
    for (final o in state.videoOverlays) {
      if (o.id == id) return o;
    }
    return null;
  }

  /// Closes the open tool, keeping what it did — the ✓, and every dismissal
  /// that is not the ✕ ([discardActiveTool]).
  void closeActiveTool() {
    _toolEntry = null;
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
    final cut = _cutSegments(state.segments, timelineSeconds);
    final updatedSegments = cut.segments;
    final rightSegment = updatedSegments[cut.rightIndex];
    saveStateForUndo();
    state = state.copyWith(
      segments: updatedSegments,
      selectedSegmentId: rightSegment.id,
      isClipSelected: true,
      trimRange: RangeValues(rightSegment.sourceStart, rightSegment.sourceEnd),
    );
  }

  /// The segment list with the clip under [timelineSeconds] cut in two, and
  /// where the right half landed.
  ///
  /// Pure: reads nothing from state and writes nothing. The blade and the
  /// freeze both build on it, so a cut is one piece of arithmetic however it
  /// is reached. Throws, with the message the user sees, where a cut is
  /// impossible.
  ({List<VideoSegment> segments, int rightIndex}) _cutSegments(
    List<VideoSegment> segments,
    double timelineSeconds,
  ) {
    // Where to cut is [_clipCutPoint]'s decision alone — the Split tool and
    // the freeze ask it too, so none of them can offer a cut this refuses.
    final point = _clipCutPoint(segments, timelineSeconds);
    if (point == null) {
      throw Exception(
        segments.isEmpty || segmentIndexAt(timelineSeconds, segments) < 0
            ? 'There is nothing to split.'
            : 'Move the playhead further into the clip to split it.',
      );
    }

    final index = point.index;
    final segment = segments[index];
    final offsetIntoClip = point.offsetIntoClip;

    final sourceSplit = segment.sourceAtOffset(offsetIntoClip);

    // A reversed clip runs backwards through its source, so the half that plays
    // first is the one nearer the source *end*.
    final leftRange = segment.isReversed
        ? (start: sourceSplit, end: segment.sourceEnd)
        : (start: segment.sourceStart, end: sourceSplit);
    final rightRange = segment.isReversed
        ? (start: segment.sourceStart, end: sourceSplit)
        : (start: sourceSplit, end: segment.sourceEnd);

    // A curve is a function of the clip's source range, so each half takes
    // its own rescaled piece and both read the same speed at the seam. The
    // cut fraction is in play order, like the curve's x.
    final sourceSpan = segment.sourceEnd - segment.sourceStart;
    final cutFraction = sourceSpan <= 0
        ? 0.5
        : ((segment.isReversed
                    ? segment.sourceEnd - sourceSplit
                    : sourceSplit - segment.sourceStart) /
                sourceSpan)
            .clamp(0.0, 1.0)
            .toDouble();
    final curveHalves = segment.speedCurve?.splitAt(cutFraction);

    final leftSegment = segment.copyWith(
      sourceStart: leftRange.start,
      sourceEnd: leftRange.end,
      speedCurve: curveHalves?.left,
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
      speedCurve: curveHalves?.right,
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
      // Built by hand rather than through `copyWith`, so every clip-owned
      // field has to be named here — a rotated clip lost its angle on the
      // right of a cut until this line existed.
      canvasRotation: segment.canvasRotation,
      // Same footage either side of the cut, so the same crop and mirror.
      cropRect: segment.cropRect,
      flipHorizontal: segment.flipHorizontal,
      flipVertical: segment.flipVertical,
      opacity: segment.opacity,
      // Same footage, same grade, same window.
      adjustments: segment.adjustments,
      mask: segment.mask,
      // Same footage either side of the cut, so the same key.
      chromaKey: segment.chromaKey,
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

    return (segments: updatedSegments, rightIndex: index + 1);
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
    final params = clipParams(original);
    final split = splitKeyframesIn(params, cut, isLeft: isLeft);
    // Unchanged means no keyframes or a degenerate cut: the half keeps what
    // the split gave it.
    if (identical(split, params)) return half;
    return withClipParams(half, split);
  }

  void splitAtPlayhead(double timelineSeconds) {
    splitAtPosition(timelineSeconds);
  }

  /// Holds the frame under the playhead as a photo clip of
  /// [kDefaultPhotoDurationSeconds], inserted where the playhead is.
  ///
  /// The frame is pulled from the **source** at the clip's own time there —
  /// `sourceAtOffset`, the mapping playback and the filmstrip use, so a
  /// trimmed, sped or reversed clip freezes the frame that was on screen —
  /// written into the project folder like a cover, and added as an image
  /// asset. The still inherits the clip's look and placement **as resolved at
  /// that instant**: a keyframed zoom mid-flight freezes at the size it had,
  /// as flat base values, because a still has no travel to keyframe.
  ///
  /// Where the playhead is far enough from both ends the clip is cut and the
  /// still goes between the halves — one undo step for the cut and the insert
  /// together. Nearer an end than a clip may be short, it goes before or after
  /// instead of forcing a sliver. A photo has no frame to freeze; that throws,
  /// like the blade does, with the message the user sees.
  ///
  /// [frameProvider] and [destinationDir] exist for tests, which have neither
  /// a platform to decode a frame nor a documents folder.
  Future<void> freezeFrameAtPlayhead({
    Future<Uint8List?> Function(String path, int timeMs, int width, int height)?
        frameProvider,
    Directory? destinationDir,
  }) async {
    final segments = state.segments;
    final position = state.currentPlaybackPosition;
    final index = segmentIndexAt(position, segments);
    if (index < 0) {
      throw Exception('Move the playhead onto a clip to freeze a frame.');
    }
    final segment = segments[index];
    final asset = state.assetFor(segment);
    if (asset == null) {
      throw Exception('This clip has no source to freeze.');
    }
    if (asset.isImage) {
      throw Exception('This clip is already a still.');
    }
    final draftId = state.draftId;
    if (draftId == null) {
      throw Exception('Save the project before freezing a frame.');
    }

    final starts = segmentTimelineStarts(segments);
    final offset = position - starts[index];
    final sourceSeconds = segment.sourceAtOffset(offset);
    final progress = segment.clipProgressAt(position, starts[index]);

    // Full source size, capped so a 4K clip does not decode a 4K still —
    // no export renders one larger than this.
    final scale = asset.width > kFreezeFrameMaxPx
        ? kFreezeFrameMaxPx / asset.width
        : 1.0;
    final width = (asset.width * scale).round();
    final height = (asset.height * scale).round();
    final provide = frameProvider ??
        (path, timeMs, w, h) => VideoThumbnailService.instance
            .frameAtSize(path: path, timeMs: timeMs, width: w, height: h);
    final bytes = await provide(
      asset.path,
      (sourceSeconds * 1000).round(),
      width,
      height,
    );
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Could not read a frame here.');
    }

    final dir = destinationDir ?? await getApplicationDocumentsDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final file = File('${dir.path}/freeze_${draftId}_$stamp.jpg');
    await file.writeAsBytes(bytes);

    final frameAsset = MediaAsset(
      id: 'freeze_$stamp',
      path: file.path,
      type: MediaAssetType.image,
      durationSeconds: 0,
      width: asset.width,
      height: asset.height,
      hasAudio: false,
    );

    // The still, wearing the clip's state at this instant as flat values.
    AnimatableDouble flat(ClipProperty p) =>
        AnimatableDouble(baseValue: clipParameter(segment, p).resolveAt(progress));
    final still = VideoSegment(
      id: 'clip_freeze_$stamp',
      assetId: frameAsset.id,
      sourceStart: 0,
      sourceEnd: kDefaultPhotoDurationSeconds,
      filterId: segment.filterId,
      filterIntensity: segment.filterIntensity,
      effectId: segment.effectId,
      effectIntensity: flat(ClipProperty.effectIntensity),
      canvasScale: flat(ClipProperty.canvasScale),
      canvasOffsetX: flat(ClipProperty.canvasOffsetX),
      canvasOffsetY: flat(ClipProperty.canvasOffsetY),
      canvasRotation: flat(ClipProperty.canvasRotation),
      opacity: flat(ClipProperty.opacity),
      cropRect: segment.cropRect,
      flipHorizontal: segment.flipHorizontal,
      flipVertical: segment.flipVertical,
      adjustments: segment.adjustments,
    );

    // Cut where a cut is possible; otherwise sit the still beside the clip
    // at the nearer end rather than force a sliver the blade would refuse.
    // The blade's own rule, asked rather than restated.
    final canCut = _clipCutPoint(segments, position) != null;
    final List<VideoSegment> updated;
    if (canCut) {
      final cut = _cutSegments(segments, position);
      updated = [...cut.segments]..insert(cut.rightIndex, still);
    } else {
      final nearStart = offset < segment.duration - offset;
      updated = [...segments]..insert(nearStart ? index : index + 1, still);
    }

    saveStateForUndo();
    state = state.copyWith(
      assets: [...state.assets, frameAsset],
      segments: updated,
      selectedSegmentId: still.id,
      isClipSelected: true,
    );
  }

  /// A pinch/drag on the canvas is starting to reposition the selected clip.
  ///
  /// The undo snapshot is taken here, once, so the whole gesture undoes as one
  /// step rather than as sixty.
  /// The selected clip's Adjust. [takeUndoSnapshot] false for the live frames
  /// of a drag whose start already took one.
  void setClipAdjustments(
    ColorAdjustments adjustments, {
    bool takeUndoSnapshot = true,
  }) {
    final targetId = state.selectedSegmentId;
    if (targetId == null) return;
    if (takeUndoSnapshot) saveStateForUndo();
    state = state.copyWith(
      segments: [
        for (final s in state.segments)
          if (s.id == targetId) s.copyWith(adjustments: adjustments) else s,
      ],
    );
  }

  /// The project's Adjust, composed into the canvas look after the filter.
  void setProjectAdjustments(
    ColorAdjustments adjustments, {
    bool takeUndoSnapshot = true,
  }) {
    if (takeUndoSnapshot) saveStateForUndo();
    state = state.copyWith(adjustments: adjustments);
  }

  /// The selected clip's mask. [takeUndoSnapshot] false for the live frames of
  /// a drag whose start already took one.
  /// The mask on whatever is selected — a clip, a photo overlay or a video
  /// overlay — or [ClipMask.none] with nothing selected.
  ///
  /// One editor serves all three, so there is no second mask UI to drift from
  /// the first. A clip wins when several are somehow selected at once, since
  /// that is the selection the canvas is drawing handles for.
  ClipMask get maskOnSelection {
    final segment = state.selectedSegment;
    if (segment != null) return segment.mask;
    final imageId = state.selectedImageId;
    if (imageId != null) {
      for (final o in state.imageOverlays) {
        if (o.id == imageId) return o.mask;
      }
    }
    final videoId = state.selectedVideoOverlayId;
    if (videoId != null) {
      for (final o in state.videoOverlays) {
        if (o.id == videoId) return o.mask;
      }
    }
    return ClipMask.none;
  }

  /// Writes [mask] to whatever is selected. With nothing selected it does
  /// nothing — and takes no snapshot either, because an undo entry that undoes
  /// nothing is a lie.
  void setMaskOnSelection(ClipMask mask, {bool takeUndoSnapshot = true}) {
    if (state.selectedSegmentId != null) {
      setClipMask(mask, takeUndoSnapshot: takeUndoSnapshot);
      return;
    }

    final imageId = state.selectedImageId;
    if (imageId != null) {
      if (takeUndoSnapshot) saveStateForUndo();
      state = state.copyWith(
        imageOverlays: [
          for (final o in state.imageOverlays)
            if (o.id == imageId) o.copyWith(mask: mask) else o,
        ],
      );
      return;
    }

    final videoId = state.selectedVideoOverlayId;
    if (videoId != null) {
      if (takeUndoSnapshot) saveStateForUndo();
      state = state.copyWith(
        videoOverlays: [
          for (final o in state.videoOverlays)
            if (o.id == videoId) o.copyWith(mask: mask) else o,
        ],
      );
    }
  }

  void setClipMask(ClipMask mask, {bool takeUndoSnapshot = true}) {
    final targetId = state.selectedSegmentId;
    if (targetId == null) return;
    if (takeUndoSnapshot) saveStateForUndo();
    state = state.copyWith(
      segments: [
        for (final s in state.segments)
          if (s.id == targetId) s.copyWith(mask: mask) else s,
      ],
    );
  }

  /// Swaps the media under the selected clip for [asset], keeping the edit.
  ///
  /// Everything the user did to the clip is about the *slot* on the timeline,
  /// not the file — speed, placement and its keyframes (clip-relative, so they
  /// still mean the same instants), crop, mirror, opacity, adjustments,
  /// filter, effect, transition — and survives. The trim survives where it
  /// still fits; a shorter file pulls the end in and slides the start back to
  /// keep as much of the clip's length as the file allows. A photo has no
  /// source length and is given the clip's on-screen length at 1×. What cannot
  /// survive is what belonged to the old file: a proxy rendered from it, and a
  /// reversal that depended on that proxy. One undo step; the file joins the
  /// asset pool once, and the old asset stays for anything else that uses it.
  void replaceClipAsset(MediaAsset asset) {
    final segment = state.selectedSegment;
    if (segment == null) return;

    final double start;
    final double end;
    final double speed;
    if (asset.isImage) {
      start = 0.0;
      end = segment.duration;
      speed = 1.0;
    } else {
      final length = segment.sourceEnd - segment.sourceStart;
      final maxEnd = asset.durationSeconds;
      end = segment.sourceEnd <= maxEnd ? segment.sourceEnd : maxEnd;
      start = (end - length).clamp(0.0, end - kMinClipDurationSeconds)
          .clamp(0.0, segment.sourceStart)
          .toDouble();
      speed = segment.speed;
    }

    final replaced = segment.copyWith(
      assetId: asset.id,
      sourceStart: start,
      sourceEnd: end,
      speed: speed,
      isReversed: false,
      clearOverrideVideoPath: true,
    );

    saveStateForUndo();
    state = state.copyWith(
      assets: state.assets.any((a) => a.id == asset.id)
          ? state.assets
          : [...state.assets, asset],
      segments: [
        for (final s in state.segments) s.id == segment.id ? replaced : s,
      ],
    );
  }

  /// Copies the selected clip's placement — scale, position and rotation with
  /// their keyframes, and the mirror — onto every other clip, as one undo
  /// step. Returns how many clips changed.
  ///
  /// **A copy, not a mode.** A live all-clips mode on a ruler drag would write
  /// a keyframe into every clip at the same *relative* instant per frame,
  /// which nobody means; set one clip up, then copy it.
  int applyTransformToAllClips() => _copyToOtherClips(
        (source, target) => target.copyWith(
          canvasScale: source.canvasScale,
          canvasOffsetX: source.canvasOffsetX,
          canvasOffsetY: source.canvasOffsetY,
          canvasRotation: source.canvasRotation,
          flipHorizontal: source.flipHorizontal,
          flipVertical: source.flipVertical,
        ),
      );

  /// Copies the selected clip's own crop onto every other clip. One undo step.
  int applyCropToAllClips() => _copyToOtherClips(
        (source, target) => target.copyWith(cropRect: source.cropRect),
      );

  /// Copies the selected clip's effect and intensity (keyframes included) onto
  /// every other clip; an unaffected clip clears the others. One undo step.
  int applyEffectToAllClips() => _copyToOtherClips(
        (source, target) => source.effectId == null
            ? target.copyWith(
                clearEffectId: true,
                effectIntensity: source.effectIntensity,
              )
            : target.copyWith(
                effectId: source.effectId,
                effectIntensity: source.effectIntensity,
              ),
      );

  /// Applies [copy] from the selected clip to every other clip, snapshotting
  /// once. Zero, and no snapshot, with nothing selected or nothing else to
  /// write — an undo entry that undoes nothing is a lie to the user.
  int _copyToOtherClips(
    VideoSegment Function(VideoSegment source, VideoSegment target) copy,
  ) {
    final source = state.selectedSegment;
    if (source == null || state.segments.length < 2) return 0;
    saveStateForUndo();
    final updated = [
      for (final s in state.segments) s.id == source.id ? s : copy(source, s),
    ];
    state = state.copyWith(segments: updated);
    return updated.length - 1;
  }

  /// Mirrors the selected clip across one axis: left for right when
  /// [horizontal], top for bottom otherwise. One undo step; nothing with no
  /// clip selected. A toggle, not a drag, so it commits through state and the
  /// engine hears it on the next push — no override channel needed.
  void toggleClipFlip({required bool horizontal}) {
    final targetId = state.selectedSegmentId;
    if (targetId == null) return;
    saveStateForUndo();
    state = state.copyWith(
      segments: [
        for (final s in state.segments)
          if (s.id == targetId)
            horizontal
                ? s.copyWith(flipHorizontal: !s.flipHorizontal)
                : s.copyWith(flipVertical: !s.flipVertical)
          else
            s,
      ],
    );
  }

  void beginClipCanvasTransform() {
    if (state.selectedSegmentId == null) return;
    saveStateForUndo();
    // **Pause first.** A ruler drag or a pinch writes at the playhead every
    // frame, and on a keyframed clip a moving playhead turns one drag into a
    // trail of diamonds. The screen reacts to `isPlaying` and holds the engine.
    state = state.copyWith(isClipTransformActive: true, isPlaying: false);
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
              // A mirrored clip did not come mirrored.
              flipHorizontal: false,
              flipVertical: false,
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
      outputDir: await _proxiesDir(),
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
      outputDir: await _proxiesDir(),
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
    // A flat speed and a curve are exclusive: dragging the slider is the
    // user choosing a fixed rate over the ramp.
    updatedSegments[index] = updatedSegments[index].copyWith(
      speed: state.previewSpeed!,
      clearSpeedCurve: true,
    );
    state = state.copyWith(segments: updatedSegments, clearPreviewSpeed: true);
  }

  /// Sets the selected clip's chroma key. One undo step; [live] skips the
  /// snapshot for the per-frame half of a slider drag.
  /// The key on whatever is selected — a clip, a photo overlay or a video
  /// overlay — so there is one chroma editor, not three.
  ///
  /// A clip wins if one is somehow selected alongside an overlay, the same
  /// precedence [maskOnSelection] uses.
  ChromaKey get chromaKeyOnSelection {
    final segment = state.selectedSegment;
    if (segment != null) return segment.chromaKey;
    final imageId = state.selectedImageId;
    if (imageId != null) {
      for (final o in state.imageOverlays) {
        if (o.id == imageId) return o.chromaKey;
      }
    }
    final videoId = state.selectedVideoOverlayId;
    if (videoId != null) {
      for (final o in state.videoOverlays) {
        if (o.id == videoId) return o.chromaKey;
      }
    }
    return ChromaKey.none;
  }

  /// Writes [key] to whatever is selected. With nothing selected it does
  /// nothing — and takes no snapshot either, because an undo entry that undoes
  /// nothing is a lie.
  ///
  /// [live] is a slider frame: no snapshot, since
  /// [beginChromaKeyOnSelection] took one when the drag started.
  void setChromaKeyOnSelection(ChromaKey key, {bool live = false}) {
    if (state.selectedSegmentId != null) {
      setClipChromaKey(key, live: live);
      return;
    }

    final imageId = state.selectedImageId;
    if (imageId != null) {
      final current = chromaKeyOnSelection;
      if (current == key) return;
      if (!live) saveStateForUndo();
      state = state.copyWith(
        imageOverlays: [
          for (final o in state.imageOverlays)
            if (o.id == imageId) o.copyWith(chromaKey: key) else o,
        ],
      );
      return;
    }

    final videoId = state.selectedVideoOverlayId;
    if (videoId != null) {
      final current = chromaKeyOnSelection;
      if (current == key) return;
      if (!live) saveStateForUndo();
      state = state.copyWith(
        videoOverlays: [
          for (final o in state.videoOverlays)
            if (o.id == videoId) o.copyWith(chromaKey: key) else o,
        ],
      );
    }
  }

  /// The undo snapshot for a whole chroma drag, on whatever is selected.
  void beginChromaKeyOnSelection() {
    if (state.selectedSegmentId == null &&
        state.selectedImageId == null &&
        state.selectedVideoOverlayId == null) {
      return;
    }
    saveStateForUndo();
  }

  void setClipChromaKey(ChromaKey key, {bool live = false}) {
    final targetId = state.selectedSegmentId;
    if (targetId == null) return;
    final index = state.segments.indexWhere((s) => s.id == targetId);
    if (index == -1) return;
    if (state.segments[index].chromaKey == key) return;
    if (!live) saveStateForUndo();
    final updated = [...state.segments];
    updated[index] = updated[index].copyWith(chromaKey: key);
    state = state.copyWith(segments: updated);
  }

  /// The undo snapshot for a whole chroma slider drag.
  void beginClipChromaKey() {
    if (state.selectedSegmentId == null) return;
    saveStateForUndo();
  }

  /// Takes the undo snapshot for a whole curve drag, once, and pauses.
  ///
  /// The same rule as [beginClipCanvasTransform]: a drag writes per frame, and
  /// going through [setClipSpeedCurve] would push an undo entry for every one
  /// of them. Pausing matters more here than elsewhere — reshaping the curve
  /// changes the clip's length under a running playhead.
  void beginClipSpeedCurve() {
    if (state.selectedSegmentId == null) return;
    saveStateForUndo();
    if (state.isPlaying) {
      state = state.copyWith(isPlaying: false);
    }
  }

  /// Writes the curve with no snapshot — the per-frame half of a drag that
  /// [beginClipSpeedCurve] opened.
  void setClipSpeedCurveLive(SpeedCurve curve) {
    final targetId = state.selectedSegmentId;
    if (targetId == null) return;
    state = state.copyWith(
      segments: [
        for (final s in state.segments)
          if (s.id == targetId)
            s.copyWith(speedCurve: curve, speed: 1.0)
          else
            s,
      ],
      clearPreviewSpeed: true,
    );
  }

  /// Gives the selected clip a speed curve, or removes it with null. One undo
  /// step. With a curve the flat speed is reset to 1, so the curve alone
  /// decides the clip's rate and length; without one the clip keeps whatever
  /// flat speed it had.
  void setClipSpeedCurve(SpeedCurve? curve) {
    final targetId = state.selectedSegmentId;
    if (targetId == null) return;
    final index = state.segments.indexWhere((s) => s.id == targetId);
    if (index == -1) return;
    final current = state.segments[index];
    if (current.speedCurve == curve) return;
    saveStateForUndo();
    final updated = [...state.segments];
    updated[index] = curve == null
        ? current.copyWith(clearSpeedCurve: true)
        : current.copyWith(speedCurve: curve, speed: 1.0);
    state = state.copyWith(segments: updated, clearPreviewSpeed: true);
  }

  void setSelectedRatio(EditorCropRatio ratio) {
    state = state.copyWith(selectedRatio: ratio);
  }

  /// Writes the selected clip's own crop, live — the canvas calls this per
  /// drag frame, having taken the undo snapshot once at the drag's start.
  void setClipCropRect(Rect rect) {
    final targetId = state.selectedSegmentId;
    if (targetId == null) return;
    state = state.copyWith(
      segments: [
        for (final segment in state.segments)
          if (segment.id == targetId)
            segment.copyWith(cropRect: clampNormalizedRect(rect))
          else
            segment,
      ],
    );
  }

  /// Puts the selected clip back to its whole frame, undoably.
  void resetClipCropRect() {
    final targetId = state.selectedSegmentId;
    if (targetId == null) return;
    saveStateForUndo();
    setClipCropRect(kFullFrameRect);
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

  /// Picks a solid background colour.
  ///
  /// Type and colour move together as **one undo step**: the picker has no
  /// separate switch any more (black is a tile like any other), so a tap is
  /// one decision and undo should take back exactly one.
  void setBackground(Color color) {
    saveStateForUndo();
    state = state.copyWith(
      backgroundType: EditorBackgroundType.color,
      backgroundColor: color,
    );
  }

  /// Uses the photo at [path] as the background: type and path together, one
  /// undo step. The path should already be the project's own copy — see
  /// [importBackgroundImage].
  void setBackgroundImage(String path) {
    saveStateForUndo();
    state = state.copyWith(
      backgroundType: EditorBackgroundType.image,
      backgroundImagePath: path,
    );
  }

  /// The clip blurred behind itself as the letterbox fill. One undo step.
  void setBackgroundBlur() {
    if (state.backgroundType == EditorBackgroundType.blur) return;
    saveStateForUndo();
    state = state.copyWith(backgroundType: EditorBackgroundType.blur);
  }

  /// Switches back to the photo already chosen, without another pick. A no-op
  /// with none chosen, and not an undo step then — nothing changed.
  void useBackgroundImage() {
    if (state.backgroundImagePath == null) return;
    if (state.backgroundType == EditorBackgroundType.image) return;
    saveStateForUndo();
    state = state.copyWith(backgroundType: EditorBackgroundType.image);
  }

  /// Copies a picked photo into the project's folder and uses it.
  ///
  /// The picker hands back a cache path the OS may reclaim, so the project
  /// keeps its own copy, named by draft and time like a cover is — a fresh
  /// name per pick, because `FileImage` caches by path and overwriting one
  /// file would keep showing the old photo everywhere it had been drawn. The
  /// previous copy is deleted. False, with nothing changed, when there is no
  /// draft to keep it in or the copy fails; the sheet says so.
  Future<bool> importBackgroundImage(
    String sourcePath, {
    Directory? destinationDir,
  }) async {
    final draftId = state.draftId;
    if (draftId == null) return false;
    try {
      final source = File(sourcePath);
      if (!await source.exists()) return false;
      final dir = destinationDir ?? await getApplicationDocumentsDirectory();
      final name = sourcePath.split(RegExp(r'[\\/]')).last;
      final dot = name.lastIndexOf('.');
      final extension = dot > 0 ? name.substring(dot) : '.jpg';
      final copy = await source.copy(
        '${dir.path}/bg_${draftId}_${DateTime.now().millisecondsSinceEpoch}$extension',
      );

      final previous = state.backgroundImagePath;
      setBackgroundImage(copy.path);
      if (previous != null && previous.contains('bg_$draftId')) {
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
    // The rule itself is the shared core's (`writeKeyframedValueIn`), so a
    // clip and an overlay decide base-or-keyframe identically.
    return withClipParams(
      segment,
      writeKeyframedValueIn(
        clipParams(segment),
        property,
        value,
        playheadProgress: playheadProgress,
        tolerance: keyframeHitToleranceFor(segment),
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

  /// Places a diamond at the playhead on the keyframe target — the selected
  /// overlay, else the selected clip — pinning every property at the value it
  /// already has there, so the picture does not change.
  ///
  /// Does nothing, and takes no undo step, with the playhead off the target or
  /// already on a diamond. The button shows minus there, so that second case is
  /// a double tap landing before the rebuild — and an undo entry that undoes
  /// nothing is a lie.
  void addKeyframeAtPlayhead() {
    if (state.keyframeTargetProgress == null || state.playheadIsOnKeyframe) {
      return;
    }
    if (_editSelectedOverlayKeyframes(
      (params, progress, _) => captureKeyframeIn(params, progress),
    )) {
      return;
    }
    _editSelectedClip(
      (segment, progress) =>
          progress == null ? segment : captureKeyframe(segment, progress),
    );
  }

  /// Removes the diamond under the playhead from every property of the
  /// keyframe target. Nothing under the playhead is nothing to remove, and no
  /// undo step.
  void removeKeyframeAtPlayhead() {
    if (!state.playheadIsOnKeyframe) return;
    if (_editSelectedOverlayKeyframes(removeKeyframeIn)) return;
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
    if (_editSelectedOverlayKeyframes(
      (params, progress, tolerance) =>
          setKeyframeCurveIn(params, progress, tolerance, curve),
    )) {
      return;
    }
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


  /// One frame of a diamond drag: slides the diamond at [from] to [to] and
  /// moves the playhead with it, so the diamond stays the selected one and the
  /// canvas shows the instant being placed. **No undo snapshot** — the drag's
  /// start takes the one for the whole gesture. Returns where the diamond now
  /// is, or null when the move was refused (nothing near [from], or another
  /// diamond at the destination), so the caller keeps dragging from where it
  /// really is.
  double? moveKeyframeLive(double from, double to) {
    final dest = to.clamp(0.0, 1.0).toDouble();
    final ref = state.keyframeOverlay;
    if (ref != null) {
      final moved = moveKeyframeIn(
        ref.motion.params,
        from,
        dest,
        overlayKeyframeTolerance(ref),
      );
      if (moved == null) return null;
      _replaceOverlayMotion(ref, OverlayMotion.fromParams(moved));
      seekToKeyframe(dest);
      return dest;
    }
    final segment = state.selectedSegment;
    if (segment == null) return null;
    final moved = moveKeyframe(segment, from, dest, keyframeHitToleranceFor(segment));
    if (identical(moved, segment)) return null;
    state = state.copyWith(
      segments: [
        for (final s in state.segments) s.id == segment.id ? moved : s,
      ],
    );
    seekToKeyframe(dest);
    return dest;
  }

  /// Moves the playhead onto a diamond.
  ///
  /// What makes tapping a diamond and then tapping minus remove it — the
  /// plus/minus flip reads the playhead, so the playhead has to actually be on
  /// the diamond. Not an undoable edit: it moves the playhead, nothing else.
  void seekToKeyframe(double progress) {
    final ref = state.keyframeOverlay;
    if (ref != null) {
      final start = ref.start.inMicroseconds / 1e6;
      final span = (ref.end - ref.start).inMicroseconds / 1e6;
      updatePlaybackPosition(
        start + progress.clamp(0.0, 1.0).toDouble() * (span > 0 ? span : 0.0),
      );
      return;
    }
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

  // --- Lanes ---
  //
  // Text, photos, video overlays and audio share one set of lanes. The rules
  // live in `lane_layout.dart` as pure functions over spans; these methods
  // read the four lists into spans and write the answers back.

  List<LaneSpan> get _laneSpans => laneSpansOf(
        texts: state.textOverlays,
        images: state.imageOverlays,
        videos: state.videoOverlays,
        audios: state.audioTracks,
      );

  static Duration _duration(double seconds) =>
      Duration(microseconds: (seconds * 1e6).round());

  /// Writes new lanes by id across the four lists, replacing only a list that
  /// actually changed — an untouched list keeps its identity, which is how
  /// the overlay sync knows there is nothing to push.
  void _applyLanes(Map<String, int> lanes) {
    if (lanes.isEmpty) return;
    bool changes(String id, int lane) =>
        lanes.containsKey(id) && lanes[id] != lane;
    final texts = state.textOverlays;
    final images = state.imageOverlays;
    final videos = state.videoOverlays;
    final audios = state.audioTracks;
    state = state.copyWith(
      textOverlays: texts.any((x) => changes(x.id, x.laneIndex))
          ? [
              for (final x in texts)
                lanes.containsKey(x.id)
                    ? x.copyWith(laneIndex: lanes[x.id])
                    : x,
            ]
          : null,
      imageOverlays: images.any((x) => changes(x.id, x.laneIndex))
          ? [
              for (final x in images)
                lanes.containsKey(x.id)
                    ? x.copyWith(laneIndex: lanes[x.id])
                    : x,
            ]
          : null,
      videoOverlays: videos.any((x) => changes(x.id, x.laneIndex))
          ? [
              for (final x in videos)
                lanes.containsKey(x.id)
                    ? x.copyWith(laneIndex: lanes[x.id])
                    : x,
            ]
          : null,
      audioTracks: audios.any((x) => changes(x.id, x.laneIndex))
          ? [
              for (final x in audios)
                lanes.containsKey(x.id)
                    ? x.copyWith(laneIndex: lanes[x.id])
                    : x,
            ]
          : null,
    );
  }

  /// Closes any lane left empty — by a move, a delete — keeping everything's
  /// order relative to everything else, so paint order does not change.
  void _compactLanes() => _applyLanes(compactLanes(_laneSpans));

  /// The undo entry [beginTimelineGesture] pushed, and the redo stack it
  /// cleared, in case the gesture turns out to have changed nothing.
  VideoEditorState? _gestureBase;
  List<VideoEditorState> _gestureRedo = const [];

  /// A finger went down on a timeline drag or trim: **one** undo entry for
  /// the whole gesture, taken before anything moves.
  ///
  /// Every frame used to go through `updateTextOverlay` and its siblings,
  /// which snapshot each call, so Undo walked a drag back a frame at a time;
  /// and the only snapshot a clip trim had was taken *after* it, so Undo
  /// restored the trimmed state and the trim was permanent.
  void beginTimelineGesture() {
    _gestureRedo = [..._redoStack];
    saveStateForUndo();
    _gestureBase = _undoStack.last;
  }

  /// The finger lifted: close any lane the gesture emptied, and withdraw the
  /// undo entry if nothing changed — a long press that moved nothing is not
  /// an edit, and an undo that undoes nothing is a lie.
  void endTimelineGesture() {
    _compactLanes();
    final base = _gestureBase;
    _gestureBase = null;
    if (base == null ||
        _undoStack.isEmpty ||
        !identical(_undoStack.last, base)) {
      return;
    }
    final unchanged = identical(base.segments, state.segments) &&
        base.trimRange == state.trimRange &&
        identical(base.textOverlays, state.textOverlays) &&
        identical(base.imageOverlays, state.imageOverlays) &&
        identical(base.videoOverlays, state.videoOverlays) &&
        identical(base.audioTracks, state.audioTracks);
    if (!unchanged) return;
    _undoStack.removeLast();
    _redoStack
      ..clear()
      ..addAll(_gestureRedo);
    state = state.copyWith(
      canUndo: _undoStack.isNotEmpty,
      canRedo: _redoStack.isNotEmpty,
    );
  }

  /// One frame of a timeline move: [id] to [start] on [targetLane], keeping
  /// its length. No undo snapshot — see [beginTimelineGesture].
  ///
  /// Where it lands is [resolveMove]'s decision: the target lane if free, a
  /// trade of lanes with what it was dropped onto (the layer reorder), or the
  /// nearest free lane below — never an overlap, and never more than one new
  /// lane past the last.
  void moveLaneItem(
    String id, {
    required double start,
    required int targetLane,
  }) {
    final spans = _laneSpans;
    final me = spans.where((x) => x.id == id).firstOrNull;
    if (me == null) return;
    final from = start < 0 ? 0.0 : start;
    final to = from + (me.end - me.start);
    final lanes = resolveMove(spans, id, from, to, targetLane);

    final begin = _duration(from);
    final end = _duration(to);
    state = state.copyWith(
      textOverlays: state.textOverlays.any((x) => x.id == id)
          ? [
              for (final x in state.textOverlays)
                x.id == id ? x.copyWith(startTime: begin, endTime: end) : x,
            ]
          : null,
      imageOverlays: state.imageOverlays.any((x) => x.id == id)
          ? [
              for (final x in state.imageOverlays)
                x.id == id ? x.copyWith(startTime: begin, endTime: end) : x,
            ]
          : null,
      videoOverlays: state.videoOverlays.any((x) => x.id == id)
          ? [
              for (final x in state.videoOverlays)
                x.id == id
                    ? x.copyWith(timelineStart: begin, timelineEnd: end)
                    : x,
            ]
          : null,
      audioTracks: state.audioTracks.any((x) => x.id == id)
          ? [
              for (final x in state.audioTracks)
                x.id == id ? x.copyWith(timelineStart: from) : x,
            ]
          : null,
    );
    _applyLanes(lanes);
  }

  /// One frame of a text, photo or video overlay trim. No undo snapshot.
  ///
  /// Each edge stops at the neighbour on its lane ([clampTrim]). A video
  /// overlay's edges also stop at its footage, and its **left edge cuts into
  /// the footage**: it used to move only the timeline start, so trimming the
  /// head left the footage beginning at its first frame, just later.
  void trimLaneItem(String id, {required double start, required double end}) {
    final spans = _laneSpans;
    final me = spans.where((x) => x.id == id).firstOrNull;
    if (me == null) return;
    final clamped = clampTrim(spans, id, start, end);
    var from = clamped.start;
    var to = clamped.end;

    final video = state.videoOverlays.where((x) => x.id == id).firstOrNull;
    if (video != null) {
      var sourceStart = video.sourceStart;
      if (video.speed > 0 && video.sourceEnd > video.sourceStart) {
        // The timeline instants the footage's first and last frames would
        // play at: an edge may move within them, no further.
        final footageZero = me.start - video.sourceStart / video.speed;
        final footageEnd = footageZero + video.sourceEnd / video.speed;
        if ((from - me.start).abs() > 1e-9) {
          if (from < footageZero) from = footageZero;
          sourceStart = (from - footageZero) * video.speed;
        }
        if ((to - me.end).abs() > 1e-9 && to > footageEnd) to = footageEnd;
      }
      state = state.copyWith(videoOverlays: [
        for (final x in state.videoOverlays)
          x.id == id
              ? x.copyWith(
                  timelineStart: _duration(from),
                  timelineEnd: _duration(to),
                  sourceStart: sourceStart,
                )
              : x,
      ]);
      return;
    }

    final begin = _duration(from);
    final finish = _duration(to);
    if (state.textOverlays.any((x) => x.id == id)) {
      state = state.copyWith(textOverlays: [
        for (final x in state.textOverlays)
          x.id == id ? x.copyWith(startTime: begin, endTime: finish) : x,
      ]);
    } else if (state.imageOverlays.any((x) => x.id == id)) {
      state = state.copyWith(imageOverlays: [
        for (final x in state.imageOverlays)
          x.id == id ? x.copyWith(startTime: begin, endTime: finish) : x,
      ]);
    }
  }

  /// One frame of an audio trim. No undo snapshot. The edges stop at the
  /// lane's neighbours, and the source range follows whatever was clamped,
  /// so the sound under the clip does not slide.
  void trimAudioTrackLive(
    String id, {
    required double timelineStart,
    required double sourceStart,
    required double sourceEnd,
  }) {
    final requestedEnd = timelineStart + (sourceEnd - sourceStart);
    final clamped = clampTrim(_laneSpans, id, timelineStart, requestedEnd);
    state = state.copyWith(audioTracks: [
      for (final x in state.audioTracks)
        x.id == id
            ? x.copyWith(
                timelineStart: clamped.start,
                sourceStart: sourceStart + (clamped.start - timelineStart),
                sourceEnd: sourceEnd - (requestedEnd - clamped.end),
              )
            : x,
    ]);
  }

  /// A copy of an audio track straight after it, on its own lane when that
  /// is free there — music continuing — or the nearest free lane below.
  void duplicateAudioTrack(String id) {
    final track = state.audioTracks.where((a) => a.id == id).firstOrNull;
    if (track == null) return;
    saveStateForUndo();
    final start = track.timelineEnd;
    final lane = firstFreeLane(
      _laneSpans,
      start,
      start + track.trimmedDuration,
      fromLane: track.laneIndex,
    );
    final copy = track.copyWith(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      timelineStart: start,
      laneIndex: lane,
    );
    state = state.copyWith(audioTracks: [...state.audioTracks, copy]);
    selectAudioTrack(copy.id);
  }

  /// The lane a copy of an overlay spanning [start]–[end] on [lane] goes to:
  /// the nearest one at or below it that is free at that time.
  ///
  /// Duplicates used to keep the original's lane and times, so the copy sat
  /// exactly on top of it — invisible on the timeline and on the canvas.
  int _laneForCopy(Duration start, Duration end, int lane) => firstFreeLane(
        _laneSpans,
        start.inMicroseconds / 1e6,
        end.inMicroseconds / 1e6,
        fromLane: lane,
      );

  /// The first lane free for [start]–[end], for something new.
  int _laneForNew(Duration start, Duration end) => firstFreeLane(
        _laneSpans,
        start.inMicroseconds / 1e6,
        end.inMicroseconds / 1e6,
      );

  /// Adds [overlay] and selects it, **as the only selection**, on its menu.
  ///
  /// The Text tool and the emoji picker both arrive here. It used to leave any
  /// other selection standing, so an image selected beforehand survived beside
  /// the new text — and the delete handler, which checks text first, would act
  /// on a thing the toolbar was not about. The same shape as [addImageOverlay].
  void addTextOverlay(TextOverlayModel overlay) {
    saveStateForUndo();
    final lane = _laneForNew(overlay.startTime, overlay.endTime);
    final placedOverlay = overlay.copyWith(laneIndex: lane);
    state = state.copyWith(
      textOverlays: [...state.textOverlays, placedOverlay],
      selectedTextId: placedOverlay.id,
      clearSelectedImageId: true,
      clearSelectedVideoOverlayId: true,
      clearSelectedSegmentId: true,
      isClipSelected: false,
      currentMenuId: 'text_overlay',
    );
  }

  /// Selects a text, and opens **its** menu — or returns to root on null.
  ///
  /// It used to send the editor to the root menu either way, so a selected
  /// text showed the tools for making a project and none for the text; its
  /// whole editor was reachable only by tapping the already-selected text.
  /// Image and video overlays have always had a menu of their own.
  void selectTextOverlay(String? overlayId) {
    state = state.copyWith(
      selectedTextId: overlayId,
      clearSelectedTextId: overlayId == null,
      clearSelectedImageId: overlayId != null,
      clearSelectedVideoOverlayId: overlayId != null,
      clearSelectedSegmentId: overlayId != null,
      isClipSelected: overlayId == null ? state.isClipSelected : false,
      currentMenuId: overlayId != null ? 'text_overlay' : 'root',
    );
  }

  void updateTextOverlay(
    String id,
    TextOverlayModel Function(TextOverlayModel) update,
  ) {
    final index = state.textOverlays.indexWhere((text) => text.id == id);
    if (index == -1) return;
    saveStateForUndo();
    final updated = [...state.textOverlays];
    updated[index] = update(updated[index]);
    state = state.copyWith(textOverlays: updated);
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

  /// Deletes a text, and leaves the text menu if it was the selected one.
  ///
  /// **The menu has to be left here, not by the caller.** The canvas frame's ✕
  /// calls this and nothing else; if only [selectTextOverlay] returned to root,
  /// that path would strand the text menu on screen with nothing selected and
  /// every tool on it a silent no-op.
  void deleteTextOverlay(String id) {
    saveStateForUndo();
    final wasSelected = state.selectedTextId == id;
    state = state.copyWith(
      textOverlays: state.textOverlays.where((text) => text.id != id).toList(),
      clearSelectedTextId: wasSelected,
      currentMenuId: wasSelected ? 'root' : null,
    );
    // A lane this emptied closes, so nothing below it is left hanging.
    _compactLanes();
  }

  void duplicateTextOverlay(String id) {
    final source = state.textOverlays.where((text) => text.id == id);
    if (source.isEmpty) return;
    saveStateForUndo();
    final overlay = source.first;
    final duplicated =
        overlay.withMotion(_duplicateMotion(overlay.motion)).copyWith(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              laneIndex: _laneForCopy(
                overlay.startTime,
                overlay.endTime,
                overlay.laneIndex,
              ),
            );
    state = state.copyWith(
      textOverlays: [...state.textOverlays, duplicated],
      selectedTextId: duplicated.id,
      clearSelectedImageId: true,
      clearSelectedVideoOverlayId: true,
      clearSelectedSegmentId: true,
      isClipSelected: false,
      currentMenuId: 'text_overlay',
    );
  }

  void addImageOverlay(ImageOverlayModel overlay) {
    saveStateForUndo();
    final lane = _laneForNew(overlay.startTime, overlay.endTime);
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
    ImageOverlayModel Function(ImageOverlayModel) update,
  ) {
    final index = state.imageOverlays.indexWhere((img) => img.id == id);
    if (index == -1) return;
    saveStateForUndo();
    final updated = [...state.imageOverlays];
    updated[index] = update(updated[index]);
    state = state.copyWith(imageOverlays: updated);
  }

  /// One frame of a canvas gesture on a photo overlay: no undo snapshot.
  ///
  /// The gesture calls [saveStateForUndo] once when it starts and this per
  /// pointer move, so a drag is one undo step. Going through
  /// [updateImageOverlay] snapshotted the whole editor state sixty times a
  /// second — work the drag paid for on every frame — and left an Undo that
  /// walked the move back a pixel at a time. Same rule as
  /// [updateTextOverlayLive].
  void updateImageOverlayLive(
    String id,
    ImageOverlayModel Function(ImageOverlayModel) update,
  ) {
    final index = state.imageOverlays.indexWhere((img) => img.id == id);
    if (index == -1) return;
    final updated = [...state.imageOverlays];
    updated[index] = update(updated[index]);
    state = state.copyWith(imageOverlays: updated);
  }

  void deleteImageOverlay(String id) {
    saveStateForUndo();
    state = state.copyWith(
      imageOverlays: state.imageOverlays.where((img) => img.id != id).toList(),
      clearSelectedImageId: state.selectedImageId == id,
    );
    _compactLanes();
  }

  void duplicateImageOverlay(String id) {
    final source = state.imageOverlays.where((img) => img.id == id);
    if (source.isEmpty) return;
    saveStateForUndo();
    final overlay = source.first;
    final duplicated =
        overlay.withMotion(_duplicateMotion(overlay.motion)).copyWith(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              laneIndex: _laneForCopy(
                overlay.startTime,
                overlay.endTime,
                overlay.laneIndex,
              ),
            );
    state = state.copyWith(
      imageOverlays: [...state.imageOverlays, duplicated],
      selectedImageId: duplicated.id,
      clearSelectedTextId: true,
      clearSelectedVideoOverlayId: true,
      clearSelectedSegmentId: true,
      isClipSelected: false,
    );
  }

  // --- Video Overlay Logic ---
  void addVideoOverlay(VideoOverlayModel overlay) {
    saveStateForUndo();
    final lane = _laneForNew(overlay.timelineStart, overlay.timelineEnd);
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
    VideoOverlayModel Function(VideoOverlayModel) update,
  ) {
    final index = state.videoOverlays.indexWhere((vid) => vid.id == id);
    if (index == -1) return;
    saveStateForUndo();
    final updated = [...state.videoOverlays];
    updated[index] = update(updated[index]);
    state = state.copyWith(videoOverlays: updated);
  }

  /// One frame of a canvas gesture on a video overlay: no undo snapshot.
  /// See [updateImageOverlayLive].
  void updateVideoOverlayLive(
    String id,
    VideoOverlayModel Function(VideoOverlayModel) update,
  ) {
    final index = state.videoOverlays.indexWhere((vid) => vid.id == id);
    if (index == -1) return;
    final updated = [...state.videoOverlays];
    updated[index] = update(updated[index]);
    state = state.copyWith(videoOverlays: updated);
  }

  void deleteVideoOverlay(String id) {
    saveStateForUndo();
    state = state.copyWith(
      videoOverlays: state.videoOverlays.where((vid) => vid.id != id).toList(),
      clearSelectedVideoOverlayId: state.selectedVideoOverlayId == id,
    );
    _compactLanes();
  }

  void duplicateVideoOverlay(String id) {
    final source = state.videoOverlays.where((vid) => vid.id == id);
    if (source.isEmpty) return;
    saveStateForUndo();
    final overlay = source.first;
    final duplicated =
        overlay.withMotion(_duplicateMotion(overlay.motion)).copyWith(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              laneIndex: _laneForCopy(
                overlay.timelineStart,
                overlay.timelineEnd,
                overlay.laneIndex,
              ),
            );
    state = state.copyWith(
      videoOverlays: [...state.videoOverlays, duplicated],
      selectedVideoOverlayId: duplicated.id,
      clearSelectedTextId: true,
      clearSelectedImageId: true,
      clearSelectedSegmentId: true,
      isClipSelected: false,
    );
  }

  /// Cuts the selected video overlay in two at the playhead, as one undo step.
  ///
  /// Unreachable until the Split gate learned about overlays, and wrong in
  /// two ways that being unreachable had hidden:
  ///
  /// - **Both halves kept both animations**, so the overlay would exit before
  ///   the cut and enter again after it. The entrance now stays on the left
  ///   half and the exit on the right.
  /// - **The source was cut at the bare timeline offset, ignoring `speed`.**
  ///   The engine plays an overlay at `sourceStart + offset × speed`
  ///   (`NativeTimelineOverlay.sourceAt`), so at 2× the right half started
  ///   early in the footage and replayed frames the left half had shown. The
  ///   cut now mirrors that mapping — clamp included — so every instant shows
  ///   the frame it showed before the split.
  ///
  /// Keyframes are overlay-relative, so each half's are rescaled into its own
  /// 0..1 after a diamond is pinned at the cut ([splitKeyframesIn]) — the
  /// motion plays through the seam exactly as it did before.
  ///
  /// Refused where [_overlaySplitPoint] refuses, the rule the Split tool is
  /// offered by. With no overlay selected it does nothing.
  void splitVideoOverlay(double globalPlayhead) {
    final id = state.selectedVideoOverlayId;
    if (id == null) return;
    final index = state.videoOverlays.indexWhere((v) => v.id == id);
    if (index == -1) return;
    final videoOverlay = state.videoOverlays[index];

    final cut = _overlaySplitPoint(
      videoOverlay.timelineStart,
      videoOverlay.timelineEnd,
      globalPlayhead,
    );
    if (cut == null) {
      throw Exception(
        'Move the playhead further into the overlay to split it.',
      );
    }

    final offsetSeconds =
        (cut - videoOverlay.timelineStart).inMicroseconds / 1e6;
    var splitSourceTime =
        videoOverlay.sourceStart + offsetSeconds * videoOverlay.speed;
    if (videoOverlay.sourceEnd > videoOverlay.sourceStart &&
        splitSourceTime > videoOverlay.sourceEnd) {
      splitSourceTime = videoOverlay.sourceEnd;
    }

    // Where the cut falls in the original's progress. `_overlaySplitPoint`
    // keeps it strictly inside, so neither half is degenerate.
    final spanUs =
        (videoOverlay.timelineEnd - videoOverlay.timelineStart).inMicroseconds;
    final cutProgress = spanUs <= 0
        ? 0.0
        : (cut - videoOverlay.timelineStart).inMicroseconds / spanUs;
    VideoOverlayModel withHalfMotion(
      VideoOverlayModel half, {
      required bool isLeft,
    }) {
      if (videoOverlay.keyframes.isEmpty) return half;
      return half.withMotion(OverlayMotion.fromParams(splitKeyframesIn(
        videoOverlay.motion.params,
        cutProgress,
        isLeft: isLeft,
      )));
    }

    saveStateForUndo();

    final firstHalf = withHalfMotion(
      videoOverlay.copyWith(
        timelineEnd: cut,
        sourceEnd: splitSourceTime,
        clearAnimationOut: true,
      ),
      isLeft: true,
    );
    final secondHalf = withHalfMotion(
      videoOverlay.copyWith(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        timelineStart: cut,
        sourceStart: splitSourceTime,
        clearAnimationIn: true,
      ),
      isLeft: false,
    );

    final updatedOverlays = [...state.videoOverlays];
    updatedOverlays[index] = firstHalf;
    updatedOverlays.insert(index + 1, secondHalf);

    state = state.copyWith(
      videoOverlays: updatedOverlays,
      selectedVideoOverlayId: secondHalf.id,
    );
  }

  /// Starts a live edit of the selected overlay's placement: pauses playback
  /// and takes the **one** undo snapshot the whole gesture shares.
  ///
  /// **Pause first**, for the reason [beginClipCanvasTransform] does: a live
  /// write lands at the playhead, and on a keyframed overlay a moving playhead
  /// turns one drag into a trail of diamonds. Clearing `isPlaying` is
  /// synchronous, and while it is false the screen drops the engine's position
  /// events and the tail ticker stands still — so every frame of the gesture
  /// resolves the same instant. With nothing selected it does nothing, and
  /// takes no snapshot either: an undo entry that undoes nothing is a lie.
  void beginOverlayEdit() {
    if (state.keyframeOverlay == null) return;
    saveStateForUndo();
    if (state.isPlaying) state = state.copyWith(isPlaying: false);
  }

  /// One frame of a live edit of the selected overlay's placement, with **no
  /// undo snapshot** — [beginOverlayEdit] took the gesture's one.
  ///
  /// Every given property goes through the edit rule on **one** params map,
  /// in [OverlayProperty] order ([writeKeyframedValueIn]): base values on an
  /// overlay with no diamonds, the diamond under the playhead on one with
  /// them, and between diamonds exactly one new diamond — the first write
  /// captures it and the rest find it. A property left null is not written,
  /// so a gesture with no angle to give cannot un-rotate an overlay.
  ///
  /// [id], when given, names the overlay the gesture began on; the write is
  /// dropped if that is no longer the selected one. A second finger can select
  /// another overlay mid-drag, and the first gesture's callback may fire once
  /// more before its layer rebuilds — without this it would move the overlay
  /// the user just picked to wherever the first was being dragged.
  ///
  /// A value that is not finite is skipped rather than written: `jsonEncode`
  /// refuses NaN and infinity, so one bad gesture frame in a keyframe would
  /// make every later draft save fail. Opacity is held to 0..1.
  void setOverlayMotionLive({
    String? id,
    Offset? position,
    double? scale,
    double? rotation,
    double? opacity,
  }) {
    final ref = state.keyframeOverlay;
    if (ref == null || (id != null && id != ref.id)) return;
    final progress = overlayProgressOn(ref, state.currentPlaybackPosition);
    final tolerance = overlayKeyframeTolerance(ref);
    final before = ref.motion.params;
    var params = before;
    void write(OverlayProperty property, double? value) {
      if (value == null || !value.isFinite) return;
      params = writeKeyframedValueIn(
        params,
        property,
        value,
        playheadProgress: progress,
        tolerance: tolerance,
      );
    }

    write(OverlayProperty.x, position?.dx);
    write(OverlayProperty.y, position?.dy);
    write(OverlayProperty.scale, scale);
    write(OverlayProperty.rotation, rotation);
    write(OverlayProperty.opacity, opacity?.clamp(0.0, 1.0).toDouble());
    if (identical(params, before)) return;
    _replaceOverlayMotion(ref, OverlayMotion.fromParams(params));
  }

  /// Writes [motion] into the overlay [ref] names, with no undo snapshot.
  void _replaceOverlayMotion(KeyframeOverlayRef ref, OverlayMotion motion) {
    switch (ref.kind) {
      case OverlayKind.text:
        updateTextOverlayLive(ref.id, (o) => o.withMotion(motion));
      case OverlayKind.image:
        updateImageOverlayLive(ref.id, (o) => o.withMotion(motion));
      case OverlayKind.video:
        updateVideoOverlayLive(ref.id, (o) => o.withMotion(motion));
    }
  }

  /// The overlay half of every keyframe command — [_editSelectedClip]'s twin.
  ///
  /// Returns false when no overlay is the keyframe target, so the command
  /// falls through to the clip; true otherwise, **even when nothing changed**,
  /// so a command meant for an overlay can never land on a clip. The playhead
  /// is resolved once, and an edit that hands its input back unchanged (the
  /// core's refusals) touches nothing and takes no undo snapshot.
  bool _editSelectedOverlayKeyframes(
    KeyframeParams<OverlayProperty> Function(
      KeyframeParams<OverlayProperty> params,
      double progress,
      double tolerance,
    ) edit,
  ) {
    final ref = state.keyframeOverlay;
    if (ref == null) return false;
    final progress = overlayProgressOn(ref, state.currentPlaybackPosition);
    if (progress == null) return true;
    final params = ref.motion.params;
    final edited = edit(params, progress, overlayKeyframeTolerance(ref));
    if (identical(edited, params)) return true;
    saveStateForUndo();
    _replaceOverlayMotion(ref, OverlayMotion.fromParams(edited));
    return true;
  }

  /// Sets the selected overlay's opacity — a text's included — through the
  /// edit rule, so on a keyframed overlay the Opacity slider keyframes itself
  /// like every other control.
  ///
  /// [takeUndoSnapshot] false is the per-frame half of a slider drag, whose
  /// start takes the one snapshot — every frame used to snapshot, and Undo
  /// walked the drag back a step at a time. That start should be
  /// [beginOverlayEdit], which also pauses, for the trail-of-diamonds reason.
  void setOverlayOpacity(double opacity, {bool takeUndoSnapshot = true}) {
    if (state.keyframeOverlay == null) return;
    if (takeUndoSnapshot) saveStateForUndo();
    setOverlayMotionLive(opacity: opacity);
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
    final lane = _laneForNew(trackStart, trackEnd);
    final placedTrack = track.copyWith(laneIndex: lane);
    state = state.copyWith(
      audioTracks: [...state.audioTracks, placedTrack],
      selectedAudioId: placedTrack.id,
    );
  }

  void updateAudioTrack(AudioTrackModel updatedTrack) {
    saveStateForUndo();
    state = state.copyWith(
      audioTracks: state.audioTracks
          .map((t) => t.id == updatedTrack.id ? updatedTrack : t)
          .toList(),
    );
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
    _compactLanes();
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

/// Where the blade at [timelineSeconds] would cut [segments]: the clip under
/// it and how far into that clip — or null where the cut is refused.
///
/// **The one rule for cutting a clip**, asked by the cut itself
/// ([VideoEditorNotifier._cutSegments]), by the freeze (which sits its still
/// beside the clip instead where this refuses) and by
/// [isSplitToolEnabledProvider] — so the Split tool is offered exactly where
/// the blade cuts. The gate used to restate the rule and got it wrong,
/// comparing the playhead's *timeline* seconds against the clip's *source*
/// range, which hid Split mid-clip on any clip whose source does not start
/// where it sits on the timeline.
///
/// The playhead decides which clip is cut, not the selection: the blade cuts
/// where the user can see it. The minimum is measured in timeline seconds, the
/// gap the user can actually see; the same test in source seconds would
/// tighten or loosen with the clip's speed.
({int index, double offsetIntoClip})? _clipCutPoint(
  List<VideoSegment> segments,
  double timelineSeconds,
) {
  if (segments.isEmpty) return null;
  final index = segmentIndexAt(timelineSeconds, segments);
  if (index < 0) return null;
  final offsetIntoClip =
      timelineSeconds - segmentTimelineStarts(segments)[index];
  if (offsetIntoClip < kMinClipDurationSeconds ||
      segments[index].duration - offsetIntoClip < kMinClipDurationSeconds) {
    return null;
  }
  return (index: index, offsetIntoClip: offsetIntoClip);
}

/// Where an overlay spanning [start]–[end] may be cut at [playheadSeconds]:
/// the cut instant, or null where it may not.
///
/// **One rule, two consumers**: [VideoEditorNotifier.splitVideoOverlay] cuts
/// here and [isSplitToolEnabledProvider] offers the tool from it, so the
/// Split button shows exactly where a tap succeeds — never a dead tap, never
/// a missing tool. Each half must last at least [kMinClipDurationSeconds],
/// the timeline's own trim minimum, so a split cannot make a piece the trim
/// handles could not. The cut lands on a whole millisecond, the precision a
/// draft stores, so both halves save to the same instant and still abut.
/// A duplicate's motion: the original's nudged 20px right and down, so the
/// user can see there are two — through the **whole** path.
///
/// On a keyframed overlay the x and y tracks decide where it is drawn, not the
/// base, so nudging only the base (all a duplicate did before keyframes) would
/// put the copy exactly on top of the original at every instant. Every
/// keyframe on those tracks moves with the base, keeping its curve.
OverlayMotion _duplicateMotion(OverlayMotion motion) {
  const nudge = Offset(20, 20);
  AnimatableDouble shifted(AnimatableDouble p, double by) =>
      AnimatableDouble.sorted(
        baseValue: p.baseValue + by,
        envelope: p.envelope,
        keyframes: [
          for (final k in p.keyframes)
            Keyframe(
              progress: k.progress,
              value: k.value + by,
              interpolation: k.interpolation,
            ),
        ],
      );
  final params = motion.params;
  return OverlayMotion.fromParams({
    ...params,
    OverlayProperty.x: shifted(params[OverlayProperty.x]!, nudge.dx),
    OverlayProperty.y: shifted(params[OverlayProperty.y]!, nudge.dy),
  });
}

Duration? _overlaySplitPoint(
  Duration start,
  Duration end,
  double playheadSeconds,
) {
  final cut = Duration(milliseconds: (playheadSeconds * 1000).round());
  final minimum = Duration(
    milliseconds: (kMinClipDurationSeconds * 1000).round(),
  );
  if (cut - start < minimum || end - cut < minimum) return null;
  return cut;
}

/// Whether the Split tool shows for what is selected.
///
/// **Every branch asks the rule its split cuts with**, never a restatement,
/// so the button shows exactly where a tap succeeds. This gate used to carry
/// a rule of its own and was wrong twice: it knew only clips, requiring
/// `isClipSelected` — which selecting a video overlay clears, so its Split
/// could never show — and for clips it compared the playhead's
/// timeline seconds against the clip's *source* range.
final isSplitToolEnabledProvider = Provider.autoDispose<bool>((ref) {
  final editorState = ref.watch(videoEditorProvider);
  final playhead = editorState.currentPlaybackPosition;

  // A selected overlay splits **itself**, not the clip under it.
  final videoId = editorState.selectedVideoOverlayId;
  if (videoId != null) {
    final video = editorState.videoOverlays
        .where((overlay) => overlay.id == videoId)
        .firstOrNull;
    return video != null &&
        _overlaySplitPoint(video.timelineStart, video.timelineEnd, playhead) !=
            null;
  }

  // Split is a clip-menu tool: offered with a clip selected, wherever the
  // blade would cut — which is the clip under the playhead.
  return editorState.isClipSelected &&
      _clipCutPoint(editorState.segments, playhead) != null;
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
