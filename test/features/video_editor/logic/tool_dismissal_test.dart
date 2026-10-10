import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/tool_dismissal.dart';

/// How an open tool panel is dismissed by gestures that are not its ✓ or ✕.
///
/// Device-reported, twice: a tap on the canvas's empty space did nothing to an
/// open panel, and the system Back button — pressed to close the panel the way
/// it closes a sheet — left the editor for the home screen instead. A panel is
/// modal in spirit, so both now dismiss it, **keeping** what the user set (the
/// way a sheet's dismissal keeps its live edits; ✕ remains the explicit
/// discard).
///
/// The picture itself is the tools' to use — dragging a mask window or a crop
/// corner, tapping to play — so only the empty space **around** it dismisses,
/// and it dismisses every panel, the ones that edit on the picture included.
///
/// A panel without the bar (Mask) closes the same ways, minus the two buttons.
void main() {
  group('a tap around the picture', () {
    // The 9:16 picture in a wider preview area: the empty space beside it is
    // where a tap clears the selection and closes the panel.
    const picture = Rect.fromLTWH(200, 0, 360, 640);

    test('counts out in the space beside the picture', () {
      expect(tapIsBesidePicture(const Offset(40, 300), picture), isTrue);
      expect(tapIsBesidePicture(const Offset(720, 300), picture), isTrue);
    });

    test('never counts on the picture', () {
      expect(tapIsBesidePicture(const Offset(380, 320), picture), isFalse);
      expect(tapIsBesidePicture(const Offset(201, 1), picture), isFalse);
    });

    test('does not count just past the edge, where a handle hangs over', () {
      // A text's or overlay's handles and the crop corners are drawn half
      // past the picture's edge, and Flutter cannot hit them out there: a
      // slightly missed handle must not throw the selection or panel away.
      final justOutside = picture.left - (kPictureTapMarginPx - 1);
      expect(tapIsBesidePicture(Offset(justOutside, 300), picture), isFalse);
      final pastMargin = picture.left - (kPictureTapMarginPx + 1);
      expect(tapIsBesidePicture(Offset(pastMargin, 300), picture), isTrue);
    });
  });

  group('the system Back button', () {
    test('closes an open tool rather than leaving the editor', () {
      expect(backActionFor(activeToolId: 'volume'), BackAction.closeTool);
      // Even a canvas-editing one: Back is an explicit "done here".
      expect(backActionFor(activeToolId: 'crop'), BackAction.closeTool);
    });

    test('leaves the editor when no tool is open', () {
      expect(backActionFor(activeToolId: null), BackAction.leaveEditor);
    });
  });

  group('the ✕ / title / ✓ bar', () {
    test('is not on the Mask panel', () {
      // Every Mask change applies as it is made and its ✕ undid nothing, so
      // the bar was two buttons that both just closed it, plus the name of
      // the tool the user had just tapped. The space goes to the shapes.
      expect(toolPanelHasHeader('mask'), isFalse);
    });

    test('stays on every other panel', () {
      // On Volume and Opacity ✕ is the only way to throw a drag away.
      for (final id in ['volume', 'opacity', 'speed', 'crop', 'clip_crop', 'zoom']) {
        expect(toolPanelHasHeader(id), isTrue, reason: id);
      }
    });
  });
}
