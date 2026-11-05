import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/camera/logic/camera_geometry.dart';

void main() {
  group('the preview as it is shown', () {
    test('a sensor turned a quarter shows its buffer on its side', () {
      // A phone's back camera delivers 1920x1080 landscape buffers that are
      // shown upright as 1080x1920.
      expect(displayedPreviewSize(1920, 1080, 90), const Size(1080, 1920));
      expect(displayedPreviewSize(1920, 1080, 270), const Size(1080, 1920));
    });

    test('unturned or turned half way it keeps its shape', () {
      expect(displayedPreviewSize(1920, 1080, 0), const Size(1920, 1080));
      expect(displayedPreviewSize(1920, 1080, 180), const Size(1920, 1080));
    });
  });

  group('covering the screen', () {
    test('a 9:16 picture on a taller screen fills the height and crops the sides', () {
      const screen = Size(360, 800);
      final rect = previewCoverRect(const Size(1080, 1920), screen);
      expect(rect.height, closeTo(800, 1e-9));
      expect(rect.width, closeTo(450, 1e-9));
      expect(rect.center.dx, closeTo(180, 1e-9), reason: 'centred');
      expect(rect.top, closeTo(0, 1e-9));
    });

    test('a 9:16 picture on a wider screen fills the width and crops top and bottom', () {
      const screen = Size(600, 800);
      final rect = previewCoverRect(const Size(1080, 1920), screen);
      expect(rect.width, closeTo(600, 1e-9));
      expect(rect.height, closeTo(600 * 16 / 9, 1e-9));
      expect(rect.center.dy, closeTo(400, 1e-9));
    });

    test('an unknown picture size fills the screen as it is', () {
      expect(previewCoverRect(Size.zero, const Size(360, 800)),
          const Rect.fromLTWH(0, 0, 360, 800));
    });
  });

  group('a tap to focus', () {
    const screen = Size(360, 800);
    const picture = Size(1080, 1920);

    test('the middle of the screen is the middle of the picture', () {
      final p = focusPointFor(const Offset(180, 400), screen, picture)!;
      expect(p.dx, closeTo(0.5, 1e-9));
      expect(p.dy, closeTo(0.5, 1e-9));
    });

    test('a tap is measured on the whole picture, crop included', () {
      // The picture is 450 wide, 45 px cut off each side: the screen's left
      // edge is 45/450 = 0.1 of the way across it.
      final p = focusPointFor(const Offset(0, 0), screen, picture)!;
      expect(p.dx, closeTo(0.1, 1e-9));
      expect(p.dy, closeTo(0.0, 1e-9));
    });

    test('a tap outside the picture is no point', () {
      expect(focusPointFor(const Offset(-5, 400), screen, picture), isNull);
      expect(focusPointFor(const Offset(180, 900), screen, picture), isNull);
    });
  });

  group('turning the texture upright', () {
    test('straight from the camera, the texture is already upright and mirrored', () {
      // The camera's own transform turns the sensor's picture for the phone
      // held as it is meant to be, and mirrors a selfie: nothing is left to do.
      final back = previewTurns(cameraTransform: true, rotation: 90, mirrored: false, displayRotation: 0);
      expect(back.quarterTurns, 0);
      expect(back.mirror, isFalse);
      final front = previewTurns(cameraTransform: true, rotation: 270, mirrored: true, displayRotation: 0);
      expect(front.quarterTurns, 0);
      expect(front.mirror, isFalse, reason: 'mirroring it again would undo the selfie');
    });

    test('straight from the camera on a screen turned from its natural way, '
        'only the screen\'s turn is left', () {
      final turns = previewTurns(cameraTransform: true, rotation: 0, mirrored: false, displayRotation: 90);
      expect(turns.quarterTurns, 1);
    });

    test('through a processor the buffer arrives as the sensor wrote it', () {
      final back = previewTurns(cameraTransform: false, rotation: 90, mirrored: false, displayRotation: 0);
      expect(back.quarterTurns, 1);
      expect(back.mirror, isFalse);
      final front = previewTurns(cameraTransform: false, rotation: 270, mirrored: true, displayRotation: 0);
      expect(front.quarterTurns, 3);
      expect(front.mirror, isTrue);
    });
  });

  group('pinch to zoom', () {
    test('scales from where the pinch began, within the camera\'s range', () {
      expect(zoomAfterPinch(start: 1, scale: 2, min: 1, max: 8), 2);
      expect(zoomAfterPinch(start: 3, scale: 0.5, min: 1, max: 8), 1.5);
      expect(zoomAfterPinch(start: 6, scale: 3, min: 1, max: 8), 8);
      expect(zoomAfterPinch(start: 1, scale: 0.2, min: 0.6, max: 8), 0.6);
    });
  });
}
