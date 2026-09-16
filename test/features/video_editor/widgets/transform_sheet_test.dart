import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/animation/animatable_double.dart';
import 'package:slimshotai/features/video_editor/logic/animation/clip_keyframes.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/transform_sheet.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/value_ruler.dart';

/// The Transform sheet: Scale / Rotate / Position, each a ruler.
///
/// Every ruler writes through the edit rule and shows what its write will
/// target, so the sheet inherits keyframing without a keyframe control of its
/// own — the same shape as the volume slider and the pinch gesture.
void main() {
  /// The engine's override channel is fire-and-forget from the sheet; in a
  /// test there is no platform, so it is answered with nothing rather than
  /// left to throw `MissingPluginException` out of an unawaited future.
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('slimshot_ai/native_timeline_preview'),
      (call) async {
        calls.add(call);
        return null;
      },
    );
  });

  VideoSegment clip(String id) =>
      VideoSegment(id: id, sourceStart: 0, sourceEnd: 10);

  VideoEditorNotifier notifierWith(
    List<VideoSegment> segments, {
    String? selectedSegmentId,
    double position = 0.0,
  }) {
    return VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        segments: segments,
        selectedSegmentId: selectedSegmentId,
        isClipSelected: selectedSegmentId != null,
        currentPlaybackPosition: position,
      );
  }

  Future<void> pump(WidgetTester tester, VideoEditorNotifier notifier) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [videoEditorProvider.overrideWith((ref) => notifier)],
        child: const MaterialApp(
          home: Scaffold(body: TransformSheet()),
        ),
      ),
    );
    await tester.pump();
  }

  VideoSegment only(VideoEditorNotifier n) => n.state.segments.first;

  group('shape', () {
    testWidgets('three tabs, Scale first, one ruler', (tester) async {
      await pump(tester, notifierWith([clip('a')], selectedSegmentId: 'a'));
      expect(find.text('Scale'), findsOneWidget);
      expect(find.text('Rotate'), findsOneWidget);
      expect(find.text('Position'), findsOneWidget);
      expect(find.byType(ValueRuler), findsOneWidget);
    });

    testWidgets('Position shows two rulers, X and Y', (tester) async {
      await pump(tester, notifierWith([clip('a')], selectedSegmentId: 'a'));
      await tester.tap(find.text('Position'));
      await tester.pumpAndSettle();
      expect(find.byType(ValueRuler), findsNWidgets(2));
      expect(find.text('X'), findsOneWidget);
      expect(find.text('Y'), findsOneWidget);
    });

    testWidgets('Rotate shows one ruler in degrees', (tester) async {
      await pump(tester, notifierWith([clip('a')], selectedSegmentId: 'a'));
      await tester.tap(find.text('Rotate'));
      await tester.pumpAndSettle();
      expect(find.byType(ValueRuler), findsOneWidget);
      expect(find.textContaining('°'), findsOneWidget);
    });

    testWidgets('Rotate offers two mirrors, each one undo step', (tester) async {
      // A mirror is the one orientation change a rotation cannot make, and it
      // lives where a user looks for it.
      final n = notifierWith([clip('a')], selectedSegmentId: 'a');
      await pump(tester, n);
      await tester.tap(find.text('Rotate'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('flip_horizontal')));
      await tester.pump();
      expect(n.state.segments.single.flipHorizontal, isTrue);
      expect(n.state.segments.single.flipVertical, isFalse);

      await tester.tap(find.byKey(const Key('flip_vertical')));
      await tester.pump();
      expect(n.state.segments.single.flipVertical, isTrue);

      n.undo();
      expect(n.state.segments.single.flipVertical, isFalse);
      expect(n.state.segments.single.flipHorizontal, isTrue);
    });

    testWidgets('Apply to all copies the placement onto every other clip',
        (tester) async {
      final n = notifierWith(
        [
          clip('a').copyWith(canvasScale: const AnimatableDouble(baseValue: 2.0)),
          clip('b'),
          clip('c'),
        ],
        selectedSegmentId: 'a',
      );
      await pump(tester, n);
      await tester.tap(find.byKey(const Key('transform_apply_all')));
      await tester.pump();
      // Let the confirmation toast run its course inside the test clock.
      await tester.pump(const Duration(seconds: 5));

      expect(n.state.segments[1].canvasScale.baseValue, 2.0);
      expect(n.state.segments[2].canvasScale.baseValue, 2.0);
    });

    testWidgets('with no clip selected it says so rather than lying',
        (tester) async {
      // Every tab writes a *clip* property, so with nothing selected there is
      // nothing to write — the same rule the volume panel follows.
      await pump(tester, notifierWith([clip('a')]));
      expect(find.byType(ValueRuler), findsNothing);
      expect(find.textContaining('Select a clip'), findsOneWidget);
    });
  });

  group('writes go through the edit rule', () {
    testWidgets('dragging Scale writes the base on an unkeyframed clip',
        (tester) async {
      final n = notifierWith([clip('a')], selectedSegmentId: 'a');
      await pump(tester, n);
      await tester.drag(find.byType(ValueRuler), const Offset(50, 0));
      await tester.pump();
      expect(only(n).canvasScale.baseValue, greaterThan(1.0));
      expect(only(n).canvasScale.keyframes, isEmpty);
    });

    testWidgets('dragging Scale writes the keyframe on a keyframed clip',
        (tester) async {
      // Which is the whole point: the sheet has no keyframe UI, and does not
      // need one.
      final n = notifierWith([clip('a')], selectedSegmentId: 'a');
      n.addKeyframeAtPlayhead(); // at 0.0
      n.updatePlaybackPosition(10.0);
      n.addKeyframeAtPlayhead(); // at 1.0
      await pump(tester, n);

      await tester.drag(find.byType(ValueRuler), const Offset(50, 0));
      await tester.pump();

      final s = only(n);
      expect(s.canvasScale.baseValue, 1.0, reason: 'base untouched');
      expect(s.canvasScale.keyframes.last.value, greaterThan(1.0));
      expect(s.canvasScaleAt(0.0), 1.0, reason: 'the first diamond holds');
    });

    testWidgets('dragging Rotate writes degrees to the sixth property',
        (tester) async {
      final n = notifierWith([clip('a')], selectedSegmentId: 'a');
      await pump(tester, n);
      await tester.tap(find.text('Rotate'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ValueRuler), const Offset(40, 0));
      await tester.pump();
      // 40px at 0.5°/px is 20°, no snap point nearby.
      expect(only(n).canvasRotationAt(0.5), closeTo(20.0, 1e-6));
    });

    testWidgets('Position X and Y write their own axes only', (tester) async {
      final n = notifierWith([clip('a')], selectedSegmentId: 'a');
      await pump(tester, n);
      await tester.tap(find.text('Position'));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ValueRuler).first, const Offset(40, 0));
      await tester.pump();
      expect(only(n).canvasOffsetXAt(0.5), greaterThan(0.0));
      expect(only(n).canvasOffsetYAt(0.5), 0.0);

      await tester.drag(find.byType(ValueRuler).last, const Offset(-40, 0));
      await tester.pump();
      expect(only(n).canvasOffsetYAt(0.5), lessThan(0.0));
    });

    testWidgets('a drag never disturbs the properties it is not editing',
        (tester) async {
      // Scale is dragged; rotation and position must be exactly what they
      // were, not "written back as what they resolved to", which on an
      // unkeyframed clip is the same thing but on a keyframed one is not.
      final n = notifierWith([
        clip('a').copyWith(
          canvasRotation: const AnimatableDouble(baseValue: 30.0),
          canvasOffsetX: const AnimatableDouble(baseValue: 0.2),
        ),
      ], selectedSegmentId: 'a');
      await pump(tester, n);
      await tester.drag(find.byType(ValueRuler), const Offset(30, 0));
      await tester.pump();
      expect(only(n).canvasRotationAt(0.5), 30.0);
      expect(only(n).canvasOffsetXAt(0.5), closeTo(0.2, 1e-9));
    });
  });

  group('the engine hears it live', () {
    testWidgets('each drag frame reaches the override channel with the angle',
        (tester) async {
      // Not a timeline push per frame — the same lightweight channel the pinch
      // uses, so the picture follows the finger without re-preparing players.
      final n = notifierWith([clip('a')], selectedSegmentId: 'a');
      await pump(tester, n);
      await tester.tap(find.text('Rotate'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ValueRuler), const Offset(40, 0));
      await tester.pump();

      final overrides = calls.where((c) => c.method == 'setClipTransform');
      expect(overrides, isNotEmpty);
      final last = overrides.last.arguments as Map;
      expect(last['clipId'], 'a');
      expect((last['rotation'] as num).toDouble(), closeTo(20.0, 1e-6));
    });
  });

  group('undo', () {
    testWidgets('a drag is one undo step', (tester) async {
      final n = notifierWith([clip('a')], selectedSegmentId: 'a');
      await pump(tester, n);
      final before = only(n).canvasScale;

      final gesture = await tester.startGesture(
          tester.getCenter(find.byType(ValueRuler)));
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(10, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();
      expect(only(n).canvasScale.baseValue, greaterThan(1.0));

      n.undo();
      expect(only(n).canvasScale, before);
    });

    testWidgets('tapping the readout resets that value, undoably',
        (tester) async {
      final n = notifierWith([
        clip('a').copyWith(canvasScale: const AnimatableDouble(baseValue: 2.4)),
      ], selectedSegmentId: 'a');
      await pump(tester, n);
      await tester.tap(find.byKey(const Key('value_ruler_readout')));
      await tester.pump();
      expect(only(n).canvasScale.baseValue, 1.0);
      n.undo();
      expect(only(n).canvasScale.baseValue, 2.4);
    });
  });

  group('what a ruler shows', () {
    testWidgets('the value the write will target, not the base',
        (tester) async {
      // A clip scaling 1 → 3 with the playhead halfway: the ruler must read
      // 2.0, because that is what a drag would move from. The base (1.0) is
      // what the volume slider showed once, and the thumb was pinned.
      final n = notifierWith([clip('a')], selectedSegmentId: 'a');
      n.addKeyframeAtPlayhead();
      n.updatePlaybackPosition(10.0);
      n.setClipProperty(ClipProperty.canvasScale, 3.0);
      n.updatePlaybackPosition(5.0);
      await pump(tester, n);

      final ruler = tester.widget<ValueRuler>(find.byType(ValueRuler));
      expect(ruler.value, closeTo(2.0, 1e-9));
      expect(find.text('2.00×'), findsOneWidget);
    });
  });
}
