
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/camera/logic/camera_controller.dart';
import 'package:slimshotai/features/camera/logic/reaction.dart';
import 'package:slimshotai/features/camera/logic/reaction_session.dart';

import '../../support/fake_camera.dart';

/// A video that plays on the test's clock, starting a set time after it is
/// asked to.
class FakeReactionPlayer implements ReactionPlayer {
  FakeReactionPlayer(this.clock, {this.durationMs = 60000});

  final Duration Function() clock;
  @override
  final int durationMs;

  /// How long play() takes to get the video moving.
  Duration startDelay = Duration.zero;

  final calls = <String>[];
  int _positionMs = 0;
  Duration? _playingSince;

  @override
  Future<int?> positionMs() async {
    final since = _playingSince;
    if (since == null) return _positionMs;
    final moving = clock() - since - startDelay;
    return _positionMs + (moving.isNegative ? 0 : moving.inMilliseconds);
  }

  @override
  Future<void> play() async {
    calls.add('play');
    _playingSince ??= clock();
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    _positionMs = (await positionMs())!;
    _playingSince = null;
  }

  @override
  Future<void> seekTo(int ms) async {
    calls.add('seek $ms');
    _positionMs = ms;
  }

  @override
  bool completed = false;
}

void main() {
  late FakeCamera camera;
  late CameraController controller;
  late FakeReactionPlayer player;
  late Duration now;
  var ended = 0;

  setUp(() async {
    now = Duration.zero;
    ended = 0;
    camera = FakeCamera()..recordedMs = 5000;
    controller = CameraController(
      backend: camera,
      newPath: (extension) async => '/camera/take.$extension',
      allowMicrophone: () async => true,
      allowStorage: () async => true,
      clock: () => now,
    );
    await controller.open();
    await controller.setMode(CameraMode.react);
    player = FakeReactionPlayer(() => now);
  });

  tearDown(() => controller.dispose());

  ReactionTakeSession session() =>
      ReactionTakeSession(camera: controller, player: player, onVideoEnded: () => ended++, sampleEvery: null);

  /// The recorder says how long its file is, as CameraX does while it writes.
  Future<void> report(int ms) async {
    camera.emit(RecordingProgress(durationMs: ms, paused: false));
    await pumpEventQueue();
  }

  test('the video waits for the recording to be running, then starts with it', () async {
    final take = session();
    await take.start();
    expect(camera.lastGallery, isFalse, reason: 'the take is private; the reaction is what is saved');
    expect(player.calls, isEmpty, reason: 'nothing recorded yet');
    await report(0);
    expect(player.calls, ['play']);
  });

  test('the video starting late is measured, and the reaction lines up with it', () async {
    final take = session();
    player.startDelay = const Duration(milliseconds: 150);
    await take.start();
    await report(0);
    for (var t = 250; t <= 2000; t += 250) {
      now = Duration(milliseconds: t);
      await take.sample();
    }
    now = const Duration(milliseconds: 2100);
    final recording = await take.stop();
    expect(recording!.cameraPath, '/camera/take.mp4');
    expect(recording.pieces.single.offsetMs, -150);
    expect(player.calls.last, 'pause');
  });

  test('pause holds both, and a pause that slipped the video is a piece of its own', () async {
    final take = session();
    await take.start();
    await report(0);
    now = const Duration(milliseconds: 500);
    await take.sample();
    now = const Duration(milliseconds: 1000);
    await take.pauseOrResume();
    expect(camera.calls.last, 'pause');
    expect(player.calls.last, 'pause');

    // The video comes back a fifth of a second slower than the camera.
    player.startDelay = const Duration(milliseconds: 200);
    now = const Duration(seconds: 5);
    await take.pauseOrResume();
    expect(camera.calls.last, 'resume');
    expect(player.calls.last, 'play');
    now = const Duration(milliseconds: 5600);
    await take.sample();
    now = const Duration(milliseconds: 6000);
    final recording = await take.stop();
    expect(recording!.pieces, const [
      ReactionPiece(startMs: 0, endMs: 1000, offsetMs: 0),
      ReactionPiece(startMs: 1000, endMs: 2000, offsetMs: -200),
    ]);
  });

  test('a sample before the video moves says nothing about the offset', () async {
    final take = session();
    player.startDelay = const Duration(milliseconds: 400);
    await take.start();
    await report(0);
    now = const Duration(milliseconds: 300);
    await take.sample();
    now = const Duration(milliseconds: 1000);
    final recording = await take.stop();
    // Nothing moving was sampled: the run keeps where it began.
    expect(recording!.pieces.single.offsetMs, 0);
  });

  test('the video reaching its end holds its last frame, and you go on recording', () async {
    player = FakeReactionPlayer(() => now, durationMs: 1000);
    final take = session();
    await take.start();
    await report(0);
    now = const Duration(milliseconds: 990);
    await take.sample();
    expect(ended, 1, reason: 'the screen is told, to offer the cross');
    expect(take.videoEnded, isTrue);
    expect(camera.calls, isNot(contains('stop')), reason: 'the take goes on');
    now = const Duration(milliseconds: 1500);
    await take.sample();
    expect(ended, 1, reason: 'said once');
    now = const Duration(milliseconds: 3000);
    final recording = await take.stop();
    expect(recording!.pieces, const [
      ReactionPiece(startMs: 0, endMs: 1000, offsetMs: 0),
      ReactionPiece.hold(startMs: 1000, endMs: 3000, atMs: 1000),
    ], reason: 'the hold starts exactly where the video ran out');
    expect(recording.removedAtMs, isNull);
  });

  test('a tap pauses the video while you keep recording, and another plays it on from there', () async {
    final take = session();
    await take.start();
    await report(0);
    now = const Duration(milliseconds: 1000);
    await take.toggleVideo();
    expect(take.videoHeld, isTrue);
    expect(player.calls.last, 'pause');
    expect(camera.calls.last, isNot('pause'), reason: 'only the video stops');
    now = const Duration(milliseconds: 3000);
    await take.toggleVideo();
    expect(take.videoHeld, isFalse);
    expect(player.calls.last, 'play');
    now = const Duration(milliseconds: 5000);
    final recording = await take.stop();
    expect(recording!.pieces, const [
      ReactionPiece(startMs: 0, endMs: 1000, offsetMs: 0),
      ReactionPiece.hold(startMs: 1000, endMs: 3000, atMs: 1000),
      ReactionPiece(startMs: 3000, endMs: 5000, offsetMs: -2000),
    ]);
  });

  test('pausing the take while the video is held keeps it held through the resume', () async {
    final take = session();
    await take.start();
    await report(0);
    now = const Duration(milliseconds: 1000);
    await take.toggleVideo();
    now = const Duration(milliseconds: 1500);
    await take.pauseOrResume();
    expect(camera.calls.last, 'pause');
    now = const Duration(milliseconds: 4000);
    await take.pauseOrResume();
    expect(camera.calls.last, 'resume');
    expect(player.calls.last, 'pause', reason: 'the video stays where the tap left it');
    expect(take.videoHeld, isTrue);
    now = const Duration(milliseconds: 5000);
    final recording = await take.stop();
    expect(recording!.pieces, const [
      ReactionPiece(startMs: 0, endMs: 1000, offsetMs: 0),
      ReactionPiece.hold(startMs: 1000, endMs: 2500, atMs: 1000),
    ]);
  });

  test('the video taken away after its end: you fill the frame from that moment', () async {
    player = FakeReactionPlayer(() => now, durationMs: 1000);
    final take = session();
    await take.start();
    await report(0);
    now = const Duration(milliseconds: 990);
    await take.sample();
    now = const Duration(milliseconds: 2000);
    take.removeVideo();
    expect(take.videoRemoved, isTrue);
    await take.toggleVideo();
    expect(player.calls.where((c) => c == 'play'), hasLength(1), reason: 'nothing to play once gone');
    now = const Duration(milliseconds: 4000);
    final recording = await take.stop();
    expect(recording!.removedAtMs, 2000);
    expect(recording.pieces.last, const ReactionPiece.hold(startMs: 1000, endMs: 2000, atMs: 1000));
  });

  test('the video is not taken away while it still plays', () async {
    final take = session();
    await take.start();
    await report(0);
    now = const Duration(milliseconds: 1000);
    take.removeVideo();
    expect(take.videoRemoved, isFalse);
    now = const Duration(milliseconds: 2000);
    final recording = await take.stop();
    expect(recording!.removedAtMs, isNull);
  });

  test('a video whose length the player cannot tell never ends the take by itself', () async {
    player = FakeReactionPlayer(() => now, durationMs: 0)..completed = true;
    final take = session();
    await take.start();
    await report(0);
    for (var t = 250; t <= 3000; t += 250) {
      now = Duration(milliseconds: t);
      await take.sample();
    }
    expect(ended, 0, reason: 'a length of 0 says nothing about where the video is');
  });

  test('a player that says it is done before anything played is not believed', () async {
    player.completed = true;
    player.startDelay = const Duration(seconds: 10);
    final take = session();
    await take.start();
    await report(0);
    now = const Duration(milliseconds: 250);
    await take.sample();
    expect(ended, 0);
  });

  test('a recording the camera ended by itself keeps what was recorded', () async {
    final take = session();
    await take.start();
    await report(0);
    now = const Duration(milliseconds: 800);
    await take.sample();
    camera.emit(const RecordingEnded(path: '/camera/take.mp4', durationMs: 900));
    await pumpEventQueue();
    final shot = controller.takeEndedShot()!;
    final recording = await take.endedBy(shot);
    expect(recording!.cameraPath, '/camera/take.mp4');
    expect(recording.durationMs, 900);
    expect(recording.pieces, isNotEmpty);
    expect(player.calls.last, 'pause');
  });

  test('nothing recorded is no reaction', () async {
    camera.recordedMs = 0;
    final take = session();
    await take.start();
    await report(0);
    expect(await take.stop(), isNull);
  });
}
