import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/features/camera/logic/camera_controller.dart';
import 'package:slimshotai/features/camera/logic/camera_roll.dart';
import 'package:slimshotai/features/camera/logic/react_capture_store.dart';
import 'package:slimshotai/features/camera/logic/react_live.dart';
import 'package:slimshotai/features/camera/logic/reaction.dart';
import 'package:slimshotai/features/camera/screens/camera_screen.dart';
import 'package:slimshotai/features/camera/widgets/reaction_frame.dart';

import '../../support/fake_camera.dart';
import 'camera_react_screen_test.dart' show FakeReactionVideo;
import 'camera_screen_test.dart' show FakePermissions;

/// REACT recorded live: the recorder draws your camera and the video into
/// the file as you record; the screen decides the way, sends the scene, and
/// keeps every control it had.
void main() {
  late FakeCamera camera;
  late String? picked;
  late List<FakeReactionVideo> oldWayVideos;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    camera = FakeCamera()
      ..recordedMs = 4000
      ..liveFacts = const ReactLiveFacts(fps1080: 60, fps720: 120);
    picked = '/picked/clip.mp4';
    oldWayVideos = [];
  });

  Future<void> pumpCamera(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: CameraScreen(
        backend: camera,
        permissions: FakePermissions(),
        newPath: (extension) async => '/shots/take.$extension',
        openRoll: (context, roll) async => null,
        loadFrame: (_) async => null,
        pickReactionVideo: (context) async => picked,
        probeReactionSource: (path) async =>
            ReactionSourceInfo(aspect: path.endsWith('.jpg') ? 4 / 5 : 16 / 9, isPhoto: path.endsWith('.jpg')),
        openReactionVideo: (path) async {
          final video = FakeReactionVideo();
          oldWayVideos.add(video);
          return video;
        },
        makeReaction: (request, {onProgress, onWarning}) async => null,
        buildStamp: () async => 'b1',
      ),
    ));
    await tester.pumpAndSettle();
  }

  Finder key(String name) => find.byKey(ValueKey(name));

  Future<void> enterAndChoose(WidgetTester tester) async {
    await tester.tap(key('camera_mode_react'));
    await tester.pumpAndSettle();
    await tester.tap(key('react_pick'));
    await tester.pumpAndSettle();
  }

  Future<void> startTake(WidgetTester tester) async {
    await tester.tap(key('camera_shutter'));
    await tester.pumpAndSettle();
    camera.emit(const RecordingProgress(durationMs: 0, paused: false));
    await tester.pumpAndSettle();
  }

  Future<void> stopTake(WidgetTester tester) async {
    await tester.tap(key('camera_shutter'));
    await tester.pumpAndSettle();
  }

  testWidgets('a phone that can records REACT live at 1080, the composite on screen', (tester) async {
    await pumpCamera(tester);
    await tester.tap(key('camera_mode_react'));
    await tester.pumpAndSettle();
    expect(camera.calls, contains('configure front react off live1080'));
    expect(find.byType(Texture), findsOneWidget);
    expect(key('react_pick'), findsOneWidget);
  });

  testWidgets('entering REACT gives the recorder your camera at once, before anything is chosen', (tester) async {
    await pumpCamera(tester);
    await tester.tap(key('camera_mode_react'));
    await tester.pumpAndSettle();
    expect(camera.scenes, isNotEmpty, reason: 'without a scene the recorder draws black');
    final places = reactionPlaces(layout: ReactionLayout.topBottom, window: ReactionWindow.initial, videoAspect: 9 / 16);
    expect(camera.scenes.last.camera.dst, places.camera);
    expect(camera.scenes.last.video, isNull);
  });

  testWidgets('choosing a video opens it in the recorder, and the scene puts it in its place', (tester) async {
    await pumpCamera(tester);
    await enterAndChoose(tester);
    expect(camera.calls, contains('source /picked/clip.mp4 video'));
    expect(oldWayVideos, isEmpty, reason: 'live: no player of its own on the screen');
    final places = reactionPlaces(layout: ReactionLayout.topBottom, window: ReactionWindow.initial, videoAspect: 16 / 9);
    expect(camera.scenes.last.video!.dst, places.video);
    expect(camera.scenes.last.camera.dst, places.camera);
  });

  testWidgets('the layout button and the window send their scene', (tester) async {
    await pumpCamera(tester);
    await enterAndChoose(tester);
    await tester.tap(key('react_layout'));
    await tester.pumpAndSettle();
    expect(camera.scenes.last.video!.dst, const Rect.fromLTWH(0, 0, 0.5, 1));
    await tester.tap(key('react_layout'));
    await tester.pumpAndSettle();
    final before = camera.scenes.last.video!.dst;
    await tester.drag(key('reaction_window'), const Offset(40, 60));
    await tester.pumpAndSettle();
    expect(camera.scenes.last.video!.dst.center.dx, greaterThan(before.center.dx));
  });

  testWidgets('the cross lets the choice go, and the scene loses the video', (tester) async {
    await pumpCamera(tester);
    await enterAndChoose(tester);
    await tester.tap(key('react_remove'));
    await tester.pumpAndSettle();
    expect(camera.calls, contains('clear source'));
    expect(camera.scenes.last.video, isNull);
    expect(key('react_pick'), findsOneWidget);
  });

  testWidgets("out loud the microphone cancels the speaker's echo; with headphones there is none", (tester) async {
    await pumpCamera(tester);
    await enterAndChoose(tester);
    await startTake(tester);
    expect(camera.lastReactLive!.cancelEcho, isTrue);
    expect(camera.lastGallery, isTrue);
    await stopTake(tester);
    camera.headphones = true;
    await startTake(tester);
    expect(camera.lastReactLive!.cancelEcho, isFalse);
    await stopTake(tester);
  });

  testWidgets("with the video's sound off nothing plays to the microphone", (tester) async {
    await pumpCamera(tester);
    await enterAndChoose(tester);
    await tester.tap(key('react_sound'));
    await tester.pumpAndSettle();
    await startTake(tester);
    expect(camera.lastReactLive!.cancelEcho, isFalse);
    await stopTake(tester);
  });

  testWidgets('a photo has no sound to echo', (tester) async {
    picked = '/picked/meme.jpg';
    await pumpCamera(tester);
    await enterAndChoose(tester);
    expect(camera.calls, contains('source /picked/meme.jpg photo'));
    expect(key('react_sound'), findsNothing);
    await startTake(tester);
    expect(camera.lastReactLive!.cancelEcho, isFalse);
    await stopTake(tester);
  });

  testWidgets('a tap on the video mid-take holds it, another plays it on', (tester) async {
    await pumpCamera(tester);
    await enterAndChoose(tester);
    await startTake(tester);
    await tester.tap(key('reaction_video_tap'));
    await tester.pump();
    expect(camera.playback, [false]);
    expect(key('react_video_held'), findsOneWidget);
    await tester.tap(key('reaction_video_tap'));
    await tester.pump();
    expect(camera.playback, [false, true]);
    await stopTake(tester);
  });

  testWidgets("the video's end offers its cross, which gives you the whole frame", (tester) async {
    await pumpCamera(tester);
    await enterAndChoose(tester);
    await startTake(tester);
    expect(key('react_take_remove'), findsNothing);
    camera.emit(const ReactVideoEnded());
    await tester.pumpAndSettle();
    await tester.tap(key('react_take_remove'));
    await tester.pumpAndSettle();
    expect(camera.scenes.last.video, isNull);
    expect(camera.scenes.last.camera.dst, const Rect.fromLTWH(0, 0, 1, 1));
    await stopTake(tester);
  });

  testWidgets('stop lands the reaction on the pile as one video', (tester) async {
    await pumpCamera(tester);
    await enterAndChoose(tester);
    await startTake(tester);
    await stopTake(tester);
    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(prefs.getString(kCameraRollKey)!) as List;
    expect(stored.single['path'], '/shots/take.mp4');
    expect((stored.single as Map).containsKey('react'), isFalse, reason: 'Edit opens it as one clip');
  });

  testWidgets('a choppy take steps down to 720p, says so, and the next take records at 720p', (tester) async {
    await pumpCamera(tester);
    await enterAndChoose(tester);
    await startTake(tester);
    camera.recordedFrames = 900;
    camera.recordedMissedFrames = 60;
    await stopTake(tester);
    expect(find.text(kReactStepTo720Message), findsOneWidget);
    expect(await ReactCaptureStore.load('b1'), 1);
    expect(camera.calls.last, 'configure front react off live720');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets("a recorder that failed goes back to today's way", (tester) async {
    await pumpCamera(tester);
    await enterAndChoose(tester);
    camera.emit(const ReactRecorderFailed(message: 'codec gone'));
    await tester.pumpAndSettle();
    expect(await ReactCaptureStore.load('b1'), 2);
    expect(camera.calls.last, 'configure front react off');
    expect(find.text(kReactLiveFailedMessage), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets("a phone that cannot keep up makes reactions today's way", (tester) async {
    camera.liveFacts = ReactLiveFacts.none;
    await pumpCamera(tester);
    await enterAndChoose(tester);
    expect(camera.calls, contains('configure front react off'));
    expect(camera.calls.where((c) => c.contains('live')), isEmpty);
    expect(oldWayVideos, hasLength(1), reason: "today's way plays the video itself");
  });
}
