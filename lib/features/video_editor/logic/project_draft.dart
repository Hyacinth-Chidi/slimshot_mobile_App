import '../../../core/models/draft_project.dart';
import '../models/video_editor_state.dart';
import 'background_blur.dart';
import 'timeline/project_end.dart';

/// [state] as the draft it saves to — the one mapping, read by the editor's
/// own save and by anything that makes a project outside the editor (a REACT
/// take opened for editing), so a project cannot be saved two ways.
///
/// [thumbnailPath] stands in for the state's own where the caller has just
/// written one. Null when the project has no file to be a draft of.
DraftProject? draftProjectFrom(
  VideoEditorState state, {
  String? thumbnailPath,
  DateTime? now,
}) {
  final source = state.sourceVideo;
  final id = state.draftId;
  if (source == null || id == null) return null;
  final at = now ?? DateTime.now();
  return DraftProject(
    id: id,
    sourceVideoPath: source.path,
    // Real creation time would need to be tracked, but this is fine for
    // updating.
    createdAt: at,
    updatedAt: at,
    durationSeconds: state.durationSeconds,
    // The length the editor shows (`totalEditedDurationProvider`), for the
    // home screen widget.
    editedSeconds: projectEndSeconds(
      segments: state.segments,
      audios: state.audioTracks,
      texts: state.textOverlays,
      images: state.imageOverlays,
      videos: state.videoOverlays,
      effects: state.effectBars,
    ),
    thumbnailPath: thumbnailPath ?? state.thumbnailPath,
    assets: state.assets.map((e) => e.toJson()).toList(),
    segments: state.segments.map((e) => e.toJson()).toList(),
    textOverlays: state.textOverlays.map((e) => e.toJson()).toList(),
    imageOverlays: state.imageOverlays.map((e) => e.toJson()).toList(),
    videoOverlays: state.videoOverlays.map((e) => e.toJson()).toList(),
    audioTracks: state.audioTracks.map((e) => e.toJson()).toList(),
    effectBars: state.effectBars.map((e) => e.toJson()).toList(),
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
    backgroundColorValue: state.backgroundColor.toARGB32(),
    // Absent at the default, so a project that never touched the slider
    // saves what it always did.
    backgroundBlurStrength:
        state.backgroundBlurStrength == kDefaultBackgroundBlurStrength ? null : state.backgroundBlurStrength,
    backgroundImagePath: state.backgroundImagePath,
    adjustments: state.adjustments,
    isMuted: state.isMuted,
    captionSettings: state.captionSettings?.toJson(),
  );
}
