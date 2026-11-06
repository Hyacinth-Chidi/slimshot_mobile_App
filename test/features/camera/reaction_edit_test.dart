import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:slimshotai/core/models/draft_project.dart';
import 'package:slimshotai/features/camera/logic/camera_roll.dart';
import 'package:slimshotai/features/camera/logic/reaction.dart';
import 'package:slimshotai/features/camera/screens/camera_screen.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';

const _take = ReactionTake(
  id: '42',
  layout: ReactionLayout.topBottom,
  window: ReactionWindow.initial,
  camera: MediaAsset(
    id: 'c',
    path: '/camera/VID_take.mp4',
    type: MediaAssetType.video,
    durationSeconds: 8,
    width: 1080,
    height: 1920,
    hasAudio: true,
  ),
  video: MediaAsset(
    id: 'v',
    path: '/picked/clip.mp4',
    type: MediaAssetType.video,
    durationSeconds: 30,
    width: 1920,
    height: 1080,
    hasAudio: true,
  ),
  pieces: [ReactionPiece(startMs: 0, endMs: 8000, offsetMs: 0)],
  videoSoundInCamera: true,
);

const _reaction = RollShot(
  path: '/gallery/SlimShot_VID_r.mp4',
  isVideo: true,
  durationMs: 8000,
  takenAt: null,
  reaction: _take,
);

void main() {
  Future<bool> everything(String path) async => true;
  Future<DraftProject?> none(String id) async => null;

  test('a reaction opens as its two layers', () async {
    final extra = await editorExtraFor(_reaction, exists: everything, savedDraft: none);
    expect(extra, isA<DraftProject>());
    final draft = extra as DraftProject;
    expect(draft.id, 'react_42');
    expect(draft.assets.single['path'], '/camera/VID_take.mp4');
    expect(draft.videoOverlays.single['videoPath'], '/picked/clip.mp4');
    expect(draft.videoOverlays.single['refWidth'], 360);
  });

  test('a reaction edited before opens where the edit left it', () async {
    final asked = <String>[];
    DraftProject? saved;
    final first = await editorExtraFor(_reaction, exists: everything, savedDraft: none) as DraftProject;
    saved = first;
    final extra = await editorExtraFor(_reaction, exists: everything, savedDraft: (id) async {
      asked.add(id);
      return saved;
    });
    expect(asked, ['react_42']);
    expect(identical(extra, saved), isTrue);
  });

  test('a reaction whose take or video is gone opens as its finished file', () async {
    final extra = await editorExtraFor(
      _reaction,
      exists: (path) async => path != '/picked/clip.mp4',
      savedDraft: none,
    );
    expect(extra, isA<List<XFile>>());
    expect((extra as List<XFile>).single.path, '/gallery/SlimShot_VID_r.mp4');
  });

  test('any other video opens as itself', () async {
    const plain = RollShot(path: '/gallery/VID_1.mp4', isVideo: true, durationMs: 1000, takenAt: null);
    final extra = await editorExtraFor(plain, exists: everything, savedDraft: none) as List<XFile>;
    expect(extra.single.path, '/gallery/VID_1.mp4');
  });
}
