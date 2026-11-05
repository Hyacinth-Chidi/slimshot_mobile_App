import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/camera/logic/camera_controller.dart';
import 'package:slimshotai/features/camera/services/method_channel_camera.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the camera\'s description', () {
    test('is read field by field', () {
      final info = cameraInfoFrom({
        'textureId': 3,
        'lens': 'front',
        'mode': 'video',
        'hasFlash': false,
        'minZoom': 1.0,
        'maxZoom': 4,
        'canFlip': true,
        'previewWidth': 1920,
        'previewHeight': 1080,
        'rotation': 270,
        'mirrored': true,
        'cameraTransform': false,
        'displayRotation': 90,
      })!;
      expect(info.textureId, 3);
      expect(info.lens, CameraLens.front);
      expect(info.mode, CameraMode.video);
      expect(info.hasFlash, isFalse);
      expect(info.minZoom, 1.0);
      expect(info.maxZoom, 4.0);
      expect(info.canFlip, isTrue);
      expect(info.previewWidth, 1920);
      expect(info.previewHeight, 1080);
      expect(info.rotation, 270);
      expect(info.mirrored, isTrue);
      expect(info.cameraTransform, isFalse);
      expect(info.displayRotation, 90);
    });

    test('without a texture there is no camera', () {
      expect(cameraInfoFrom({'lens': 'back'}), isNull);
      expect(cameraInfoFrom(null), isNull);
    });

    test('what it does not say reads as the camera straight to the screen', () {
      // An older build sends no transform: the camera's own transform was
      // the only path it had.
      final info = cameraInfoFrom({'textureId': 1})!;
      expect(info.lens, CameraLens.back);
      expect(info.mode, CameraMode.photo);
      expect(info.cameraTransform, isTrue);
      expect(info.previewWidth, isNull);
      expect(info.rotation, 0);
    });

    test('a zoom range the wrong way round holds at its least', () {
      final info = cameraInfoFrom({'textureId': 1, 'minZoom': 2.0, 'maxZoom': 1.0})!;
      expect(info.minZoom, 2.0);
      expect(info.maxZoom, 2.0);
    });
  });

  group('events', () {
    test('a preview change', () {
      final event = cameraEventFrom({
        'type': 'preview',
        'previewWidth': 1280,
        'previewHeight': 720,
        'rotation': 90,
        'mirrored': false,
        'cameraTransform': true,
        'displayRotation': 0,
      });
      expect(event, isA<PreviewChanged>());
      final preview = event! as PreviewChanged;
      expect(preview.previewWidth, 1280);
      expect(preview.rotation, 90);
    });

    test('the running time', () {
      final event = cameraEventFrom({'type': 'recording', 'durationMs': 7300, 'paused': true});
      expect(event, isA<RecordingProgress>());
      expect((event! as RecordingProgress).durationMs, 7300);
      expect((event as RecordingProgress).paused, isTrue);
    });

    test('a recording that ended by itself, with what it kept or without', () {
      final kept = cameraEventFrom({'type': 'recordingEnded', 'path': '/c/1.mp4', 'durationMs': 3000})
          as RecordingEnded;
      expect(kept.path, '/c/1.mp4');
      expect(kept.durationMs, 3000);
      final lost = cameraEventFrom({'type': 'recordingEnded'}) as RecordingEnded;
      expect(lost.path, isNull);
    });

    test('the camera taken away and given back', () {
      final lost = cameraEventFrom({
        'type': 'camera',
        'open': false,
        'message': 'The camera is in use by another app.',
      }) as CameraAvailability;
      expect(lost.open, isFalse);
      expect(lost.message, 'The camera is in use by another app.');
      final back = cameraEventFrom({'type': 'camera', 'open': true}) as CameraAvailability;
      expect(back.open, isTrue);
    });

    test('one this build does not know is ignored', () {
      expect(cameraEventFrom({'type': 'faces'}), isNull);
      expect(cameraEventFrom('preview'), isNull);
    });
  });

  test('a finished recording needs a file', () {
    expect(recordedVideoFrom({}), isNull);
    expect(recordedVideoFrom({'path': ''}), isNull);
    final video = recordedVideoFrom({'path': '/c/2.mp4', 'durationMs': 1500})!;
    expect(video.path, '/c/2.mp4');
    expect(video.durationMs, 1500);
  });

  group('over the channel', () {
    const channel = MethodChannel('slimshot_ai/camera_test');
    final calls = <MethodCall>[];

    setUp(() => calls.clear());

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    void answer(Future<Object?>? Function(MethodCall call) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) {
        calls.add(call);
        return handler(call);
      });
    }

    test('a bind sends the lens, the mode and that mode\'s flash', () async {
      answer((_) async => {'textureId': 9, 'lens': 'back', 'mode': 'video'});
      final camera = MethodChannelCamera(channel: channel);
      final info = await camera.configure(
        lens: CameraLens.back,
        mode: CameraMode.video,
        flash: CameraFlash.on,
      );
      expect(info.textureId, 9);
      expect(calls.single.method, 'configure');
      expect(calls.single.arguments, {'lens': 'back', 'mode': 'video', 'flash': 'on'});
    });

    test('a refusal arrives in the phone\'s own words', () async {
      answer((_) async => throw PlatformException(code: 'camera_unavailable', message: 'No camera here.'));
      final camera = MethodChannelCamera(channel: channel);
      await expectLater(
        camera.open(lens: CameraLens.back, mode: CameraMode.photo, flash: CameraFlash.off),
        throwsA(isA<CameraFailure>().having((f) => f.message, 'message', 'No camera here.')),
      );
    });

    test('a photo answered without a file is a failure', () async {
      answer((_) async => <String, Object?>{});
      final camera = MethodChannelCamera(channel: channel);
      await expectLater(camera.takePhoto('/c/1.jpg'), throwsA(isA<CameraFailure>()));
    });

    test('closing a camera that is gone says nothing', () async {
      answer((_) async => throw PlatformException(code: 'gone'));
      await MethodChannelCamera(channel: channel).close();
    });
  });
}
