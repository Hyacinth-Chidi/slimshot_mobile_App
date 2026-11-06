import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/features/camera/logic/camera_roll.dart';
import 'package:slimshotai/features/camera/logic/reaction.dart';
import 'package:slimshotai/features/video_editor/models/media_asset.dart';

RollShot shot(String name, {bool video = false, String? uri, int minute = 0}) => RollShot(
      path: '/g/$name',
      uri: uri ?? 'content://media/external/$name',
      isVideo: video,
      durationMs: video ? 4000 : 0,
      takenAt: DateTime(2026, 11, 5, 19, minute),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a new shot goes on top', () async {
    final roll = CameraRoll();
    await roll.add(shot('a.jpg'));
    await roll.add(shot('b.mp4', video: true));
    expect(roll.shots.map((s) => s.path), ['/g/b.mp4', '/g/a.jpg']);
  });

  test('the shots outlive the screen: a new roll reads them back', () async {
    final first = CameraRoll();
    await first.add(shot('a.jpg', minute: 1));
    await first.add(shot('b.mp4', video: true, minute: 2));

    final again = CameraRoll();
    await again.load(exists: (_) async => true);
    expect(again.shots.map((s) => s.path), ['/g/b.mp4', '/g/a.jpg']);
    final video = again.shots.first;
    expect(video.isVideo, isTrue);
    expect(video.durationMs, 4000);
    expect(video.uri, 'content://media/external/b.mp4');
    expect(video.takenAt, DateTime(2026, 11, 5, 19, 2));
  });

  test('a shot deleted in the gallery drops out of the roll', () async {
    final first = CameraRoll();
    await first.add(shot('a.jpg'));
    await first.add(shot('gone.jpg'));

    final again = CameraRoll();
    await again.load(exists: (path) async => path != '/g/gone.jpg');
    expect(again.shots.map((s) => s.path), ['/g/a.jpg']);

    final third = CameraRoll();
    await third.load(exists: (_) async => true);
    expect(third.shots.map((s) => s.path), ['/g/a.jpg'], reason: 'the drop is written back');
  });

  test('removing a shot takes it out for good', () async {
    final roll = CameraRoll();
    await roll.add(shot('a.jpg'));
    await roll.add(shot('b.jpg'));
    await roll.remove(roll.shots.first);
    expect(roll.shots.map((s) => s.path), ['/g/a.jpg']);

    final again = CameraRoll();
    await again.load(exists: (_) async => true);
    expect(again.shots.map((s) => s.path), ['/g/a.jpg']);
  });

  test('the roll keeps a bounded list, dropping the oldest', () async {
    final roll = CameraRoll();
    for (var i = 0; i < kCameraRollMax + 5; i++) {
      await roll.add(shot('$i.jpg'));
    }
    expect(roll.shots, hasLength(kCameraRollMax));
    expect(roll.shots.first.path, '/g/${kCameraRollMax + 4}.jpg');
    expect(roll.shots.last.path, '/g/5.jpg');
  });

  test('a shot kept inside SlimShot has no gallery address', () async {
    final roll = CameraRoll();
    await roll.add(const RollShot(
      path: '/app/camera/IMG_1.jpg',
      isVideo: false,
      durationMs: 0,
      takenAt: null,
    ));
    final again = CameraRoll();
    await again.load(exists: (_) async => true);
    expect(again.shots.single.uri, isNull);
    expect(again.shots.single.inGallery, isFalse);
  });

  test('a stored list it cannot read is an empty roll, never a crash', () async {
    SharedPreferences.setMockInitialValues({kCameraRollKey: 'not json'});
    final roll = CameraRoll();
    await roll.load(exists: (_) async => true);
    expect(roll.shots, isEmpty);
  });

  test('the paths a roll keeps are readable without loading it', () async {
    final roll = CameraRoll();
    await roll.add(shot('a.jpg'));
    expect(await CameraRoll.storedPaths(), {'/g/a.jpg'});
  });

  group('a reaction', () {
    const take = ReactionTake(
      id: 'r1',
      layout: ReactionLayout.sideBySide,
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
      pieces: [ReactionPiece(startMs: 0, endMs: 8000, offsetMs: -90)],
      videoSoundInCamera: true,
    );

    RollShot reaction() => RollShot(
          path: '/g/SlimShot_VID_r1.mp4',
          uri: 'content://media/external/video/1',
          isVideo: true,
          durationMs: 8000,
          takenAt: DateTime(2026, 11, 6),
          reaction: take,
        );

    test('keeps what it was made from, so Edit can open it as its layers', () async {
      final roll = CameraRoll();
      await roll.add(reaction());
      final again = CameraRoll();
      await again.load(exists: (_) async => true);
      expect(again.shots.single.reaction!.toJson(), take.toJson());
    });

    test('its take is kept from the launch sweep', () async {
      final roll = CameraRoll();
      await roll.add(reaction());
      expect(await CameraRoll.storedPaths(), {'/g/SlimShot_VID_r1.mp4', '/camera/VID_take.mp4'});
    });

    test("deleting it takes its take too; the video reacted to is the user's", () {
      expect(cameraFilesOf(reaction()), ['/camera/VID_take.mp4']);
      expect(cameraFilesOf(shot('a.jpg')), isEmpty, reason: 'in the gallery: deleted through its address');
      const private = RollShot(path: '/camera/IMG_1.jpg', isVideo: false, durationMs: 0, takenAt: null);
      expect(cameraFilesOf(private), ['/camera/IMG_1.jpg'], reason: "kept in SlimShot: its file is the camera's");
    });
  });
}
