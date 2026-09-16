import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';

/// Selecting a seam puts the editor into a transition *mode* — and something
/// has to take it back out again.
///
/// `currentMenuId: 'transition'` names a menu whose tool list is deliberately
/// empty, because `TransitionsDrawer` replaces it. So while that mode is on and
/// the sheet is **not** showing, the user is looking at an empty submenu: the
/// device-reported symptom, seen after dismissing the sheet.
void main() {
  VideoEditorNotifier notifierWith() {
    return VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        segments: [
          VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 5),
          VideoSegment(id: 'b', sourceStart: 5, sourceEnd: 10),
        ],
      );
  }

  test('selecting a seam enters the transition menu', () {
    final n = notifierWith();
    n.selectTransition('a');

    expect(n.state.selectedTransitionSegmentId, 'a');
    expect(n.state.currentMenuId, 'transition');
  });

  test('deselecting leaves it, so no empty submenu is left behind', () {
    // The whole fix: the mode is entered by a tap and has to be left when the
    // sheet closes, whichever way it closes — the ✓, the scrim, or Back.
    final n = notifierWith();
    n.selectTransition('a');

    n.deselectAll();

    expect(n.state.currentMenuId, 'root');
    expect(n.state.selectedTransitionSegmentId, isNull);
  });

  test('leaving is safe to call when nothing was selected', () {
    // A dismiss handler runs on every close, including one where the drawer
    // showed "split the video first" and nothing was ever selected.
    final n = notifierWith();
    n.deselectAll();

    expect(n.state.currentMenuId, 'root');
    expect(n.state.selectedTransitionSegmentId, isNull);
  });

  test('a transition applied from the sheet survives leaving the menu', () {
    // Dismissing must not undo the work: only the *selection* and the menu are
    // transient, never the edit.
    final n = notifierWith();
    n.selectTransition('a');
    n.setSegmentTransition('fade', 0.5);
    expect(n.state.segments.first.transitionType, 'fade');

    n.deselectAll();

    expect(n.state.segments.first.transitionType, 'fade');
    expect(n.state.currentMenuId, 'root');
  });
}
