import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';

void main() {
  VideoEditorNotifier notifierWith(List<VideoSegment> segments) {
    return VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(segments: segments);
  }

  List<String> idsOf(VideoEditorNotifier notifier) =>
      notifier.state.segments.map((s) => s.id).toList(growable: false);

  VideoSegment clip(String id, {String? transition}) => VideoSegment(
        id: id,
        sourceStart: 0,
        sourceEnd: 5,
        transitionType: transition,
        transitionDuration: transition == null ? null : 0.8,
      );

  group('reorderSegment', () {
    test('toIndex is the position in the final list', () {
      final notifier = notifierWith([clip('a'), clip('b'), clip('c')]);

      // Carrying the first clip to the end means it ends up at index 2, not at
      // some insertion point computed before the removal.
      notifier.reorderSegment(0, 2);

      expect(idsOf(notifier), ['b', 'c', 'a']);
    });

    test('moves a clip backwards', () {
      final notifier = notifierWith([clip('a'), clip('b'), clip('c')]);

      notifier.reorderSegment(2, 0);

      expect(idsOf(notifier), ['c', 'a', 'b']);
    });

    test('moving to the same place changes nothing', () {
      final notifier = notifierWith([clip('a'), clip('b')]);
      final before = notifier.state;

      notifier.reorderSegment(1, 1);

      expect(notifier.state, same(before));
    });

    test('clamps a target past the end', () {
      final notifier = notifierWith([clip('a'), clip('b'), clip('c')]);

      notifier.reorderSegment(0, 99);

      expect(idsOf(notifier), ['b', 'c', 'a']);
    });

    test('ignores an out-of-range source', () {
      final notifier = notifierWith([clip('a'), clip('b')]);

      notifier.reorderSegment(5, 0);
      notifier.reorderSegment(-1, 0);

      expect(idsOf(notifier), ['a', 'b']);
    });

    test('drops the transition off whatever ends up last', () {
      // `a` transitions into `b`. Carry `a` to the end and that transition has
      // no incoming clip left, so it must not survive the move.
      final notifier = notifierWith([
        clip('a', transition: 'dissolve'),
        clip('b'),
        clip('c'),
      ]);

      notifier.reorderSegment(0, 2);

      expect(idsOf(notifier), ['b', 'c', 'a']);
      expect(notifier.state.segments.last.transitionType, isNull);
      expect(notifier.state.segments.last.transitionDuration, isNull);
    });

    test('a transition on a clip that stays mid-timeline is kept', () {
      final notifier = notifierWith([
        clip('a'),
        clip('b', transition: 'dissolve'),
        clip('c'),
      ]);

      // Move `c` to the front: `b` is still followed by something.
      notifier.reorderSegment(2, 0);

      expect(idsOf(notifier), ['c', 'a', 'b']);
      expect(
        notifier.state.segments.firstWhere((s) => s.id == 'b').transitionType,
        isNull,
        reason: 'b is now last, so its transition goes',
      );
    });

    test('the move is undoable', () {
      final notifier = notifierWith([clip('a'), clip('b'), clip('c')]);

      notifier.reorderSegment(0, 2);
      expect(idsOf(notifier), ['b', 'c', 'a']);

      notifier.undo();
      expect(idsOf(notifier), ['a', 'b', 'c']);
    });
  });
}
