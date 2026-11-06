import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/core/utils/held_work.dart';
import 'package:slimshotai/features/camera/logic/camera_controller.dart';
import 'package:slimshotai/features/camera/logic/camera_roll.dart';
import 'package:slimshotai/features/camera/logic/reaction.dart';
import 'package:slimshotai/features/camera/screens/camera_screen.dart';
import 'package:slimshotai/features/camera/services/reaction_maker.dart';
import 'package:slimshotai/features/camera/widgets/reaction_frame.dart';

import '../../support/fake_camera.dart';
import 'camera_screen_test.dart' show FakePermissions;

/// A video that plays nothing and remembers what it was told.
class FakeReactionVideo implements ReactionVideo {
  FakeReactionVideo({this.aspectRatio = 16 / 9, this.isPhoto = false});

  @override
  final double aspectRatio;

  @override
  final bool isPhoto;

  final calls = <String>[];
  double volume = 1;
  bool disposed = false;

  @override
  int durationMs = 60000;

  /// Where the video says it is.
  int position = 0;

  @override
  bool get completed => false;

  @override
  Future<int?> positionMs() async => position;

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> seekTo(int ms) async => calls.add('seek $ms');

  @override
  Future<void> setVolume(double volume) async => this.volume = volume;

  @override
  Widget picture() => const ColoredBox(key: ValueKey('fake_video_picture'), color: Colors.teal);

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  late FakeCamera camera;
  late FakePermissions permissions;
  late List<FakeReactionVideo> videos;
  late List<ReactionRequest> requests;
  late String? picked;
  late RollShot? made;
  var picks = 0;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    camera = FakeCamera()..recordedMs = 4000;
    permissions = FakePermissions();
    videos = [];
    requests = [];
    picked = '/picked/clip.mp4';
    picks = 0;
    made = const RollShot(path: '/gallery/reaction.mp4', uri: 'content://media/video/5', isVideo: true, durationMs: 3900, takenAt: null);
  });

  Future<void> pumpCamera(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: CameraScreen(
        backend: camera,
        permissions: permissions,
        newPath: (extension) async => '/shots/take.$extension',
        openRoll: (context, roll) async => null,
        loadFrame: (_) async => null,
        pickReactionVideo: (context) async {
          picks++;
          return picked;
        },
        openReactionVideo: (path) async {
          final video = FakeReactionVideo(isPhoto: path.endsWith('.jpg'));
          videos.add(video);
          return video;
        },
        makeReaction: (request, {onProgress, onWarning}) async {
          requests.add(request);
          onProgress?.call(0.5);
          return made;
        },
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder key(String name) => find.byKey(ValueKey(name));

  Future<void> enterReact(WidgetTester tester) async {
    await tester.tap(key('camera_mode_react'));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester) async {
    await tester.tap(key('react_pick'));
    await tester.pumpAndSettle();
  }

  Future<void> enterAndChoose(WidgetTester tester) async {
    await enterReact(tester);
    await choose(tester);
  }

  Future<void> recordATake(WidgetTester tester) async {
    await tester.tap(key('camera_shutter'));
    await tester.pumpAndSettle();
    camera.emit(const RecordingProgress(durationMs: 0, paused: false));
    await tester.pumpAndSettle();
    await tester.tap(key('camera_shutter'));
    await tester.pumpAndSettle();
  }

  testWidgets('REACT opens at once on the front camera, with a frame to choose what to react to', (tester) async {
    await pumpCamera(tester);
    await enterReact(tester);
    expect(picks, 0, reason: 'nothing is picked until asked for');
    expect(camera.calls, contains('configure front react off'));
    expect(key('reaction_frame'), findsOneWidget);
    expect(key('react_pick'), findsOneWidget);
    expect(find.text('Select photo or video'), findsOneWidget);
    expect(key('react_sound'), findsNothing, reason: 'no sound to turn off yet');
    expect(key('react_layout'), findsOneWidget, reason: 'the layout can be chosen first');
  });

  testWidgets('the frame opens the picker; nothing chosen, it stays', (tester) async {
    picked = null;
    await pumpCamera(tester);
    await enterReact(tester);
    await choose(tester);
    expect(picks, 1);
    expect(key('react_pick'), findsOneWidget);
    picked = '/picked/clip.mp4';
    await choose(tester);
    expect(key('react_pick'), findsNothing);
    expect(key('fake_video_picture'), findsOneWidget);
  });

  testWidgets('the shutter with nothing chosen asks for something, and records nothing', (tester) async {
    await pumpCamera(tester);
    await enterReact(tester);
    await tester.tap(key('camera_shutter'));
    await tester.pumpAndSettle();
    expect(picks, 1);
    expect(camera.calls.where((c) => c.startsWith('record')), isEmpty);
    expect(key('fake_video_picture'), findsOneWidget);
  });

  testWidgets('a photo: no sound to turn off, and the microphone hears only you', (tester) async {
    picked = '/picked/meme.jpg';
    await pumpCamera(tester);
    await enterAndChoose(tester);
    expect(key('react_sound'), findsNothing);
    await recordATake(tester);
    expect(requests.single.videoPath, '/picked/meme.jpg');
    expect(requests.single.micHearsVideo, isFalse);
  });

  testWidgets('a video chosen: the frame with you and the video', (tester) async {
    await pumpCamera(tester);
    await enterAndChoose(tester);
    expect(camera.calls, contains('configure front react off'));
    expect(key('reaction_frame'), findsOneWidget);
    expect(key('fake_video_picture'), findsOneWidget);
    expect(find.byType(Texture), findsOneWidget);
  });

  testWidgets('the layout button moves through top and bottom, side by side, and the window', (tester) async {
    await pumpCamera(tester);
    await enterAndChoose(tester);
    final frame = tester.getRect(key('reaction_frame'));
    Rect video() => tester.getRect(key('reaction_video'));

    expect(video().top, moreOrLessEquals(frame.top));
    expect(video().width, moreOrLessEquals(frame.width));
    expect(video().height, moreOrLessEquals(frame.height / 2));

    await tester.tap(key('react_layout'));
    await tester.pumpAndSettle();
    expect(video().left, moreOrLessEquals(frame.left));
    expect(video().width, moreOrLessEquals(frame.width / 2));
    expect(video().height, moreOrLessEquals(frame.height));

    await tester.tap(key('react_layout'));
    await tester.pumpAndSettle();
    expect(video().width, lessThan(frame.width / 2), reason: 'a window over you');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kReactLayoutKey), 'float');
  });

  testWidgets('a take: the video plays once the recording runs, and the reaction lands on the pile', (tester) async {
    await pumpCamera(tester);
    await enterAndChoose(tester);
    await tester.tap(key('camera_shutter'));
    await tester.pumpAndSettle();
    expect(camera.lastGallery, isFalse, reason: 'the take is private');
    expect(videos.single.calls, isNot(contains('play')), reason: 'not running yet');
    expect(HeldWork.instance.isHeld, isTrue);
    expect(key('react_layout'), findsNothing, reason: 'the layout is fixed for the take');

    camera.emit(const RecordingProgress(durationMs: 0, paused: false));
    await tester.pumpAndSettle();
    expect(videos.single.calls, contains('play'));

    await tester.tap(key('camera_shutter'));
    await tester.pumpAndSettle();
    final request = requests.single;
    expect(request.recording.cameraPath, '/shots/take.mp4');
    expect(request.videoPath, '/picked/clip.mp4');
    expect(request.layout, ReactionLayout.topBottom);
    expect(request.micHearsVideo, isTrue, reason: 'out loud, no headphones');
    expect(request.toGallery, isTrue);
    expect(camera.calls, containsAllInOrder(['stop', 'close', 'open front react']));
    expect(HeldWork.instance.isHeld, isFalse);

    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getString(kCameraRollKey)!) as List;
    expect(stored.map((s) => s['path']), ['/gallery/reaction.mp4'], reason: 'the reaction, not the take');
    expect(key('camera_roll_pile'), findsOneWidget);
    expect(videos.single.calls.last, 'seek 0', reason: 'ready for the next take');
  });

  testWidgets('with headphones, or the video silent, the file keeps the video\'s own sound', (tester) async {
    camera.headphones = true;
    await pumpCamera(tester);
    await enterAndChoose(tester);
    await recordATake(tester);
    expect(requests.last.micHearsVideo, isFalse);

    camera.headphones = false;
    await tester.tap(key('react_sound'));
    await tester.pumpAndSettle();
    expect(videos.single.volume, 0);
    await recordATake(tester);
    expect(requests.last.micHearsVideo, isFalse);
  });

  testWidgets('a reaction that could not be made says so, and keeps the take', (tester) async {
    made = null;
    await pumpCamera(tester);
    await enterAndChoose(tester);
    await recordATake(tester);
    expect(find.text(kReactionFailedMessage), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getString(kCameraRollKey)!) as List;
    expect(stored.single['path'], '/shots/take.mp4');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the window moves under the finger and stays in the frame', (tester) async {
    await pumpCamera(tester);
    await enterAndChoose(tester);
    await tester.tap(key('react_layout'));
    await tester.pumpAndSettle();
    await tester.tap(key('react_layout'));
    await tester.pumpAndSettle();
    final frame = tester.getRect(key('reaction_frame'));
    final before = tester.getRect(key('reaction_video'));

    await tester.drag(key('reaction_window'), const Offset(60, 80));
    await tester.pumpAndSettle();
    final moved = tester.getRect(key('reaction_video'));
    expect(moved.center.dx, greaterThan(before.center.dx));
    expect(moved.center.dy, greaterThan(before.center.dy));

    await tester.drag(key('reaction_window'), const Offset(-2000, -2000));
    await tester.pumpAndSettle();
    final held = tester.getRect(key('reaction_video'));
    expect(held.left, moreOrLessEquals(frame.left));
    expect(held.top, moreOrLessEquals(frame.top));
    expect(camera.calls.where((c) => c.startsWith('configure') && !c.contains('react')), isEmpty,
        reason: 'moving the window is not a swipe between modes');
  });

  testWidgets('leaving REACT lets the video go; coming back starts empty', (tester) async {
    await pumpCamera(tester);
    await enterAndChoose(tester);
    await tester.tap(key('camera_mode_video'));
    await tester.pumpAndSettle();
    expect(videos.single.disposed, isTrue);
    await enterReact(tester);
    expect(videos, hasLength(1), reason: 'nothing reopened');
    expect(key('react_pick'), findsOneWidget);
    expect(key('fake_video_picture'), findsNothing);
  });

  testWidgets('the cross clears what was chosen, back to the empty frame', (tester) async {
    await pumpCamera(tester);
    await enterReact(tester);
    expect(key('react_remove'), findsNothing, reason: 'nothing to clear yet');
    await choose(tester);
    await tester.tap(key('react_remove'));
    await tester.pumpAndSettle();
    expect(videos.single.disposed, isTrue);
    expect(key('react_pick'), findsOneWidget);
    expect(key('react_remove'), findsNothing);
    await tester.tap(key('camera_shutter'));
    await tester.pumpAndSettle();
    expect(picks, 2, reason: 'the shutter asks again, nothing chosen');
  });

  testWidgets('a tap on the video while recording pauses only the video, and another plays it on', (tester) async {
    await pumpCamera(tester);
    await enterAndChoose(tester);
    await tester.tap(key('camera_shutter'));
    await tester.pumpAndSettle();
    camera.emit(const RecordingProgress(durationMs: 0, paused: false));
    await tester.pumpAndSettle();
    expect(videos.single.calls.last, 'play');

    await tester.tap(key('reaction_video_tap'));
    await tester.pump();
    expect(videos.single.calls.last, 'pause');
    expect(camera.calls, isNot(contains('pause')), reason: 'you are still being recorded');
    expect(key('react_video_held'), findsOneWidget);

    await tester.tap(key('reaction_video_tap'));
    await tester.pump();
    expect(videos.single.calls.last, 'play');
    expect(key('react_video_held'), findsNothing);
    await tester.tap(key('camera_shutter'));
    await tester.pumpAndSettle();
    expect(requests.single.recording.pieces.where((p) => p.isHold), hasLength(1));
  });

  testWidgets('the video at its end holds; its cross takes it away and you fill the frame', (tester) async {
    await pumpCamera(tester);
    await enterAndChoose(tester);
    videos.single.durationMs = 1000;
    await tester.tap(key('camera_shutter'));
    await tester.pumpAndSettle();
    camera.emit(const RecordingProgress(durationMs: 0, paused: false));
    await tester.pumpAndSettle();
    expect(key('react_take_remove'), findsNothing, reason: 'not while the video plays');

    videos.single.position = 990;
    await tester.pump(const Duration(milliseconds: 300));
    expect(key('react_take_remove'), findsOneWidget);
    expect(camera.calls, isNot(contains('stop')), reason: 'the take goes on');
    expect(requests, isEmpty);

    await tester.tap(key('react_take_remove'));
    await tester.pump();
    expect(key('reaction_video'), findsNothing);
    expect(key('react_take_remove'), findsNothing);

    await tester.tap(key('camera_shutter'));
    await tester.pumpAndSettle();
    expect(requests.single.recording.removedAtMs, isNotNull);
  });

  testWidgets('a photo is not paused by a tap: there is nothing to pause', (tester) async {
    picked = '/picked/meme.jpg';
    await pumpCamera(tester);
    await enterAndChoose(tester);
    await tester.tap(key('camera_shutter'));
    await tester.pumpAndSettle();
    camera.emit(const RecordingProgress(durationMs: 0, paused: false));
    await tester.pumpAndSettle();
    expect(key('reaction_video_tap'), findsNothing);
    await tester.tap(key('camera_shutter'));
    await tester.pumpAndSettle();
  });

  testWidgets('nothing overflows in REACT on a small phone with large text', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 568 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(320, 568), textScaler: TextScaler.linear(1.3)),
      child: MaterialApp(
        home: CameraScreen(
          backend: camera,
          permissions: permissions,
          newPath: (extension) async => '/shots/x.$extension',
          openRoll: (context, roll) async => null,
          loadFrame: (_) async => null,
          pickReactionVideo: (context) async => '/picked/clip.mp4',
          openReactionVideo: (path) async => FakeReactionVideo(aspectRatio: 9 / 16),
          makeReaction: (request, {onProgress, onWarning}) async => made,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await enterReact(tester);
    expect(tester.takeException(), isNull);
    await choose(tester);
    for (var i = 0; i < 3; i++) {
      await tester.tap(key('react_layout'));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });
}
