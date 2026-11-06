import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimshotai/features/camera/logic/react_capture_store.dart';
import 'package:slimshotai/features/camera/logic/react_live.dart';
import 'package:slimshotai/features/camera/logic/reaction.dart';

void main() {
  group('the way a phone records', () {
    test('comfortable at 1080p records 1080p', () {
      expect(chooseReactCapture(const ReactLiveFacts(fps1080: 60, fps720: 120)), ReactCapture.live1080);
    });

    test('borderline at 1080p records 720p', () {
      expect(chooseReactCapture(const ReactLiveFacts(fps1080: 35, fps720: 60)), ReactCapture.live720);
      expect(chooseReactCapture(const ReactLiveFacts(fps1080: 0, fps720: 30)), ReactCapture.live720);
    });

    test('a phone that cannot keep up makes reactions after recording, as today', () {
      expect(chooseReactCapture(const ReactLiveFacts(fps1080: 20, fps720: 20)), ReactCapture.afterwards);
      expect(chooseReactCapture(ReactLiveFacts.none), ReactCapture.afterwards);
    });

    test('a remembered step down holds', () {
      const fast = ReactLiveFacts(fps1080: 60, fps720: 120);
      expect(chooseReactCapture(fast, step: 1), ReactCapture.live720);
      expect(chooseReactCapture(fast, step: 2), ReactCapture.afterwards);
    });

    test('the facts read from the channel, anything unreadable as none', () {
      final facts = ReactLiveFacts.fromMap({'fps1080': 48, 'fps720': 96.5});
      expect(facts.fps1080, 48);
      expect(facts.fps720, 96.5);
      expect(ReactLiveFacts.fromMap(null).fps1080, 0);
      expect(ReactLiveFacts.fromMap({'fps1080': 'x'}).fps1080, 0);
    });

    test('the short side each way records at', () {
      expect(ReactCapture.live1080.shortSide, 1080);
      expect(ReactCapture.live720.shortSide, 720);
      expect(ReactCapture.afterwards.shortSide, isNull);
    });
  });

  group('a choppy take', () {
    test('a few frames lost is normal, many is choppy', () {
      expect(takeWasChoppy(frames: 900, missedFrames: 9), isFalse);
      expect(takeWasChoppy(frames: 900, missedFrames: 40), isFalse, reason: 'under 5% of 940');
      expect(takeWasChoppy(frames: 900, missedFrames: 50), isTrue);
      expect(takeWasChoppy(frames: 100, missedFrames: 12), isTrue, reason: 'at least 10, the floor');
    });

    test('steps down one size at a time', () {
      expect(stepAfterChoppy(ReactCapture.live1080), 1);
      expect(stepAfterChoppy(ReactCapture.live720), 2);
    });
  });

  group('the scene the recorder draws', () {
    const cameraAspect = 9 / 16;
    const videoAspect = 16 / 9;

    for (final layout in ReactionLayout.values) {
      test('${layout.name}: each picture in its place, as the file was rendered', () {
        final scene = reactionScene(
          layout: layout,
          window: ReactionWindow.initial,
          cameraAspect: cameraAspect,
          videoAspect: videoAspect,
          hasVideo: true,
        );
        final places = reactionPlaces(layout: layout, window: ReactionWindow.initial, videoAspect: videoAspect);
        expect(scene.camera.dst, places.camera);
        expect(
          scene.camera.src,
          coverCrop(contentAspect: cameraAspect, regionAspect: reactionRegionAspect(places.camera)),
        );
        expect(scene.video!.dst, places.video);
        expect(
          scene.video!.src,
          layout == ReactionLayout.float
              ? const Rect.fromLTWH(0, 0, 1, 1)
              : coverCrop(contentAspect: videoAspect, regionAspect: reactionRegionAspect(places.video)),
        );
      });
    }

    test('nothing chosen yet: no video, the camera in its place', () {
      final scene = reactionScene(
        layout: ReactionLayout.topBottom,
        window: ReactionWindow.initial,
        cameraAspect: cameraAspect,
        videoAspect: videoAspect,
        hasVideo: false,
      );
      expect(scene.video, isNull);
      expect(scene.camera.dst, const Rect.fromLTWH(0, 0.5, 1, 0.5));
    });

    test('the video taken away: you fill the frame', () {
      final scene = reactionScene(
        layout: ReactionLayout.sideBySide,
        window: ReactionWindow.initial,
        cameraAspect: 3 / 4,
        videoAspect: videoAspect,
        hasVideo: true,
        removed: true,
      );
      expect(scene.video, isNull);
      expect(scene.camera.dst, const Rect.fromLTWH(0, 0, 1, 1));
      expect(scene.camera.src, coverCrop(contentAspect: 3 / 4, regionAspect: 9 / 16));
    });

    test('on the wire: rects as left, top, width, height', () {
      const scene = ReactionScene(
        camera: ReactionQuad(dst: Rect.fromLTWH(0, 0.5, 1, 0.5), src: Rect.fromLTWH(0.25, 0, 0.5, 1)),
        video: ReactionQuad(dst: Rect.fromLTWH(0, 0, 1, 0.5), src: Rect.fromLTWH(0, 0, 1, 1)),
      );
      expect(scene.toJson(), {
        'camera': {
          'dst': [0.0, 0.5, 1.0, 0.5],
          'src': [0.25, 0.0, 0.5, 1.0],
        },
        'video': {
          'dst': [0.0, 0.0, 1.0, 0.5],
          'src': [0.0, 0.0, 1.0, 1.0],
        },
      });
      expect(
        const ReactionScene(camera: ReactionQuad(dst: Rect.fromLTWH(0, 0, 1, 1), src: Rect.fromLTWH(0, 0, 1, 1)))
            .toJson()
            .containsKey('video'),
        isFalse,
      );
    });
  });

  test("a take's sound settings travel with its start", () {
    expect(const ReactLiveTake(lowerVideo: true).toJson(), {'lowerVideo': true, 'duck': 0.25, 'gate': 0.1, 'rampMs': 150});
    expect(const ReactLiveTake(lowerVideo: false).toJson()['lowerVideo'], isFalse);
  });

  group('the remembered step', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('is kept for this build and forgotten by the next', () async {
      await ReactCaptureStore.save(1, 'b1');
      expect(await ReactCaptureStore.load('b1'), 1);
      expect(await ReactCaptureStore.load('b2'), 0);
    });

    test('with no build known nothing is kept', () async {
      await ReactCaptureStore.save(2, null);
      expect(await ReactCaptureStore.load(null), 0);
      expect(await ReactCaptureStore.load('b1'), 0);
    });
  });
}
