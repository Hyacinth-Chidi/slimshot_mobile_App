import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/filter_presets.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';

void main() {
  final neon = FilterPresets.allPresets.first;
  final other = FilterPresets.allPresets[1];

  VideoSegment clip(String id, {String? transition}) => VideoSegment(
        id: id,
        sourceStart: 0,
        sourceEnd: 5,
        transitionType: transition,
        transitionDuration: transition == null ? null : 0.8,
      );

  VideoEditorNotifier notifierWith(
    List<VideoSegment> segments, {
    bool filterAppliesToAll = true,
    bool transitionAppliesToAll = false,
    String? selectedSegmentId,
    String? selectedTransitionSegmentId,
  }) {
    return VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        segments: segments,
        filterAppliesToAll: filterAppliesToAll,
        transitionAppliesToAll: transitionAppliesToAll,
        selectedSegmentId: selectedSegmentId,
        selectedTransitionSegmentId: selectedTransitionSegmentId,
      );
  }

  group('filters', () {
    test('apply-to-all sets the project look and leaves clips ungraded', () {
      final notifier = notifierWith([clip('a'), clip('b')]);

      notifier.setSelectedFilter(neon);

      expect(notifier.state.selectedFilter?.id, neon.id);
      expect(notifier.state.segments.every((s) => s.filterId == null), isTrue);
    });

    test('per-clip grades only the selected clip', () {
      final notifier = notifierWith(
        [clip('a'), clip('b')],
        filterAppliesToAll: false,
        selectedSegmentId: 'b',
      );

      notifier.setSelectedFilter(neon);

      expect(notifier.state.segments[0].filterId, isNull);
      expect(notifier.state.segments[1].filterId, neon.id);
      // The project look is untouched, so nothing is graded twice.
      expect(notifier.state.selectedFilter, isNull);
    });

    test('per-clip does nothing when no clip is selected', () {
      final notifier = notifierWith(
        [clip('a'), clip('b')],
        filterAppliesToAll: false,
      );

      notifier.setSelectedFilter(neon);

      expect(notifier.state.segments.every((s) => s.filterId == null), isTrue);
    });

    test('two clips can hold different filters', () {
      final notifier = notifierWith(
        [clip('a'), clip('b')],
        filterAppliesToAll: false,
        selectedSegmentId: 'a',
      );

      notifier.setSelectedFilter(neon);
      notifier.state = notifier.state.copyWith(selectedSegmentId: 'b');
      notifier.setSelectedFilter(other);

      expect(notifier.state.segments[0].filterId, neon.id);
      expect(notifier.state.segments[1].filterId, other.id);
    });

    test('intensity follows the same target as the filter', () {
      final notifier = notifierWith(
        [clip('a'), clip('b')],
        filterAppliesToAll: false,
        selectedSegmentId: 'a',
      );
      notifier.setSelectedFilter(neon);

      notifier.setFilterIntensity(0.5);

      expect(notifier.state.segments[0].filterIntensity, 0.5);
      expect(notifier.state.segments[1].filterIntensity, 1.0);
      expect(notifier.state.filterIntensity, 1.0);
    });

    test('switching to apply-to-all carries the clip look up to the project',
        () {
      // The picture must not change at the moment the switch is flipped.
      final notifier = notifierWith(
        [clip('a'), clip('b')],
        filterAppliesToAll: false,
        selectedSegmentId: 'a',
      );
      notifier.setSelectedFilter(neon);

      notifier.setFilterAppliesToAll(true);

      expect(notifier.state.selectedFilter?.id, neon.id);
      expect(notifier.state.segments.every((s) => s.filterId == null), isTrue,
          reason: 'clip grades are cleared so nothing is graded twice');
    });

    test('switching off pushes the project look down onto every clip', () {
      final notifier = notifierWith([clip('a'), clip('b')]);
      notifier.setSelectedFilter(neon);

      notifier.setFilterAppliesToAll(false);

      expect(notifier.state.selectedFilter, isNull);
      expect(notifier.state.segments.every((s) => s.filterId == neon.id), isTrue);
    });

    test('a clip carries its grade through a split', () {
      final notifier = notifierWith(
        [clip('a')],
        filterAppliesToAll: false,
        selectedSegmentId: 'a',
      );
      notifier.setSelectedFilter(neon);

      notifier.splitAtPosition(2.5);

      expect(notifier.state.segments.length, 2);
      expect(notifier.state.segments.every((s) => s.filterId == neon.id), isTrue);
    });
  });

  group('transitions', () {
    test('apply-to-all writes the transition to every cut but the last', () {
      final notifier = notifierWith(
        [clip('a'), clip('b'), clip('c')],
        transitionAppliesToAll: true,
      );

      notifier.setSegmentTransition('dissolve', 0.6);

      expect(notifier.state.segments[0].transitionType, 'dissolve');
      expect(notifier.state.segments[1].transitionType, 'dissolve');
      expect(notifier.state.segments[0].transitionDuration, 0.6);
      // The final clip has nothing to transition into.
      expect(notifier.state.segments[2].transitionType, isNull);
    });

    test('apply-to-all can clear every transition at once', () {
      final notifier = notifierWith(
        [
          clip('a', transition: 'dissolve'),
          clip('b', transition: 'dissolve'),
          clip('c'),
        ],
        transitionAppliesToAll: true,
      );

      notifier.setSegmentTransition(null);

      expect(
        notifier.state.segments.every((s) => s.transitionType == null),
        isTrue,
      );
    });

    test('off, only the selected seam changes', () {
      final notifier = notifierWith(
        [clip('a'), clip('b'), clip('c')],
        selectedTransitionSegmentId: 'b',
      );

      notifier.setSegmentTransition('dissolve', 0.6);

      expect(notifier.state.segments[0].transitionType, isNull);
      expect(notifier.state.segments[1].transitionType, 'dissolve');
      expect(notifier.state.segments[2].transitionType, isNull);
    });

    test('turning the switch on spreads the selected seam immediately', () {
      final notifier = notifierWith(
        [clip('a', transition: 'dissolve'), clip('b'), clip('c')],
        selectedTransitionSegmentId: 'a',
      );

      notifier.setTransitionAppliesToAll(true);

      expect(notifier.state.segments[0].transitionType, 'dissolve');
      expect(notifier.state.segments[1].transitionType, 'dissolve');
      expect(notifier.state.segments[2].transitionType, isNull);
    });

    test('a transition never survives on the last clip after reorder', () {
      final notifier = notifierWith(
        [clip('a'), clip('b'), clip('c')],
        transitionAppliesToAll: true,
      );
      notifier.setSegmentTransition('dissolve', 0.6);

      notifier.reorderSegment(0, 2);

      expect(notifier.state.segments.last.transitionType, isNull);
    });
  });
}
