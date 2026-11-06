import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../video_editor/models/media_asset.dart';
import '../../video_editor/models/video_editor_state.dart';
import '../../video_editor/services/media_import_service.dart';
import '../../video_editor/services/native_timeline_preview_service.dart';
import '../logic/camera_controller.dart';
import '../logic/camera_files.dart';
import '../logic/camera_roll.dart';
import '../logic/reaction.dart';
import '../logic/reaction_session.dart';

/// What a finished take needs to become a reaction.
@immutable
class ReactionRequest {
  const ReactionRequest({
    required this.recording,
    required this.videoPath,
    required this.layout,
    required this.window,
    required this.micHearsVideo,
    required this.toGallery,
  });

  final ReactionRecording recording;
  final String videoPath;
  final ReactionLayout layout;
  final ReactionWindow window;

  /// The video played out loud with no headphones: the microphone has it.
  final bool micHearsVideo;

  /// The reaction may go to the gallery (Android 10 and older ask first).
  final bool toGallery;
}

/// A rendered reaction: its file and how long it runs.
@immutable
class RenderedReaction {
  const RenderedReaction({required this.path, required this.durationMs});

  final String path;
  final int durationMs;
}

/// What making a reaction needs of the phone. The real one is
/// [EngineReactionRenderer]; tests give their own.
abstract class ReactionRenderer {
  /// Each file's length, size and sound; one it cannot read is left out.
  Future<List<MediaAsset>> probe(List<String> paths);

  Future<RenderedReaction> render(
    VideoEditorState project, {
    required void Function(double fraction) onProgress,
    required void Function(String message) onWarning,
  });

  /// Moves [path] into the gallery's album; null where it would not take it.
  Future<SavedShot?> publish(String path);
}

/// Turns a finished take into the reaction: both files measured, the
/// two-layer project built from them ([reactionProject]), rendered by the
/// editor's own engine and moved into the gallery. Null when the take cannot
/// be read; a render that fails throws, for the caller to say so.
Future<RollShot?> makeReaction(
  ReactionRequest request,
  ReactionRenderer renderer, {
  void Function(double fraction)? onProgress,
  void Function(String message)? onWarning,
  DateTime? now,
}) async {
  final recording = request.recording;
  final assets = await renderer.probe([recording.cameraPath, request.videoPath]);
  MediaAsset? find(String path) => assets.where((asset) => asset.path == path).firstOrNull;
  final camera = find(recording.cameraPath);
  final video = find(request.videoPath);
  if (camera == null || video == null || camera.durationSeconds <= 0) return null;

  final at = now ?? DateTime.now();
  final take = ReactionTake(
    id: at.millisecondsSinceEpoch.toString(),
    layout: request.layout,
    window: request.window,
    camera: camera,
    video: video,
    pieces: recording.pieces,
    videoSoundInCamera: request.micHearsVideo,
  );
  final rendered = await renderer.render(
    reactionProject(take),
    onProgress: onProgress ?? (_) {},
    onWarning: onWarning ?? (_) {},
  );
  final saved = request.toGallery ? await renderer.publish(rendered.path) : null;
  return RollShot(
    path: saved?.path ?? rendered.path,
    uri: saved?.uri,
    isVideo: true,
    durationMs: rendered.durationMs,
    takenAt: at,
    reaction: take,
  );
}

/// The reaction rendered as an export is: the native engine composites both
/// layers frame by frame and encodes the file, so the reaction looks exactly
/// as the project would in the editor. The engine is set up for the one
/// render and let go after it — the camera screen runs no editor.
class EngineReactionRenderer implements ReactionRenderer {
  EngineReactionRenderer({required this.camera});

  /// The camera channel, for moving the file into the gallery.
  final CameraBackend camera;

  @override
  Future<List<MediaAsset>> probe(List<String> paths) =>
      MediaImportService().assetsFor([for (final path in paths) XFile(path)]);

  @override
  Future<RenderedReaction> render(
    VideoEditorState project, {
    required void Function(double fraction) onProgress,
    required void Function(String message) onWarning,
  }) async {
    final engine = NativeTimelinePreviewService();
    final events = engine.events.listen((event) {
      if (event.type == 'exportProgress' && event.progress != null) {
        onProgress(event.progress!.clamp(0.0, 1.0).toDouble());
      } else if (event.type == 'exportWarning' && event.message != null) {
        onWarning(event.message!);
      }
    });
    try {
      await engine.initialize();
      final output = await (await CameraFiles.open()).newShotPath('mp4');
      final result = await engine.exportVideo(
        project,
        outputPath: output,
        previewCanvasSize: kReactionFrame,
        frameRate: 30,
        targetShortSidePx: 1080,
        onWarning: onWarning,
      );
      return RenderedReaction(path: result.outputPath, durationMs: (result.durationSeconds * 1000).round());
    } finally {
      await events.cancel();
      try {
        await engine.dispose();
      } catch (_) {
        // Gone already: nothing held.
      }
    }
  }

  @override
  Future<SavedShot?> publish(String path) => camera.publishVideo(path);
}
