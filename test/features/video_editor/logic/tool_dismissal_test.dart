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
/// The one exception is deliberate: a tool that edits **on the canvas** must
/// not close because the canvas was touched.
void main() {
  group('a tap on empty canvas space', () {
    test('dismisses a tool that does not edit on the canvas', () {
      for (final id in ['volume', 'speed', 'edit', 'opacity', 'audio']) {
        expect(toolClosesOnCanvasTap(id), isTrue, reason: id);
      }
    });

    test('leaves a canvas-editing tool open', () {
      // Crop and clip crop drag handles on the canvas; zoom pinches it. A
      // stray tap there is part of using the tool, not a request to leave it.
      for (final id in ['crop', 'clip_crop', 'zoom']) {
        expect(toolClosesOnCanvasTap(id), isFalse, reason: id);
      }
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
}
