import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/camera/logic/camera_controller.dart';
import 'package:slimshotai/features/camera/logic/reaction.dart';
import 'package:slimshotai/features/camera/logic/reaction_session.dart';
import 'package:slimshotai/features/camera/services/reaction_maker.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';

class FakeRenderer implements ReactionRenderer {
  final rendered = <VideoEditorState>[];
  final published = <String>[];
  bool unreadableTake = false;
  bool refusePublish = false;
  bool failRender = false;

  @override
  Future<List<MediaAsset>> probe(List<String> paths) async => [
        for (final path in paths)
          if (!(unreadableTake && path.contains('/camera/')))
            MediaAsset(
              id: 'asset_$path',
              path: path,
              type: MediaAssetType.video,
              durationSeconds: path.contains('/camera/') ? 6 : 40,
              width: path.contains('/camera/') ? 1080 : 1920,
              height: path.contains('/camera/') ? 1920 : 1080,
              hasAudio: true,
            ),
      ];

  @override
  Future<RenderedReaction> render(
    VideoEditorState project, {
    required void Function(double fraction) onProgress,
    required void Function(String message) onWarning,
  }) async {
    if (failRender) throw StateError('no encoder');
    rendered.add(project);
    onProgress(0.5);
    onProgress(1);
    return const RenderedReaction(path: '/camera/VID_out.mp4', durationMs: 5900);
  }

  @override
  Future<SavedShot?> publish(String path) async {
    published.add(path);
    if (refusePublish) return null;
    return const SavedShot(path: '/gallery/SlimShot_VID_out.mp4', uri: 'content://media/video/9');
  }
}

ReactionRequest _request({bool toGallery = true}) => ReactionRequest(
      recording: const ReactionRecording(
        cameraPath: '/camera/VID_take.mp4',
        durationMs: 6000,
        pieces: [ReactionPiece(startMs: 0, endMs: 6000, offsetMs: -100)],
      ),
      videoPath: '/picked/clip.mp4',
      layout: ReactionLayout.topBottom,
      window: ReactionWindow.initial,
      micHearsVideo: true,
      toGallery: toGallery,
    );

void main() {
  late FakeRenderer renderer;

  setUp(() => renderer = FakeRenderer());

  test('a take becomes the reaction, rendered from its project and saved to the gallery', () async {
    final progress = <double>[];
    final shot = await makeReaction(
      _request(),
      renderer,
      onProgress: progress.add,
      now: DateTime(2026, 11, 6, 10),
    );
    expect(renderer.rendered.single.segments.single.assetId, 'asset_/camera/VID_take.mp4');
    expect(renderer.rendered.single.videoOverlays.single.videoPath, '/picked/clip.mp4');
    expect(renderer.rendered.single.videoOverlays.single.isMuted, isTrue);
    expect(progress, [0.5, 1]);
    expect(shot!.path, '/gallery/SlimShot_VID_out.mp4');
    expect(shot.uri, 'content://media/video/9');
    expect(shot.isVideo, isTrue);
    expect(shot.durationMs, 5900);
    expect(shot.reaction!.layout, ReactionLayout.topBottom);
    expect(shot.reaction!.pieces.single.offsetMs, -100);
    expect(shot.reaction!.camera.path, '/camera/VID_take.mp4');
  });

  test('with no gallery the reaction stays in SlimShot', () async {
    final shot = await makeReaction(_request(toGallery: false), renderer);
    expect(renderer.published, isEmpty);
    expect(shot!.path, '/camera/VID_out.mp4');
    expect(shot.uri, isNull);
  });

  test('a gallery that will not take it leaves it in SlimShot', () async {
    renderer.refusePublish = true;
    final shot = await makeReaction(_request(), renderer);
    expect(shot!.path, '/camera/VID_out.mp4');
    expect(shot.uri, isNull);
  });

  test('a take that cannot be read makes nothing', () async {
    renderer.unreadableTake = true;
    expect(await makeReaction(_request(), renderer), isNull);
    expect(renderer.rendered, isEmpty);
  });

  test('a render that fails says so to the caller', () async {
    renderer.failRender = true;
    await expectLater(makeReaction(_request(), renderer), throwsStateError);
  });
}
