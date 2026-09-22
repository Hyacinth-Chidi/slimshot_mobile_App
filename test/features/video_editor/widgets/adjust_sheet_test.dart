import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimshotai/features/video_editor/logic/color/color_adjustments.dart';
import 'package:slimshotai/features/video_editor/models/video_editor_state.dart';
import 'package:slimshotai/features/video_editor/models/video_segment.dart';
import 'package:slimshotai/features/video_editor/providers/video_editor_notifier.dart';
import 'package:slimshotai/features/video_editor/services/video_editor_service.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/adjust_sheet.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/apply_to_all_toggle.dart';
import 'package:slimshotai/features/video_editor/widgets/panels/value_ruler.dart';

/// The Adjust sheet: four rulers behind four pills, writing live to the clip
/// or to the project as the apply-to-all toggle decides.
void main() {
  VideoSegment clip(String id) =>
      VideoSegment(id: id, sourceStart: 0, sourceEnd: 10);

  VideoEditorNotifier notifierWith(List<VideoSegment> segments,
      {String? selected}) {
    return VideoEditorNotifier(VideoEditorService())
      ..state = VideoEditorState(
        segments: segments,
        selectedSegmentId: selected,
        isClipSelected: selected != null,
      );
  }

  Future<void> pump(WidgetTester tester, VideoEditorNotifier n) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [videoEditorProvider.overrideWith((ref) => n)],
        child: const MaterialApp(home: Scaffold(body: AdjustSheet())),
      ),
    );
  }

  testWidgets('four pills, Brightness first, one ruler', (tester) async {
    await pump(tester, notifierWith([clip('a')], selected: 'a'));
    for (final name in ['Brightness', 'Contrast', 'Saturation', 'Temperature']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.byType(ValueRuler), findsOneWidget);
  });

  testWidgets('with a clip selected, a drag writes that clip', (tester) async {
    final n = notifierWith([clip('a'), clip('b')], selected: 'a');
    await pump(tester, n);

    await tester.drag(find.byType(ValueRuler), const Offset(40, 0));
    await tester.pumpAndSettle();

    final a = n.state.segments.first.adjustments;
    expect(a.brightness, closeTo(40 * kAdjustUnitsPerPixel, 1e-6));
    expect(n.state.segments.last.adjustments, ColorAdjustments.none);
    expect(n.state.adjustments, ColorAdjustments.none);
  });

  testWidgets('switching to apply-to-all writes the project instead',
      (tester) async {
    final n = notifierWith([clip('a'), clip('b')], selected: 'a');
    await pump(tester, n);

    await tester.tap(find.byType(ApplyToAllToggle));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Temperature'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ValueRuler), const Offset(-40, 0));
    await tester.pumpAndSettle();

    expect(n.state.adjustments.temperature,
        closeTo(-40 * kAdjustUnitsPerPixel, 1e-6));
    expect(n.state.segments.first.adjustments, ColorAdjustments.none);
  });

  testWidgets('from the root menu there is no toggle and the project is written',
      (tester) async {
    final n = notifierWith([clip('a')]);
    await pump(tester, n);
    expect(find.byType(ApplyToAllToggle), findsNothing);

    await tester.drag(find.byType(ValueRuler), const Offset(20, 0));
    await tester.pumpAndSettle();
    expect(n.state.adjustments.brightness, closeTo(20 * kAdjustUnitsPerPixel, 1e-6));
  });

  testWidgets('a drag is one undo step', (tester) async {
    final n = notifierWith([clip('a')], selected: 'a');
    await pump(tester, n);
    await tester.drag(find.byType(ValueRuler), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(n.state.segments.single.adjustments.isIdentity, isFalse);

    n.undo();
    expect(n.state.segments.single.adjustments, ColorAdjustments.none);
    expect(n.state.canUndo, isFalse);
  });

  testWidgets('the ruler shows the level it writes', (tester) async {
    final n = notifierWith([clip('a')], selected: 'a')
      ..state = notifierWith([clip('a')], selected: 'a').state.copyWith(
            segments: [clip('a').copyWith(adjustments: const ColorAdjustments(brightness: 0.4))],
            adjustments: const ColorAdjustments(brightness: -0.2),
          );
    await pump(tester, n);
    expect(tester.widget<ValueRuler>(find.byType(ValueRuler)).value, closeTo(0.4, 1e-9));

    await tester.tap(find.byType(ApplyToAllToggle));
    await tester.pumpAndSettle();
    expect(tester.widget<ValueRuler>(find.byType(ValueRuler)).value, closeTo(-0.2, 1e-9));
  });

  testWidgets('the tick dismisses the sheet', (tester) async {
    final n = notifierWith([clip('a')], selected: 'a');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [videoEditorProvider.overrideWith((ref) => n)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => const AdjustSheet(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('adjust_done')));
    await tester.pumpAndSettle();
    expect(find.byType(AdjustSheet), findsNothing);
  });
}
