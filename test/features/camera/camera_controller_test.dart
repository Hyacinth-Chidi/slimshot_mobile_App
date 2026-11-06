import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/camera/logic/camera_controller.dart';

import '../../support/fake_camera.dart';

class _FailingPhotoCamera extends FakeCamera {
  @override
  Future<SavedShot> takePhoto(String path, {required bool gallery}) async =>
      throw const CameraFailure('The photo could not be taken.');
}

void main() {
  late FakeCamera camera;
  late CameraController controller;
  var micAllowed = true;
  var storageAllowed = true;
  var storageAsks = 0;
  var pathCount = 0;

  setUp(() {
    camera = FakeCamera();
    micAllowed = true;
    storageAllowed = true;
    storageAsks = 0;
    pathCount = 0;
    controller = CameraController(
      backend: camera,
      newPath: (extension) async => '/shots/${++pathCount}.$extension',
      allowMicrophone: () async => micAllowed,
      allowStorage: () async {
        storageAsks++;
        return storageAllowed;
      },
    );
  });

  tearDown(() => controller.dispose());

  group('opening', () {
    test('opens the back camera in photo mode and is ready', () async {
      await controller.open();
      expect(camera.calls.first, 'open back photo');
      expect(controller.status, CameraStatus.ready);
      expect(controller.info!.textureId, 7);
    });

    test('a camera that will not open says why', () async {
      camera.failOpen = true;
      await controller.open();
      expect(controller.status, CameraStatus.failed);
      expect(controller.message, 'The camera is in use.');
    });

    test('opens on the lens it was last left on', () async {
      final again = CameraController(
        backend: camera,
        newPath: (e) async => '/x.$e',
        allowMicrophone: () async => true,
        allowStorage: () async => true,
        initialLens: CameraLens.front,
      );
      await again.open();
      expect(camera.calls.first, 'open front photo');
      again.dispose();
    });
  });

  group('saved to the gallery', () {
    test('a photo goes straight to the gallery and carries its address', () async {
      await controller.open();
      final shot = await controller.shutter();
      expect(camera.lastGallery, isTrue);
      expect(shot!.uri, 'content://media//shots/1.jpg');
      expect(storageAsks, 0, reason: 'Android 11 and up need no permission for it');
    });

    test('a video goes straight to the gallery too', () async {
      await controller.open();
      await controller.setMode(CameraMode.video);
      await controller.shutter();
      camera.recordedMs = 2000;
      final shot = await controller.shutter();
      expect(camera.lastGallery, isTrue);
      expect(shot!.uri, 'content://media//shots/1.mp4');
    });

    test('where the phone needs storage access it is asked for', () async {
      camera.galleryNeedsPermission = true;
      await controller.open();
      await controller.shutter();
      expect(storageAsks, 1);
      expect(camera.lastGallery, isTrue);
    });

    test('refused, the shot is kept in SlimShot, said once', () async {
      camera.galleryNeedsPermission = true;
      storageAllowed = false;
      await controller.open();
      final first = await controller.shutter();
      expect(camera.lastGallery, isFalse);
      expect(first!.uri, isNull);
      expect(controller.takeMessage(), kGalleryOffMessage);

      await controller.shutter();
      expect(controller.takeMessage(), isNull, reason: 'said once');
    });
  });

  group('a photo', () {
    test('the shutter takes one and hands it back', () async {
      await controller.open();
      final shot = await controller.shutter();
      expect(shot, isA<PhotoShot>());
      expect(shot!.path, '/shots/1.jpg');
      expect(camera.calls, contains('photo /shots/1.jpg'));
    });

    test('a second tap while one is being taken takes nothing', () async {
      await controller.open();
      camera.photoGate = Completer<void>();
      final first = controller.shutter();
      expect(await controller.shutter(), isNull);
      camera.photoGate!.complete();
      expect(await first, isA<PhotoShot>());
      expect(camera.calls.where((c) => c.startsWith('photo')), hasLength(1));
    });

    test('a photo that fails says why and is no shot', () async {
      final failing = CameraController(
        backend: _FailingPhotoCamera(),
        newPath: (e) async => '/x.$e',
        allowMicrophone: () async => true,
        allowStorage: () async => true,
      );
      await failing.open();
      expect(await failing.shutter(), isNull);
      expect(failing.message, 'The photo could not be taken.');
      expect(failing.status, CameraStatus.ready, reason: 'the camera is still usable');
      failing.dispose();
    });
  });

  test('a mode the camera refuses leaves it in the mode it had', () async {
    camera.refuseMode = CameraMode.video;
    await controller.open();
    await controller.setMode(CameraMode.video);
    expect(controller.mode, CameraMode.photo);
    expect(controller.status, CameraStatus.ready);
    expect(controller.message, 'Video is not available.');
    expect(camera.calls.last, 'configure back photo off');
  });

  group('a video', () {
    setUp(() async {
      await controller.open();
      await controller.setMode(CameraMode.video);
    });

    test('switching to video rebinds the camera for video', () {
      expect(camera.calls, contains('configure back video off'));
      expect(controller.mode, CameraMode.video);
    });

    test('tap to start, tap to stop: one video', () async {
      expect(await controller.shutter(), isNull, reason: 'the first tap starts it');
      expect(controller.recording, RecordingState.recording);
      camera.recordedMs = 4200;
      final shot = await controller.shutter();
      expect(shot, isA<VideoShot>());
      expect(shot!.path, '/shots/1.mp4');
      expect((shot as VideoShot).durationMs, 4200);
      expect(controller.recording, RecordingState.idle);
    });

    test('pause and carry on in the same video', () async {
      await controller.shutter();
      await controller.pauseOrResume();
      expect(controller.recording, RecordingState.paused);
      await controller.pauseOrResume();
      expect(controller.recording, RecordingState.recording);
      expect(camera.calls.where((c) => c.startsWith('record')), hasLength(1));
      expect(camera.calls, containsAllInOrder(['pause', 'resume']));
    });

    test('records with sound when the microphone is allowed', () async {
      await controller.shutter();
      expect(camera.lastAudio, isTrue);
    });

    test('records without sound, and says so, when it is not', () async {
      micAllowed = false;
      await controller.shutter();
      expect(camera.lastAudio, isFalse);
      expect(controller.message, contains('without sound'));
    });

    test('a recording with nothing in it is no shot', () async {
      await controller.shutter();
      camera.recordedMs = 0;
      expect(await controller.shutter(), isNull);
      expect(controller.message, isNotNull);
    });

    test('the running time follows the camera', () async {
      await controller.shutter();
      camera.emit(const RecordingProgress(durationMs: 7300, paused: false));
      await Future<void>.delayed(Duration.zero);
      expect(controller.recordedMs, 7300);
      expect(formatRecordingTime(controller.recordedMs), '0:07');
    });

    test('a recording the camera ended by itself still becomes a shot', () async {
      // The app left the screen mid-take: CameraX finalizes what it has.
      await controller.shutter();
      camera.emit(const RecordingEnded(
        path: '/gallery/1.mp4',
        uri: 'content://media/1',
        durationMs: 3000,
      ));
      await Future<void>.delayed(Duration.zero);
      expect(controller.recording, RecordingState.idle);
      final shot = controller.takeEndedShot();
      expect(shot, isA<VideoShot>());
      expect(shot!.path, '/gallery/1.mp4', reason: 'where the camera saved it');
      expect(shot.uri, 'content://media/1');
      expect(controller.takeEndedShot(), isNull, reason: 'taken once');
    });
  });

  group('while recording', () {
    setUp(() async {
      await controller.open();
      await controller.setMode(CameraMode.video);
      await controller.shutter();
    });

    test('the mode cannot change', () async {
      await controller.setMode(CameraMode.photo);
      expect(controller.mode, CameraMode.video);
    });

    test('the camera cannot flip', () async {
      await controller.flip();
      expect(controller.lens, CameraLens.back);
    });
  });

  group('flash', () {
    test('a photo cycles off, auto, on', () async {
      await controller.open();
      await controller.cycleFlash();
      expect(controller.flash, CameraFlash.auto);
      await controller.cycleFlash();
      expect(controller.flash, CameraFlash.on);
      await controller.cycleFlash();
      expect(controller.flash, CameraFlash.off);
      expect(camera.calls, containsAllInOrder(['flash auto', 'flash on', 'flash off']));
    });

    test('a video has a torch: off and on only', () async {
      await controller.open();
      await controller.setMode(CameraMode.video);
      await controller.cycleFlash();
      expect(controller.flash, CameraFlash.on);
      await controller.cycleFlash();
      expect(controller.flash, CameraFlash.off);
    });

    test('each mode keeps its own flash', () async {
      // A photo's flash on must not become a torch blazing in video.
      await controller.open();
      await controller.cycleFlash(); // auto
      await controller.setMode(CameraMode.video);
      expect(controller.flash, CameraFlash.off);
      expect(camera.calls, contains('configure back video off'),
          reason: "the camera is bound with the new mode's flash, never the old");
      await controller.setMode(CameraMode.photo);
      expect(controller.flash, CameraFlash.auto);
      expect(camera.calls, contains('configure back photo auto'));
    });

    test('a lens without a flash offers none', () async {
      await controller.open();
      await controller.flip();
      expect(controller.info!.hasFlash, isFalse);
      await controller.cycleFlash();
      expect(controller.flash, CameraFlash.off);
    });
  });

  group('zoom and focus', () {
    test('zoom stays inside the camera\'s range', () async {
      await controller.open();
      await controller.zoomTo(20);
      expect(controller.zoom, 8);
      await controller.zoomTo(0.2);
      expect(controller.zoom, 1);
    });

    test('flipping the camera resets the zoom', () async {
      await controller.open();
      await controller.zoomTo(3);
      await controller.flip();
      expect(controller.zoom, 1);
      expect(controller.lens, CameraLens.front);
    });

    test('a tap focuses where it landed', () async {
      await controller.open();
      await controller.focusAt(const Offset(0.25, 0.75));
      expect(camera.calls, contains('focus 0.25 0.75'));
    });
  });

  group('the camera taken away', () {
    test('says why, and is ready again when it comes back', () async {
      await controller.open();
      camera.emit(const CameraAvailability(open: false, message: 'The camera is in use by another app.'));
      await Future<void>.delayed(Duration.zero);
      expect(controller.status, CameraStatus.failed);
      expect(controller.message, 'The camera is in use by another app.');

      camera.emit(const CameraAvailability(open: true));
      await Future<void>.delayed(Duration.zero);
      expect(controller.status, CameraStatus.ready);
      expect(controller.message, isNull);
    });

    test('a camera that never opened is not made ready by the event', () async {
      camera.failOpen = true;
      await controller.open();
      camera.emit(const CameraAvailability(open: true));
      await Future<void>.delayed(Duration.zero);
      expect(controller.status, CameraStatus.failed);
      expect(controller.message, 'The camera is in use.');
    });
  });

  test('the running time reads minutes and seconds', () {
    expect(formatRecordingTime(0), '0:00');
    expect(formatRecordingTime(65 * 1000), '1:05');
    expect(formatRecordingTime(3603 * 1000), '1:00:03');
  });
}
