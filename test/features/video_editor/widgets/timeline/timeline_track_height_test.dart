import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/widgets/timeline/scrollable_timeline.dart';

/// How tall the track area is, and who pays when a tool panel opens.
///
/// The editor's canvas is `Expanded`, so whatever the timeline and the bottom
/// area do not claim, the canvas absorbs — and whatever they grow by, the
/// canvas loses. A tool panel is taller than the toolbar it replaces, so
/// opening one used to shrink the canvas and shove the timeline up by the
/// difference while the track area kept the idle slack its floor guarantees.
/// **While a panel is open the timeline gives up that slack first**, so the
/// panel's height comes out of empty track area rather than out of the
/// picture.
void main() {
  group('with the toolbar showing', () {
    test('a sparse project is held at the floor', () {
      // Ruler + one filmstrip is far under 190; the floor keeps a workable
      // track area rather than letting the canvas balloon.
      expect(timelineTrackHeight(contentHeight: 68, compact: false), 190);
    });

    test('a busy project grows to the cap', () {
      expect(timelineTrackHeight(contentHeight: 300, compact: false), 250);
    });

    test('in between, content plus padding', () {
      expect(timelineTrackHeight(contentHeight: 200, compact: false), 216);
    });
  });

  group('with a tool panel open', () {
    test('a sparse project releases its slack down to the content', () {
      expect(timelineTrackHeight(contentHeight: 68, compact: true), 84);
    });

    test('the cap still holds', () {
      expect(timelineTrackHeight(contentHeight: 300, compact: true), 250);
    });

    test('a project already at its content height is unchanged', () {
      // Nothing to release: compact never takes real rows away.
      expect(timelineTrackHeight(contentHeight: 200, compact: true), 216);
    });
  });
}
