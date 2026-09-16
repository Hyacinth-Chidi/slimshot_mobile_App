import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/mask/clip_mask.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/mask_panel.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/value_ruler.dart';

/// The Mask panel: a shape, a feather, an invert — the window itself is
/// placed on the canvas, which is why this is an in-place panel and not a
/// sheet.
void main() {
  VideoSegment clip() => VideoSegment(id: 'a', sourceStart: 0, sourceEnd: 10);

  VideoEditorNotifier notifierWith(VideoSegment segment) {
    return VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        segments: [segment],
        selectedSegmentId: segment.id,
        isClipSelected: true,
        activeToolId: 'mask',
      );
  }

  Future<void> pump(WidgetTester tester, VideoEditorNotifier n) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [videoEditorProvider.overrideWith((ref) => n)],
        child: const MaterialApp(
          home: Scaffold(
            body: Column(mainAxisSize: MainAxisSize.min, children: [MaskPanel()]),
          ),
        ),
      ),
    );
  }

  testWidgets('offers the four shapes, None first', (tester) async {
    await pump(tester, notifierWith(clip()));
    for (final label in ['None', 'Rectangle', 'Circle', 'Linear']) {
      expect(find.text(label), findsOneWidget);
    }
    // With no mask there is nothing to feather or invert.
    expect(find.byType(ValueRuler), findsNothing);
  });

  testWidgets('choosing a shape places a default window, one undo step',
      (tester) async {
    final n = notifierWith(clip());
    await pump(tester, n);
    await tester.tap(find.text('Circle'));
    await tester.pumpAndSettle();

    final mask = n.state.segments.single.mask;
    expect(mask.shape, ClipMaskShape.circle);
    expect(mask.centerX, 0.5);
    expect(mask.centerY, 0.5);
    // Now there is a window, its feather and invert appear.
    expect(find.byType(ValueRuler), findsOneWidget);
    expect(find.byKey(const Key('mask_invert')), findsOneWidget);

    n.undo();
    expect(n.state.segments.single.mask, ClipMask.none);
  });

  testWidgets('switching shape keeps the window where it was', (tester) async {
    final n = notifierWith(clip().copyWith(
      mask: const ClipMask(shape: ClipMaskShape.rectangle, centerX: 0.3, centerY: 0.2, width: 0.4, height: 0.3),
    ));
    await pump(tester, n);
    await tester.tap(find.text('Circle'));
    await tester.pumpAndSettle();
    final mask = n.state.segments.single.mask;
    expect(mask.shape, ClipMaskShape.circle);
    expect(mask.centerX, 0.3);
    expect(mask.width, 0.4);
  });

  testWidgets('the feather ruler writes live, one undo step per drag',
      (tester) async {
    final n = notifierWith(clip().copyWith(
      mask: const ClipMask(shape: ClipMaskShape.rectangle, feather: 0.05),
    ));
    await pump(tester, n);
    await tester.drag(find.byType(ValueRuler), const Offset(50, 0));
    await tester.pumpAndSettle();
    expect(n.state.segments.single.mask.feather,
        closeTo(0.05 + 50 * kMaskFeatherPerPixel, 1e-6));
    n.undo();
    expect(n.state.segments.single.mask.feather, 0.05);
    expect(n.state.canUndo, isFalse);
  });

  testWidgets('invert flips the window, None removes it', (tester) async {
    final n = notifierWith(clip().copyWith(
      mask: const ClipMask(shape: ClipMaskShape.linear),
    ));
    await pump(tester, n);
    await tester.tap(find.byKey(const Key('mask_invert')));
    await tester.pumpAndSettle();
    expect(n.state.segments.single.mask.inverted, isTrue);

    await tester.tap(find.text('None'));
    await tester.pumpAndSettle();
    expect(n.state.segments.single.mask, ClipMask.none);
  });
}
